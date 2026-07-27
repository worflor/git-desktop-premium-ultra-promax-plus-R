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
class TranslationsZhHans extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsZhHans({
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
             locale: AppLocale.zhHans,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <zh-Hans>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsZhHans _root = this; // ignore: unused_field

  @override
  TranslationsZhHans $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsZhHans(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$zh_Hans app = _Translations$app$zh_Hans._(_root);
  @override
  late final _Translations$backend$zh_Hans backend =
      _Translations$backend$zh_Hans._(_root);
  @override
  late final _Translations$branches$zh_Hans branches =
      _Translations$branches$zh_Hans._(_root);
  @override
  late final _Translations$changes$zh_Hans changes =
      _Translations$changes$zh_Hans._(_root);
  @override
  late final _Translations$common$zh_Hans common =
      _Translations$common$zh_Hans._(_root);
  @override
  late final _Translations$diff$zh_Hans diff = _Translations$diff$zh_Hans._(
    _root,
  );
  @override
  late final _Translations$filament$zh_Hans filament =
      _Translations$filament$zh_Hans._(_root);
  @override
  late final _Translations$history$zh_Hans history =
      _Translations$history$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$zh_Hans historySurgery =
      _Translations$historySurgery$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$zh_Hans onboarding =
      _Translations$onboarding$zh_Hans._(_root);
  @override
  late final _Translations$orrery$zh_Hans orrery =
      _Translations$orrery$zh_Hans._(_root);
  @override
  late final _Translations$palette$zh_Hans palette =
      _Translations$palette$zh_Hans._(_root);
  @override
  late final _Translations$releaseNotes$zh_Hans releaseNotes =
      _Translations$releaseNotes$zh_Hans._(_root);
  @override
  late final _Translations$repoSummary$zh_Hans repoSummary =
      _Translations$repoSummary$zh_Hans._(_root);
  @override
  late final _Translations$review$zh_Hans review =
      _Translations$review$zh_Hans._(_root);
  @override
  late final _Translations$settings$zh_Hans settings =
      _Translations$settings$zh_Hans._(_root);
  @override
  late final _Translations$sync$zh_Hans sync = _Translations$sync$zh_Hans._(
    _root,
  );
  @override
  late final _Translations$xray$zh_Hans xray = _Translations$xray$zh_Hans._(
    _root,
  );
}

// Path: app
class _Translations$app$zh_Hans extends Translations$app$en {
  _Translations$app$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => '设置';
  @override
  String get panelReleaseNotes => '发布说明';
  @override
  String get panelFilamentFindings => 'Filament 发现';
  @override
  String get filamentFindingsUpper => 'FILAMENT 发现';
  @override
  late final _Translations$app$cheatsheet$zh_Hans cheatsheet =
      _Translations$app$cheatsheet$zh_Hans._(_root);
  @override
  String get commandPaletteTooltip => '命令面板   /';
  @override
  String get newDeskFallback => '新 Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => '当前';
  @override
  String get noRepositoryOpen => '未打开仓库';
  @override
  String couldntOpenAsDesk({required Object error}) => '无法作为 Desk 打开：${error}';
  @override
  String couldNotDetectForge({required Object error}) => '无法检测代码托管平台：${error}';
  @override
  String get cannotFetchPrNoForge => '无法抓取 PR：未检测到此仓库的代码托管平台。';
  @override
  String overwriteRefConfirm({required Object ref}) => '用远程最新内容覆盖 ${ref}？';
  @override
  String get overwrite => '覆盖';
  @override
  String couldntFetchPr({required Object error}) => '无法抓取 PR：${error}';
  @override
  String get promoteDeskToPr => '将 Desk 提升为 PR';
  @override
  String get applyToMain => '应用到 main';
  @override
  String updateDeskFrom({required Object source, required Object target}) =>
      '从 ${source} 更新 ${target}';
  @override
  String bringChangesFromHere({required Object source}) =>
      '把 ${source} 的改动带到这里';
  @override
  String get editLocalPr => '编辑本地 PR';
  @override
  String get discardLocalPr => '丢弃本地 PR';
  @override
  String get closeDesk => '关闭 Desk';
  @override
  String couldntPromote({required Object error}) => '无法提升：${error}';
  @override
  String get commitOrShelveBeforeApplying => '应用前请先提交或搁置 Desk 的改动。';
  @override
  String get couldNotResolveMainWorktree => '无法解析主工作树路径。';
  @override
  String couldntPromoteDesk({required Object error}) => '无法提升 Desk：${error}';
  @override
  String get couldntDetermineBaseBranch => '无法确定此 Desk 的基础分支。';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'PR 的基础分支与头分支相同（${branch}）— 无内容可应用。';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '已将 ${branch} 应用到 ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
    n,
    other: '已将 ${target} 更新到 ${source}（${n} 个提交）。',
  );
  @override
  String get fastForwardFailedFallback => '快进无法干净落地 — 改为显示补丁预览。';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
    n,
    other: '${target} 领先 ${source} ${n} 个提交。',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} 已与 ${source} 保持一致。';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      '${target} 中有未提交的改动 — 改为以补丁预览。';
  @override
  String updateDeskFromLower({
    required Object source,
    required Object target,
  }) => '从 ${source} 更新 ${target}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      '${source} 没有可带来的更新。';
  @override
  String get updatePrepFailed => '更新准备失败';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => '把 ${source} 的改动带入 ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      '没有可从 ${source} 带入 ${target} 的可打补丁改动。';
  @override
  String get patchPrepFailed => '补丁准备失败';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}：${error}';
  @override
  String get titleHint => '标题';
  @override
  String get bodyHint => '正文';
  @override
  String get bodyOptionalHint => '正文（可选）';
  @override
  String get draftLower => '草稿';
  @override
  String get cancelLower => '取消';
  @override
  String get saveLower => '保存';
  @override
  String couldntSave({required Object error}) => '无法保存：${error}';
  @override
  String get stashedNoOtherDesk => '改动已储藏 — 没有其他 Desk 可应用。用 git stash pop 恢复。';
  @override
  String get suggestedSource => '建议来源';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} 个已修改';
  @override
  String tooltipAheadCount({required Object n}) => '领先 ${n}';
  @override
  String tooltipBehindCount({required Object n}) => '落后 ${n}';
  @override
  String get focusedEdits => '聚焦的改动';
  @override
  String get editsSpreadAcrossSubsystems => '改动散布于多个子系统';
  @override
  String get editsTouchingManySubsystems => '改动触及许多子系统';
  @override
  String get focusedBranch => '聚焦的分支';
  @override
  String get branchSpansMultipleSubsystems => '分支横跨多个子系统';
  @override
  String get structurallyDivergentFromMainline => '在结构上偏离主线';
  @override
  String get localPr => '本地 PR';
  @override
  String lastTouched({required Object time}) => '上次改动 ${time}';
  @override
  String driftGroupCount({required Object dir, required Object n}) =>
      '${dir} 中 ${n} 个';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => '未提交的改动';
  @override
  String get closeDeskQuestion => '关闭 Desk？';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个未提交的文件。',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '领先 main ${n} 个提交。',
      );
  @override
  String get willRemoveWorktreeDirectory => '这将移除工作树目录。';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件已更改',
      );
  @override
  String get shelveHere => '搁置到这里';
  @override
  String get discardAndClose => '丢弃并关闭';
  @override
  String get noRepository => '无仓库';
  @override
  String get issuePromotedToRemote => '议题已提升到远程。';
  @override
  String get pushedToRemote => '已推送到远程。';
  @override
  String get pulledFromRemote => '已从远程拉取。';
  @override
  String get remoteIssueNotFound => '未找到远程议题';
  @override
  String importedIssueLocally({required Object id}) => '已在本地导入 #${id}。';
  @override
  String get issueAbandoned => '议题已弃置。';
  @override
  String get abandonIssue => '弃置议题';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      '永久移除本地议题 #${id}？这会删除其引用且无法撤销。';
  @override
  String get abandon => '弃置';
  @override
  String publishedBranch({required Object branch}) => '已发布 ${branch}。';
  @override
  String get publishingEllipsis => '正在发布…';
  @override
  String get publish => '发布';
  @override
  String get noRemoteConfigured => '此仓库未配置远程。';
  @override
  String get jumpToDesk => '跳到 Desk';
  @override
  String get arrowOpen => '→ 打开';
  @override
  String get openOnANewDesk => '在新 Desk 打开';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'new-branch-name';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ 新 Desk';
  @override
  String get fromHeadEllipsis => '从 HEAD…';
  @override
  String get viewAllBranches => '查看所有分支';
  @override
  String get issuesLower => '议题';
  @override
  String get newIssueLower => '新建议题';
  @override
  String get noneLinked => '无关联';
  @override
  String get noOpenIssues => '无开放议题';
  @override
  String get createAndPushLower => '创建 + 推送';
  @override
  String get createLower => '创建';
  @override
  String get remoteLower => '远程';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => '提升到远程';
  @override
  String get pushToRemote => '推送到远程';
  @override
  String get pullFromRemote => '从远程拉取';
  @override
  String get importLabel => '导入';
  @override
  String get failedToCreateRepository => '创建仓库失败。';
  @override
  String get openRepositoryLower => '打开仓库';
  @override
  String get newRepositoryLower => '新建仓库';
  @override
  String get back => '返回';
  @override
  String get openRepositoryDialogTitle => '打开仓库';
  @override
  String get createRepositoryDialogTitle => '创建仓库';
  @override
  String get cloneTargetDialogTitle => '克隆目标';
  @override
  String get cloneToDialogTitle => '克隆到';
  @override
  String get exportToDialogTitle => '导出到';
  @override
  String get createFromTemplateInDialogTitle => '从模板创建于';
  @override
  String get notAGitRepoInitConfirm => '这不是 git 仓库。要在此初始化一个吗？';
  @override
  String get repositoryUrlRequired => '需要仓库 URL。';
  @override
  String get failedToCloneRepository => '克隆仓库失败。';
  @override
  String cloningEllipsis({required Object name}) => '正在克隆 ${name}…';
  @override
  String get cloneCancelled => '克隆已取消。';
  @override
  String get noProjectsYet => '还没有项目';
  @override
  String get dissolveGroup => '解散分组';
  @override
  String get projectsHeader => '项目';
  @override
  String get cloneLabel => '克隆';
  @override
  String get createLabel => '创建';
  @override
  String get openLabel => '打开';
  @override
  String get repositoryUrlPlaceholder => '仓库 URL';
  @override
  String get projectNameOrFullPathPlaceholder => '项目名或完整路径';
  @override
  String get pathToProjectPlaceholder => '/path/to/project';
  @override
  String get cloneToFolderPathPlaceholder => '克隆到文件夹路径';
  @override
  String get switchToCreateRepo => '切换到创建仓库';
  @override
  String get explorer => '资源管理器';
  @override
  String get terminal => '终端';
  @override
  String get cloneUrl => '克隆 URL';
  @override
  String get copyPath => '复制路径';
  @override
  String get export => '导出';
  @override
  String get readme => 'README';
  @override
  String get duplicate => '复制副本';
  @override
  String get template => '模板';
  @override
  String get forgetThisProject => '忘记此项目';
  @override
  String get aiKindCommitMessage => '提交信息';
  @override
  String get aiKindReview => '审查';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => '演示';
  @override
  String get aiKindDebug => '调试';
  @override
  String aiStatusRunning({required Object kind}) => '${kind}运行中';
  @override
  String aiStatusFailedUnread({required Object kind}) => '${kind}失败（未读）';
  @override
  String aiStatusReadyUnread({required Object kind}) => '${kind}就绪（未读）';
  @override
  String get filesLower => '文件';
  @override
  String get commitsLower => '提交';
  @override
  String get undoLabel => '撤销';
  @override
  String get goLabel => '执行';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ 折叠';
  @override
  String moreLinesGlyph({required Object n}) => '▼ 还有 ${n} 行';
}

// Path: backend
class _Translations$backend$zh_Hans extends Translations$backend$en {
  _Translations$backend$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$zh_Hans ops =
      _Translations$backend$ops$zh_Hans._(_root);
  @override
  late final _Translations$backend$mergeOutcome$zh_Hans mergeOutcome =
      _Translations$backend$mergeOutcome$zh_Hans._(_root);
}

// Path: branches
class _Translations$branches$zh_Hans extends Translations$branches$en {
  _Translations$branches$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => '正在运行 AI 审查…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => '发现';
  @override
  String get observations => '观察';
  @override
  String get renameEllipsis => '重命名…';
  @override
  String get publish => '发布';
  @override
  String publishFailed({required Object error}) => '发布失败：${error}';
  @override
  String couldntOpenDesk({required Object error}) => '无法打开 Desk：${error}';
  @override
  String syncFailed({required Object error}) => '同步失败：${error}';
  @override
  String get renameBranchTitle => '重命名分支';
  @override
  String get newNameHint => '新名称';
  @override
  String get rename => '重命名';
  @override
  String invalidBranchName({required Object name}) => '“${name}”不是有效的分支名。';
  @override
  String renameFailed({required Object error}) => '重命名失败：${error}';
  @override
  String deletingBranch({required Object name}) => '正在删除 ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '“${name}”已在 Desk“${desk}”中打开。';
  @override
  String get openDesk => '打开 Desk';
  @override
  String openInDeskShort({required Object desk}) => '在 Desk“${desk}”中打开';
  @override
  String get couldNotPinBranch => '无法固定分支顶端；已跳过删除';
  @override
  String get couldNotPinTag => '无法固定标签；已跳过删除';
  @override
  String deletingTag({required Object name}) => '正在删除标签 ${name}';
  @override
  String get applyToActiveChanges => '应用到活动更改…';
  @override
  String get couldNotLoadPrDiff => '无法加载 PR 差异。';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}：${title}';
  @override
  String mergeIntoDesk({required Object branch}) => '合并到 ${branch}…';
  @override
  String get checkoutThisPr => '检出此 PR';
  @override
  String get mergeIntoNewDesk => '合并到新 Desk…';
  @override
  String get pushToForge => '推送到托管平台';
  @override
  String get linkToIssue => '关联到议题…';
  @override
  String get gitPatch => '↓ git 补丁';
  @override
  String get copyBranchName => '复制分支名';
  @override
  String copiedRef({required Object ref}) => '已复制“${ref}”';
  @override
  String get reviewPr => '审查 PR';
  @override
  String get openInBrowser => '在浏览器中打开';
  @override
  String get markAsRead => '标记为已读';
  @override
  String get markAsUnread => '标记为未读';
  @override
  String get replaceLocalCommitsTitle => '替换本地提交？';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} 有一些本地提交不在远程 PR 头上。更新它会用远程最新内容替换它们。';
  @override
  String get update => '更新';
  @override
  String couldntFetchPr({required Object error}) => '无法抓取 PR：${error}';
  @override
  String couldntOpenAsDesk({required Object error}) => '无法作为 Desk 打开：${error}';
  @override
  String couldntOpenInBrowser({required Object error}) => '无法在浏览器中打开：${error}';
  @override
  String get noIssuesYetLocal => '还没有议题。在上游开一个，或在议题视图里用“+ 新建本地议题”。';
  @override
  String get remotePrsLinkLocalOnly => '远程 PR 只能关联到本地议题。用“+ 新建本地议题”创建一个。';
  @override
  String linkPrToIssues({required Object number}) => '将 PR #${number} 关联到议题';
  @override
  String get noPrsYetLocal => '还没有 PR。在上游开一个，或将 Desk 提升为 PR。';
  @override
  String get remoteIssuesLinkLocalOnly => '远程议题只能关联到本地 PR。请先将 Desk 提升为 PR。';
  @override
  String linkIssueToPrs({required Object number}) => '将议题 #${number} 关联到 PR';
  @override
  String couldntToggleLink({required Object error}) => '无法切换关联：${error}';
  @override
  String get openPatchDialogTitle => '打开补丁（.patch / .diff）';
  @override
  String get clipboardNoText => '剪贴板没有文本。';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) => '打开补丁失败：${error}';
  @override
  String get patchEmptyOrUnparseable => '补丁为空或无法解析。';
  @override
  String get prPushedToForge => 'PR 已推送到托管平台。';
  @override
  String overwriteRefConfirm({required Object ref}) => '用远程最新内容覆盖 ${ref}？';
  @override
  String get overwrite => '覆盖';
  @override
  String get loadingBranchesTitle => '正在加载分支';
  @override
  String get loadingBranchesMessage => '正在读取本地分支和标签。';
  @override
  String get branchesUnavailableTitle => '分支不可用';
  @override
  String get filterPullRequestsHint => '筛选拉取请求…';
  @override
  String get filterIssuesHint => '筛选议题…';
  @override
  String get branchNameHint => '分支名';
  @override
  String get tagsNewestFirst => '标签，最新在前';
  @override
  String get tagsOldestFirst => '标签，最旧在前';
  @override
  String get flipSortDirection => '翻转排序方向';
  @override
  String get readingPullRequests => '正在读取拉取请求…';
  @override
  String get noOpenPullRequests => '无开放的拉取请求';
  @override
  String get noPullRequestsHint => '从分支开一个，或提升一个 Desk。';
  @override
  String get noPrsMatchFilters => '没有 PR 匹配这些筛选';
  @override
  String get toggleFiltersRowAbove => '在上方一行关闭筛选。';
  @override
  String get issuesNewestFirst => '议题，最新在前';
  @override
  String get issuesOldestFirst => '议题，最旧在前';
  @override
  String get issuesHeading => '议题';
  @override
  String get readingIssuesLower => '正在读取议题…';
  @override
  String get noOpenIssues => '无开放议题';
  @override
  String get noIssuesHint => '+ 新建以跟踪工作和缺陷。';
  @override
  String get nothingMatches => '无匹配项';
  @override
  String get toggleFiltersAbove => '在上方关闭筛选。';
  @override
  String get bucketFresh => '新鲜';
  @override
  String get bucketThisWeek => '本周';
  @override
  String get bucketStalled => '停滞';
  @override
  String get bucketOlder => '更早';
  @override
  String get couldNotResolveMainWorktree => '无法解析主工作树路径。';
  @override
  String couldntSubmitReview({required Object error}) => '无法提交审查：${error}';
  @override
  String get reviewAiNotAvailable => '审查 AI 尚不可用。';
  @override
  String get noReviewModelConfigured => '未配置审查模型。';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({required num n, required Object branch}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${branch} 有 ${n} 个未提交的改动 — 请先提交或储藏。',
      );
  @override
  String get targetDeskNoBranch => '目标 Desk 没有分支。';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      '将 PR #${number} 合并到 ${branch}';
  @override
  String get conflictCheckUnavailableVersion => '冲突检查不可用 — 需要 git 2.38+';
  @override
  String get conflictCheckUnavailable => '冲突检查不可用';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '将冲突 · ${n} 个文件',
      );
  @override
  String plusMore({required Object n}) => '+${n} 更多';
  @override
  String get rebase => '变基';
  @override
  String get squash => '压缩';
  @override
  String get mergeCommit => '合并提交';
  @override
  String noDeskForBranch({required Object branch}) =>
      '未找到分支 ${branch} 对应的 Desk';
  @override
  String get mergeAnyway => '仍然合并';
  @override
  String get readingIssues => '正在读取议题…';
  @override
  String get openUpstreamOrLocal => '在上游开一个，或打开一个本地的。';
  @override
  String get noIssuesMatchFilters => '没有议题匹配这些筛选';
  @override
  String couldntCreateIssue({required Object error}) => '无法创建议题：${error}';
  @override
  String get promoteToRemote => '提升到远程';
  @override
  String get pushToRemote => '推送到远程';
  @override
  String get pullFromRemote => '从远程拉取';
  @override
  String get import => '导入';
  @override
  String get linkToPr => '关联到 PR…';
  @override
  String get abandon => '弃置';
  @override
  String get issuePromotedToRemote => '议题已提升到远程。';
  @override
  String get issuePushedToRemote => '已推送到远程。';
  @override
  String get issuePulledFromRemote => '已从远程拉取。';
  @override
  String issueImportedLocally({required Object number}) => '已在本地导入 #${number}。';
  @override
  String get abandonIssueTitle => '弃置议题';
  @override
  String abandonIssueMessage({required Object id}) =>
      '永久移除本地议题 #${id}？这会删除其引用且无法撤销。';
  @override
  String couldntAbandon({required Object error}) => '无法弃置：${error}';
  @override
  String couldntPostComment({required Object error}) => '无法发表评论：${error}';
  @override
  String couldntCloseIssue({required Object error}) => '无法关闭议题：${error}';
  @override
  String couldntAddLabel({required Object error}) => '无法添加标签：${error}';
  @override
  String get lensBranches => '分支';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ 补丁';
  @override
  String get syncRibbon => '⇅ 同步';
  @override
  String get kbHeading => '键盘';
  @override
  String get kbNavigateRows => '在行间导航';
  @override
  String get kbExpandCollapse => '展开 / 折叠聚焦行';
  @override
  String get kbCheckoutPr => '在本地检出聚焦的 PR';
  @override
  String get kbApproveReview => '批准 · 审查';
  @override
  String get kbRequestChanges => '请求修改';
  @override
  String get kbFocusSearch => '聚焦搜索';
  @override
  String get kbSwitchLens => '切换视图（分支 · PR）';
  @override
  String get kbToggleOverlay => '切换此覆盖层';
  @override
  String get kbPressToDismiss => '按任意处关闭';
  @override
  String get overrideScarTooltip => '在检查失败或无批准审查的情况下合并 — 请先在压力下调查';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件与你未提交的工作重叠',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '#${pr}  （${n} 个文件）',
      );
  @override
  String get prStateDraft => '草稿';
  @override
  String get localBadge => '本地';
  @override
  String get myReviewPending => '你的审查待定';
  @override
  String get myReviewApproved => '你 ✓';
  @override
  String get myReviewChangesRequested => '你 ✗ 请求了修改';
  @override
  String get myReviewCommented => '你已评论';
  @override
  String get myReviewDefault => '你';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} 条评论 · 显示作者的最后一条';
  @override
  String get tailLastComment => '最后评论';
  @override
  String tailLastReviewState({required Object state}) => '最后审查 · ${state}';
  @override
  String get tailLastReview => '最后审查';
  @override
  String tailLastCheckState({required Object state}) => '最后检查 · ${state}';
  @override
  String get tailLastCommit => '最后提交';
  @override
  String get tailLastActivity => '最近活动';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '关闭 ${n} 个议题 — 点击跳转',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '由 ${n} 个 PR 处理 — 点击跳转',
      );
  @override
  String get checksLabel => '检查';
  @override
  String get reviewersLabel => '审查者';
  @override
  String get conflictsLabel => '冲突';
  @override
  String exportFailed({required Object error}) => '导出失败：${error}';
  @override
  String get readingFiles => '正在读取文件…';
  @override
  String get noDetailAvailable => '无可用详情';
  @override
  String get noFilesReported => '未报告文件';
  @override
  String get readingGitHistory => '正在读取 git 历史…';
  @override
  String get knowsThisCode => '熟悉这段代码';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '过去一年在这些文件上有 ${n} 个提交',
      );
  @override
  String get willFight => '会冲突';
  @override
  String orbitalPartnerCos({required Object cos}) => '轨道伙伴 — cos ${cos}';
  @override
  String get orbitLabel => '轨道';
  @override
  String get touchesYourLocalWork => '触及你的本地工作';
  @override
  String get mergingWillConflict => '合并很可能与你未提交的改动冲突';
  @override
  String get closesHeading => '关闭';
  @override
  String get filesHeading => '文件';
  @override
  String get orientAligned => '对齐';
  @override
  String get orientAdjacent => '相邻';
  @override
  String get orientOrthogonal => '正交';
  @override
  String shapeField({required Object v}) => '场 ${v}';
  @override
  String shapeSource({required Object v}) => '源 ${v}';
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
  String shapeStress({required Object v}) => '应力 ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => '共振 ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      '通常与此 PR 中的文件一同改动\n（${path}）';
  @override
  String get prStateDraftLower => '草稿';
  @override
  String get keystoneTooltip => '关键石 — 仓库级桥接文件';
  @override
  String get reviewNoteHint => '留一条备注（可选）…';
  @override
  String get reviewComment => '评论';
  @override
  String get reviewRequestChanges => '请求修改';
  @override
  String get reviewApprove => '✓ 批准';
  @override
  String get actionPatchDown => '↓ 补丁';
  @override
  String get actionPrReview => '✦ pr 审查';
  @override
  String get actionOpenAsDesk => '⊞ 作为 Desk 打开';
  @override
  String get actionCheckout => '[c] 检出';
  @override
  String get actionMerge => '[m] 合并 ▾';
  @override
  String get mergeMenuMergeCommit => '合并提交';
  @override
  String get mergeMenuSquash => '压缩并合并';
  @override
  String get mergeMenuRebase => '变基并合并';
  @override
  String get deleteBranchAfter => '之后删除分支';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => '指派给：${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} 次对话 · ${time}';
  @override
  String get readingThread => '正在读取话题…';
  @override
  String get addressedByHeading => '由此处理';
  @override
  String get descriptionHeading => '描述';
  @override
  String get threadHeading => '话题';
  @override
  String get replyHint => '回复…';
  @override
  String get assignMe => '指派给我';
  @override
  String get closeLower => '关闭';
  @override
  String get postReply => '↩ 发布';
  @override
  String get remoteProviderUnavailable => '远程提供方不可用';
  @override
  String get noRecognisedRemoteHost => '未识别此仓库的远程主机。';
  @override
  String get corpseGone => '已消失';
  @override
  String get corpseAbsorbed => '已吸收';
  @override
  String get corpseSquashed => '已压缩';
  @override
  String absorbedDeliveredIn({required Object hash}) => '已在 ${hash} 中交付';
  @override
  String get absorbedNoChanges => '合并不带来任何改动';
  @override
  String get corpseTagUpstreamGone => '上游已消失';
  @override
  String corpseTagAbsorbed({required Object receipt}) => '已吸收，${receipt}';
  @override
  String get corpseTagSquashed => '已压缩并合并';
  @override
  String semanticsCurrentBranch({required Object name}) => '${name}，当前分支';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}，跟踪 ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}，${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) => '${label}，工作树已打开';
  @override
  String semanticsIdle({required Object name, required Object phrase}) =>
      '${name}，${phrase}';
  @override
  String semanticsCorpse({
    required Object name,
    required Object tag,
    required Object phrase,
  }) => '${name}，${tag}，${phrase}';
  @override
  String get crossLinkDesk => 'Desk';
  @override
  String get crossLinkPr => 'PR';
  @override
  String get crossLinkPrDraft => 'PR · 草稿';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个议题',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ 跟踪：${upstream}';
  @override
  String get checkoutButton => '检出';
  @override
  String get createBranch => '创建分支';
  @override
  String get newBranchName => '新分支名';
  @override
  String newBranchNameError({required Object error}) => '新分支名 — ${error}';
  @override
  String get forceDelete => '强制？';
  @override
  String get annotated => '带注释';
  @override
  String get applyCheckFailed => 'apply --check 失败';
  @override
  String get openPatchFrom => '打开补丁来源';
  @override
  String get patchFromFile => '从文件…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => '从剪贴板';
  @override
  String get patchFromClipboardHint => '粘贴文本';
  @override
  String get patchPreviewHeading => '补丁预览';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => '已暂存。';
  @override
  String get appliedDone => '已应用。';
  @override
  String get opening => '正在打开…';
  @override
  String get mergeEditor => '⇋ 合并编辑器';
  @override
  String get staging => '正在暂存…';
  @override
  String get applying => '正在应用…';
  @override
  String get stage => '暂存';
  @override
  String get apply => '应用';
  @override
  String get refineHint => '细化…（例如“也去掉 logger 的改动”）';
  @override
  String get reverseArmedTooltip => '已就绪 — 下次应用将还原补丁（-R）';
  @override
  String get reverseDisarmedTooltip => '就绪反向（-R）— 撤销而非应用';
  @override
  String get reverseArmedLabel => '⟲ 反向 ✓';
  @override
  String get reverseLabel => '⟲ 反向';
  @override
  String get untouchedHeading => '⚠ 未触及';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件中的 ${count} 个不在补丁中',
      );
  @override
  String get staysConflicted => '这些文件将保持冲突 — 应用不会暂存它们';
  @override
  String get orWith => '或使用';
  @override
  String get noAiModelConfigured => '未配置 AI 模型';
  @override
  String applyWithPatchFrom({required Object label}) => '用来自 ${label} 的补丁应用';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => '用来自 ${label} 的补丁应用  ·  ${model}';
  @override
  String get patching => '正在打补丁…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  用来自 ${label} 的补丁应用';
  @override
  String get orWithAnotherModel => '或用其他模型';
  @override
  String get applyCheckPassed => 'git apply --check 通过 — 补丁将干净应用';
  @override
  String get gitApplyCheckFailed => 'git apply --check 失败';
  @override
  String get appliesClean => '可干净应用';
  @override
  String get willNotApply => '无法应用';
  @override
  String get newLocalIssue => '新建本地议题';
  @override
  String get filterHint => '筛选…';
  @override
  String get nothingToLink => '暂无可关联项。';
  @override
  String get nothingMatchesDot => '无匹配项。';
  @override
  String get relevantHeading => '相关';
  @override
  String get allHeading => '全部';
  @override
  String get doneLower => '完成';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => '新建本地议题';
  @override
  String get titleHint => '标题';
  @override
  String get bodyHint => '正文（markdown）';
  @override
  String get cancelLower => '取消';
  @override
  String get createLower => '创建';
  @override
  String get deleteFailed => '删除失败';
  @override
  String reviewFailed({required Object error}) => '审查失败：${error}';
  @override
  String get resolutionFailed => '解决失败';
  @override
  String get patchBlocksNoCover => '模型返回的补丁块未覆盖失败的文件';
  @override
  String get applyFailed => '应用失败';
  @override
  String get emptyOrUnparseablePatch => '模型返回了空或无法解析的补丁';
  @override
  String noModelConfiguredFor({required Object label}) => '未为“${label}”配置模型';
  @override
  String get checksHeading => '检查';
  @override
  String get peopleHeading => '成员';
  @override
  String get conversationHeading => '对话';
}

// Path: changes
class _Translations$changes$zh_Hans extends Translations$changes$en {
  _Translations$changes$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$zh_Hans usage =
      _Translations$changes$usage$zh_Hans._(_root);
  @override
  late final _Translations$changes$tabs$zh_Hans tabs =
      _Translations$changes$tabs$zh_Hans._(_root);
  @override
  late final _Translations$changes$tabStrip$zh_Hans tabStrip =
      _Translations$changes$tabStrip$zh_Hans._(_root);
  @override
  late final _Translations$changes$select$zh_Hans select =
      _Translations$changes$select$zh_Hans._(_root);
  @override
  late final _Translations$changes$constellationToggle$zh_Hans
  constellationToggle = _Translations$changes$constellationToggle$zh_Hans._(
    _root,
  );
  @override
  late final _Translations$changes$nudgeChip$zh_Hans nudgeChip =
      _Translations$changes$nudgeChip$zh_Hans._(_root);
  @override
  late final _Translations$changes$minimap$zh_Hans minimap =
      _Translations$changes$minimap$zh_Hans._(_root);
  @override
  late final _Translations$changes$tagInput$zh_Hans tagInput =
      _Translations$changes$tagInput$zh_Hans._(_root);
  @override
  late final _Translations$changes$composer$zh_Hans composer =
      _Translations$changes$composer$zh_Hans._(_root);
  @override
  late final _Translations$changes$commit$zh_Hans commit =
      _Translations$changes$commit$zh_Hans._(_root);
  @override
  late final _Translations$changes$rebase$zh_Hans rebase =
      _Translations$changes$rebase$zh_Hans._(_root);
  @override
  late final _Translations$changes$editor$zh_Hans editor =
      _Translations$changes$editor$zh_Hans._(_root);
  @override
  late final _Translations$changes$editorTitles$zh_Hans editorTitles =
      _Translations$changes$editorTitles$zh_Hans._(_root);
  @override
  late final _Translations$changes$askHint$zh_Hans askHint =
      _Translations$changes$askHint$zh_Hans._(_root);
  @override
  late final _Translations$changes$fileMenu$zh_Hans fileMenu =
      _Translations$changes$fileMenu$zh_Hans._(_root);
  @override
  late final _Translations$changes$multiFileMenu$zh_Hans multiFileMenu =
      _Translations$changes$multiFileMenu$zh_Hans._(_root);
  @override
  late final _Translations$changes$ignoreMenu$zh_Hans ignoreMenu =
      _Translations$changes$ignoreMenu$zh_Hans._(_root);
  @override
  late final _Translations$changes$discard$zh_Hans discard =
      _Translations$changes$discard$zh_Hans._(_root);
  @override
  late final _Translations$changes$snack$zh_Hans snack =
      _Translations$changes$snack$zh_Hans._(_root);
  @override
  late final _Translations$changes$trace$zh_Hans trace =
      _Translations$changes$trace$zh_Hans._(_root);
  @override
  late final _Translations$changes$cleanTree$zh_Hans cleanTree =
      _Translations$changes$cleanTree$zh_Hans._(_root);
  @override
  late final _Translations$changes$guardrail$zh_Hans guardrail =
      _Translations$changes$guardrail$zh_Hans._(_root);
  @override
  late final _Translations$changes$dropHint$zh_Hans dropHint =
      _Translations$changes$dropHint$zh_Hans._(_root);
  @override
  late final _Translations$changes$diffEmpty$zh_Hans diffEmpty =
      _Translations$changes$diffEmpty$zh_Hans._(_root);
  @override
  late final _Translations$changes$shelvePill$zh_Hans shelvePill =
      _Translations$changes$shelvePill$zh_Hans._(_root);
  @override
  late final _Translations$changes$stashAction$zh_Hans stashAction =
      _Translations$changes$stashAction$zh_Hans._(_root);
  @override
  late final _Translations$changes$stashContents$zh_Hans stashContents =
      _Translations$changes$stashContents$zh_Hans._(_root);
  @override
  late final _Translations$changes$stashFile$zh_Hans stashFile =
      _Translations$changes$stashFile$zh_Hans._(_root);
  @override
  late final _Translations$changes$fileRow$zh_Hans fileRow =
      _Translations$changes$fileRow$zh_Hans._(_root);
  @override
  late final _Translations$changes$resolveStrip$zh_Hans resolveStrip =
      _Translations$changes$resolveStrip$zh_Hans._(_root);
  @override
  late final _Translations$changes$badge$zh_Hans badge =
      _Translations$changes$badge$zh_Hans._(_root);
  @override
  late final _Translations$changes$review$zh_Hans review =
      _Translations$changes$review$zh_Hans._(_root);
  @override
  late final _Translations$changes$commitBtn$zh_Hans commitBtn =
      _Translations$changes$commitBtn$zh_Hans._(_root);
  @override
  late final _Translations$changes$shapeBtn$zh_Hans shapeBtn =
      _Translations$changes$shapeBtn$zh_Hans._(_root);
  @override
  late final _Translations$changes$dejaVu$zh_Hans dejaVu =
      _Translations$changes$dejaVu$zh_Hans._(_root);
  @override
  late final _Translations$changes$identity$zh_Hans identity =
      _Translations$changes$identity$zh_Hans._(_root);
  @override
  late final _Translations$changes$staleScope$zh_Hans staleScope =
      _Translations$changes$staleScope$zh_Hans._(_root);
  @override
  late final _Translations$changes$finding$zh_Hans finding =
      _Translations$changes$finding$zh_Hans._(_root);
  @override
  late final _Translations$changes$muse$zh_Hans muse =
      _Translations$changes$muse$zh_Hans._(_root);
  @override
  late final _Translations$changes$debug$zh_Hans debug =
      _Translations$changes$debug$zh_Hans._(_root);
  @override
  late final _Translations$changes$includeSummary$zh_Hans includeSummary =
      _Translations$changes$includeSummary$zh_Hans._(_root);
  @override
  late final _Translations$changes$status$zh_Hans status =
      _Translations$changes$status$zh_Hans._(_root);
  @override
  late final _Translations$changes$stash$zh_Hans stash =
      _Translations$changes$stash$zh_Hans._(_root);
  @override
  late final _Translations$changes$tooltips$zh_Hans tooltips =
      _Translations$changes$tooltips$zh_Hans._(_root);
  @override
  late final _Translations$changes$mergeEditor$zh_Hans mergeEditor =
      _Translations$changes$mergeEditor$zh_Hans._(_root);
  @override
  late final _Translations$changes$conflictResolution$zh_Hans
  conflictResolution = _Translations$changes$conflictResolution$zh_Hans._(
    _root,
  );
  @override
  late final _Translations$changes$mergeFlow$zh_Hans mergeFlow =
      _Translations$changes$mergeFlow$zh_Hans._(_root);
  @override
  late final _Translations$changes$constellation$zh_Hans constellation =
      _Translations$changes$constellation$zh_Hans._(_root);
}

// Path: common
class _Translations$common$zh_Hans extends Translations$common$en {
  _Translations$common$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => '、';
  @override
  String get cancel => '取消';
  @override
  String get close => '关闭';
  @override
  String get save => '保存';
  @override
  String get delete => '删除';
  @override
  String get retry => '重试';
  @override
  String get copy => '复制';
  @override
  String get copied => '已复制';
  @override
  String get done => '完成';
  @override
  String get loading => '加载中…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个提交',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个分支',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个本地提交',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个远程提交',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个冲突文件',
      );
  @override
  late final _Translations$common$time$zh_Hans time =
      _Translations$common$time$zh_Hans._(_root);
  @override
  late final _Translations$common$size$zh_Hans size =
      _Translations$common$size$zh_Hans._(_root);
}

// Path: diff
class _Translations$diff$zh_Hans extends Translations$diff$en {
  _Translations$diff$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$zh_Hans status =
      _Translations$diff$status$zh_Hans._(_root);
  @override
  late final _Translations$diff$toolbar$zh_Hans toolbar =
      _Translations$diff$toolbar$zh_Hans._(_root);
  @override
  late final _Translations$diff$hunkDropdown$zh_Hans hunkDropdown =
      _Translations$diff$hunkDropdown$zh_Hans._(_root);
  @override
  String stagingFailed({required Object error}) => '部分暂存失败：${error}';
  @override
  late final _Translations$diff$trail$zh_Hans trail =
      _Translations$diff$trail$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$zh_Hans pinned =
      _Translations$diff$pinned$zh_Hans._(_root);
  @override
  late final _Translations$diff$hunkHint$zh_Hans hunkHint =
      _Translations$diff$hunkHint$zh_Hans._(_root);
  @override
  late final _Translations$diff$binary$zh_Hans binary =
      _Translations$diff$binary$zh_Hans._(_root);
  @override
  late final _Translations$diff$media$zh_Hans media =
      _Translations$diff$media$zh_Hans._(_root);
}

// Path: filament
class _Translations$filament$zh_Hans extends Translations$filament$en {
  _Translations$filament$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => '未打开仓库。';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      '正在扫描 ${scanned} / ${total} 个文件…';
  @override
  String findingsAcrossFiles({required Object files, required Object count}) =>
      '${files} 个文件中共 ${count} 项发现';
  @override
  String copiedFindings({required Object count}) => '已复制 ${count} 项发现';
  @override
  String get copy => '复制';
  @override
  String get noFindings => '无执行流发现。';
  @override
  late final _Translations$filament$severity$zh_Hans severity =
      _Translations$filament$severity$zh_Hans._(_root);
  @override
  late final _Translations$filament$kind$zh_Hans kind =
      _Translations$filament$kind$zh_Hans._(_root);
  @override
  String lineLabel({required Object line}) => 'L${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$zh_Hans extends Translations$history$en {
  _Translations$history$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$zh_Hans commitLede =
      _Translations$history$commitLede$zh_Hans._(_root);
  @override
  late final _Translations$history$seismograph$zh_Hans seismograph =
      _Translations$history$seismograph$zh_Hans._(_root);
  @override
  late final _Translations$history$worldline$zh_Hans worldline =
      _Translations$history$worldline$zh_Hans._(_root);
  @override
  late final _Translations$history$contextMenu$zh_Hans contextMenu =
      _Translations$history$contextMenu$zh_Hans._(_root);
  @override
  late final _Translations$history$cherryPick$zh_Hans cherryPick =
      _Translations$history$cherryPick$zh_Hans._(_root);
  @override
  late final _Translations$history$revert$zh_Hans revert =
      _Translations$history$revert$zh_Hans._(_root);
  @override
  late final _Translations$history$reflog$zh_Hans reflog =
      _Translations$history$reflog$zh_Hans._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '该提交比已加载的 ${n} 个提交更深。',
      );
  @override
  String deleteTagFailed({required Object error}) => '删除标签失败：${error}';
  @override
  String get loadingTitle => '正在加载历史';
  @override
  String get loadingMessage => '正在读取近期提交。';
  @override
  String get unavailableTitle => '历史不可用';
  @override
  String get toggleWorldline => '切换世界线';
  @override
  String get pageTitle => '历史';
  @override
  String get viewingLast => '正在查看最近';
  @override
  String get commitsUnit => '个提交';
  @override
  String get noCommitSelectedTitle => '未选择提交';
  @override
  String get noCommitSelectedMessage => '选择一个提交以查看其改动。';
  @override
  String get loadingCommitTitle => '正在加载提交';
  @override
  String get loadingCommitMessage => '正在读取提交详情。';
  @override
  String get commitUnavailableTitle => '提交不可用';
  @override
  String get couldNotLoadCommit => '无法加载提交。';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => '加载 reflog';
  @override
  String get createTag => '创建标签';
  @override
  String get newTagName => '新标签名';
  @override
  String newTagNameError({required Object error}) => '新标签名 — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件 · 全部改动',
      );
  @override
  String get allChangesLabel => '全部改动';
  @override
  late final _Translations$history$rebase$zh_Hans rebase =
      _Translations$history$rebase$zh_Hans._(_root);
  @override
  late final _Translations$history$inFlight$zh_Hans inFlight =
      _Translations$history$inFlight$zh_Hans._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$zh_Hans
    extends Translations$historySurgery$en {
  _Translations$historySurgery$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$zh_Hans chrome =
      _Translations$historySurgery$chrome$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$select$zh_Hans select =
      _Translations$historySurgery$select$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$understand$zh_Hans understand =
      _Translations$historySurgery$understand$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$confirm$zh_Hans confirm =
      _Translations$historySurgery$confirm$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$execute$zh_Hans execute =
      _Translations$historySurgery$execute$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$verify$zh_Hans verify =
      _Translations$historySurgery$verify$zh_Hans._(_root);
  @override
  late final _Translations$historySurgery$forcePush$zh_Hans forcePush =
      _Translations$historySurgery$forcePush$zh_Hans._(_root);
}

// Path: onboarding
class _Translations$onboarding$zh_Hans extends Translations$onboarding$en {
  _Translations$onboarding$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$zh_Hans nav =
      _Translations$onboarding$nav$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$naming$zh_Hans naming =
      _Translations$onboarding$naming$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$theme$zh_Hans theme =
      _Translations$onboarding$theme$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$repo$zh_Hans repo =
      _Translations$onboarding$repo$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$preview$zh_Hans preview =
      _Translations$onboarding$preview$zh_Hans._(_root);
}

// Path: orrery
class _Translations$orrery$zh_Hans extends Translations$orrery$en {
  _Translations$orrery$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$zh_Hans header =
      _Translations$orrery$header$zh_Hans._(_root);
  @override
  late final _Translations$orrery$status$zh_Hans status =
      _Translations$orrery$status$zh_Hans._(_root);
  @override
  late final _Translations$orrery$legend$zh_Hans legend =
      _Translations$orrery$legend$zh_Hans._(_root);
  @override
  late final _Translations$orrery$node$zh_Hans node =
      _Translations$orrery$node$zh_Hans._(_root);
  @override
  late final _Translations$orrery$milestone$zh_Hans milestone =
      _Translations$orrery$milestone$zh_Hans._(_root);
  @override
  late final _Translations$orrery$structure$zh_Hans structure =
      _Translations$orrery$structure$zh_Hans._(_root);
  @override
  late final _Translations$orrery$rail$zh_Hans rail =
      _Translations$orrery$rail$zh_Hans._(_root);
  @override
  late final _Translations$orrery$selection$zh_Hans selection =
      _Translations$orrery$selection$zh_Hans._(_root);
  @override
  late final _Translations$orrery$findingKind$zh_Hans findingKind =
      _Translations$orrery$findingKind$zh_Hans._(_root);
  @override
  late final _Translations$orrery$findings$zh_Hans findings =
      _Translations$orrery$findings$zh_Hans._(_root);
  @override
  late final _Translations$orrery$anchor$zh_Hans anchor =
      _Translations$orrery$anchor$zh_Hans._(_root);
  @override
  late final _Translations$orrery$compare$zh_Hans compare =
      _Translations$orrery$compare$zh_Hans._(_root);
}

// Path: palette
class _Translations$palette$zh_Hans extends Translations$palette$en {
  _Translations$palette$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get active => '活跃';
  @override
  late final _Translations$palette$prefixes$zh_Hans prefixes =
      _Translations$palette$prefixes$zh_Hans._(_root);
  @override
  late final _Translations$palette$chips$zh_Hans chips =
      _Translations$palette$chips$zh_Hans._(_root);
  @override
  late final _Translations$palette$predictive$zh_Hans predictive =
      _Translations$palette$predictive$zh_Hans._(_root);
  @override
  late final _Translations$palette$topTouched$zh_Hans topTouched =
      _Translations$palette$topTouched$zh_Hans._(_root);
  @override
  late final _Translations$palette$coherence$zh_Hans coherence =
      _Translations$palette$coherence$zh_Hans._(_root);
  @override
  late final _Translations$palette$keystone$zh_Hans keystone =
      _Translations$palette$keystone$zh_Hans._(_root);
  @override
  late final _Translations$palette$repoSub$zh_Hans repoSub =
      _Translations$palette$repoSub$zh_Hans._(_root);
  @override
  late final _Translations$palette$desks$zh_Hans desks =
      _Translations$palette$desks$zh_Hans._(_root);
  @override
  late final _Translations$palette$actions$zh_Hans actions =
      _Translations$palette$actions$zh_Hans._(_root);
  @override
  late final _Translations$palette$tools$zh_Hans tools =
      _Translations$palette$tools$zh_Hans._(_root);
  @override
  late final _Translations$palette$gitCommands$zh_Hans gitCommands =
      _Translations$palette$gitCommands$zh_Hans._(_root);
  @override
  late final _Translations$palette$pr$zh_Hans pr =
      _Translations$palette$pr$zh_Hans._(_root);
  @override
  late final _Translations$palette$ai$zh_Hans ai =
      _Translations$palette$ai$zh_Hans._(_root);
  @override
  late final _Translations$palette$undo$zh_Hans undo =
      _Translations$palette$undo$zh_Hans._(_root);
  @override
  late final _Translations$palette$navigation$zh_Hans navigation =
      _Translations$palette$navigation$zh_Hans._(_root);
  @override
  late final _Translations$palette$settings$zh_Hans settings =
      _Translations$palette$settings$zh_Hans._(_root);
  @override
  late final _Translations$palette$info$zh_Hans info =
      _Translations$palette$info$zh_Hans._(_root);
  @override
  late final _Translations$palette$debug$zh_Hans debug =
      _Translations$palette$debug$zh_Hans._(_root);
  @override
  late final _Translations$palette$dev$zh_Hans dev =
      _Translations$palette$dev$zh_Hans._(_root);
  @override
  late final _Translations$palette$historySurgery$zh_Hans historySurgery =
      _Translations$palette$historySurgery$zh_Hans._(_root);
  @override
  late final _Translations$palette$orrery$zh_Hans orrery =
      _Translations$palette$orrery$zh_Hans._(_root);
  @override
  late final _Translations$palette$command$zh_Hans command =
      _Translations$palette$command$zh_Hans._(_root);
  @override
  late final _Translations$palette$search$zh_Hans search =
      _Translations$palette$search$zh_Hans._(_root);
  @override
  late final _Translations$palette$wick$zh_Hans wick =
      _Translations$palette$wick$zh_Hans._(_root);
  @override
  late final _Translations$palette$gitCache$zh_Hans gitCache =
      _Translations$palette$gitCache$zh_Hans._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$zh_Hans extends Translations$releaseNotes$en {
  _Translations$releaseNotes$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$zh_Hans about =
      _Translations$releaseNotes$about$zh_Hans._(_root);
  @override
  late final _Translations$releaseNotes$legal$zh_Hans legal =
      _Translations$releaseNotes$legal$zh_Hans._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$zh_Hans extends Translations$repoSummary$en {
  _Translations$repoSummary$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$zh_Hans backbone =
      _Translations$repoSummary$backbone$zh_Hans._(_root);
  @override
  late final _Translations$repoSummary$glance$zh_Hans glance =
      _Translations$repoSummary$glance$zh_Hans._(_root);
  @override
  late final _Translations$repoSummary$heading$zh_Hans heading =
      _Translations$repoSummary$heading$zh_Hans._(_root);
  @override
  String get historyStarvedCaveat =>
      '排序受限：耦合图没有边（全新克隆或提交太少）。文件顺序反映的是大小，而非结构中心性。';
  @override
  late final _Translations$repoSummary$pitch$zh_Hans pitch =
      _Translations$repoSummary$pitch$zh_Hans._(_root);
  @override
  late final _Translations$repoSummary$region$zh_Hans region =
      _Translations$repoSummary$region$zh_Hans._(_root);
  @override
  late final _Translations$repoSummary$shape$zh_Hans shape =
      _Translations$repoSummary$shape$zh_Hans._(_root);
}

// Path: review
class _Translations$review$zh_Hans extends Translations$review$en {
  _Translations$review$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => '未解决';
  @override
  String get done => '完成';
  @override
  String get ack => '确认';
  @override
  String get reply => '回复';
  @override
  String get pleaseFix => '请修复';
  @override
  String get draft => '草稿';
  @override
  String get engine => '引擎';
  @override
  String get moved => '已移动';
  @override
  String get yourTurn => '轮到你了';
  @override
  String get drafts => '草稿';
  @override
  String get publish => '发布';
  @override
  String get discard => '丢弃';
  @override
  String get saveDraft => '保存草稿';
  @override
  String get cancel => '取消';
  @override
  String get verdictApprove => '批准';
  @override
  String get verdictRequestChanges => '请求修改';
  @override
  String get verdictComment => '评论';
  @override
  String get caughtUp => '已看完';
  @override
  String get sinceLastLook => '自你上次查看以来';
  @override
  String get fullDiff => '完整差异';
  @override
  String get commentHint => '写评论';
  @override
  String outdatedLastSeen({required Object round}) => '已过时 · 最后查看 R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => '等待 ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        one: '自你上次查看以来 ${n} 个文件',
        other: '自你上次查看以来 ${n} 个文件',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} 个未解决';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        one: '${n} 个草稿',
        other: '${n} 个草稿',
      );
  @override
  String startReviewFailed({required Object error}) => '无法开始审查：${error}';
  @override
  String get anchorUnavailable => '该行无法锚定 — 文件过大或不可用。';
  @override
  String reviewActionFailed({required Object error}) => '审查操作失败：${error}';
  @override
  String get lensTooLarge => '该比较过大，无法在此显示 — 继续显示完整差异。';
  @override
  String get lensEmpty => '这两个快照之间没有任何改动。';
  @override
  String get reopen => '重新打开';
  @override
  String get notBlocking => '不用等我';
  @override
  String get markReviewed => '已查看';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        one: '${n} 条新评论',
        other: '${n} 条新评论',
      );
  @override
  String get handTo => '交给';
  @override
  String get heading => '评审';
  @override
  String get identityNeeded => '设置 git 身份后即可评审';
  @override
  String get fileUnreadable => '此文件无法在此读取：过大或在本轮中不存在。';
}

// Path: settings
class _Translations$settings$zh_Hans extends Translations$settings$en {
  _Translations$settings$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$zh_Hans language =
      _Translations$settings$language$zh_Hans._(_root);
  @override
  late final _Translations$settings$sectionLabels$zh_Hans sectionLabels =
      _Translations$settings$sectionLabels$zh_Hans._(_root);
  @override
  late final _Translations$settings$errors$zh_Hans errors =
      _Translations$settings$errors$zh_Hans._(_root);
  @override
  late final _Translations$settings$promptStatus$zh_Hans promptStatus =
      _Translations$settings$promptStatus$zh_Hans._(_root);
  @override
  late final _Translations$settings$clearData$zh_Hans clearData =
      _Translations$settings$clearData$zh_Hans._(_root);
  @override
  List<String> get guardrailStageLabels => ['宽松', '均衡', '严格', '偏执'];
  @override
  late final _Translations$settings$guardrailMacro$zh_Hans guardrailMacro =
      _Translations$settings$guardrailMacro$zh_Hans._(_root);
  @override
  late final _Translations$settings$guardrails$zh_Hans guardrails =
      _Translations$settings$guardrails$zh_Hans._(_root);
  @override
  late final _Translations$settings$appearance$zh_Hans appearance =
      _Translations$settings$appearance$zh_Hans._(_root);
  @override
  late final _Translations$settings$retention$zh_Hans retention =
      _Translations$settings$retention$zh_Hans._(_root);
  @override
  late final _Translations$settings$navigation$zh_Hans navigation =
      _Translations$settings$navigation$zh_Hans._(_root);
  @override
  late final _Translations$settings$behaviour$zh_Hans behaviour =
      _Translations$settings$behaviour$zh_Hans._(_root);
  @override
  late final _Translations$settings$retentionClear$zh_Hans retentionClear =
      _Translations$settings$retentionClear$zh_Hans._(_root);
  @override
  late final _Translations$settings$channels$zh_Hans channels =
      _Translations$settings$channels$zh_Hans._(_root);
  @override
  late final _Translations$settings$pollResult$zh_Hans pollResult =
      _Translations$settings$pollResult$zh_Hans._(_root);
  @override
  late final _Translations$settings$keybindingProfile$zh_Hans
  keybindingProfile = _Translations$settings$keybindingProfile$zh_Hans._(_root);
  @override
  late final _Translations$settings$apiKeys$zh_Hans apiKeys =
      _Translations$settings$apiKeys$zh_Hans._(_root);
  @override
  late final _Translations$settings$shortcuts$zh_Hans shortcuts =
      _Translations$settings$shortcuts$zh_Hans._(_root);
  @override
  late final _Translations$settings$toggles$zh_Hans toggles =
      _Translations$settings$toggles$zh_Hans._(_root);
  @override
  late final _Translations$settings$diffDiffability$zh_Hans diffDiffability =
      _Translations$settings$diffDiffability$zh_Hans._(_root);
  @override
  late final _Translations$settings$modelSlots$zh_Hans modelSlots =
      _Translations$settings$modelSlots$zh_Hans._(_root);
  @override
  late final _Translations$settings$modelPicker$zh_Hans modelPicker =
      _Translations$settings$modelPicker$zh_Hans._(_root);
  @override
  late final _Translations$settings$aiFeatures$zh_Hans aiFeatures =
      _Translations$settings$aiFeatures$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitEditor$zh_Hans commitEditor =
      _Translations$settings$commitEditor$zh_Hans._(_root);
  @override
  late final _Translations$settings$review$zh_Hans review =
      _Translations$settings$review$zh_Hans._(_root);
  @override
  late final _Translations$settings$museHint$zh_Hans museHint =
      _Translations$settings$museHint$zh_Hans._(_root);
  @override
  late final _Translations$settings$museEditor$zh_Hans museEditor =
      _Translations$settings$museEditor$zh_Hans._(_root);
  @override
  late final _Translations$settings$museStage$zh_Hans museStage =
      _Translations$settings$museStage$zh_Hans._(_root);
  @override
  late final _Translations$settings$lensAxis$zh_Hans lensAxis =
      _Translations$settings$lensAxis$zh_Hans._(_root);
  @override
  late final _Translations$settings$logosLens$zh_Hans logosLens =
      _Translations$settings$logosLens$zh_Hans._(_root);
  @override
  late final _Translations$settings$sortGuide$zh_Hans sortGuide =
      _Translations$settings$sortGuide$zh_Hans._(_root);
  @override
  late final _Translations$settings$piggyback$zh_Hans piggyback =
      _Translations$settings$piggyback$zh_Hans._(_root);
  @override
  late final _Translations$settings$diffStage$zh_Hans diffStage =
      _Translations$settings$diffStage$zh_Hans._(_root);
  @override
  late final _Translations$settings$undoScope$zh_Hans undoScope =
      _Translations$settings$undoScope$zh_Hans._(_root);
  @override
  late final _Translations$settings$undoWindow$zh_Hans undoWindow =
      _Translations$settings$undoWindow$zh_Hans._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$zh_Hans guardrailPhrase =
      _Translations$settings$guardrailPhrase$zh_Hans._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$zh_Hans reviewGuideHint =
      _Translations$settings$reviewGuideHint$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitFormat$zh_Hans commitFormat =
      _Translations$settings$commitFormat$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$zh_Hans commitPreview =
      _Translations$settings$commitPreview$zh_Hans._(_root);
  @override
  late final _Translations$settings$externalTools$zh_Hans externalTools =
      _Translations$settings$externalTools$zh_Hans._(_root);
  @override
  late final _Translations$settings$apiUsage$zh_Hans apiUsage =
      _Translations$settings$apiUsage$zh_Hans._(_root);
  @override
  late final _Translations$settings$gitea$zh_Hans gitea =
      _Translations$settings$gitea$zh_Hans._(_root);
  @override
  late final _Translations$settings$wick$zh_Hans wick =
      _Translations$settings$wick$zh_Hans._(_root);
  @override
  late final _Translations$settings$integrations$zh_Hans integrations =
      _Translations$settings$integrations$zh_Hans._(_root);
  @override
  late final _Translations$settings$reduceMotion$zh_Hans reduceMotion =
      _Translations$settings$reduceMotion$zh_Hans._(_root);
  @override
  late final _Translations$settings$resetQuit$zh_Hans resetQuit =
      _Translations$settings$resetQuit$zh_Hans._(_root);
  @override
  late final _Translations$settings$diagnostics$zh_Hans diagnostics =
      _Translations$settings$diagnostics$zh_Hans._(_root);
  @override
  late final _Translations$settings$telemetry$zh_Hans telemetry =
      _Translations$settings$telemetry$zh_Hans._(_root);
  @override
  late final _Translations$settings$flowEngine$zh_Hans flowEngine =
      _Translations$settings$flowEngine$zh_Hans._(_root);
  @override
  late final _Translations$settings$museStrands$zh_Hans museStrands =
      _Translations$settings$museStrands$zh_Hans._(_root);
  @override
  late final _Translations$settings$cliPiggyback$zh_Hans cliPiggyback =
      _Translations$settings$cliPiggyback$zh_Hans._(_root);
  @override
  late final _Translations$settings$header$zh_Hans header =
      _Translations$settings$header$zh_Hans._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$zh_Hans diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$zh_Hans._(_root);
  @override
  late final _Translations$settings$release$zh_Hans release =
      _Translations$settings$release$zh_Hans._(_root);
  @override
  late final _Translations$settings$providerStatus$zh_Hans providerStatus =
      _Translations$settings$providerStatus$zh_Hans._(_root);
  @override
  late final _Translations$settings$meridiem$zh_Hans meridiem =
      _Translations$settings$meridiem$zh_Hans._(_root);
  @override
  late final _Translations$settings$offenders$zh_Hans offenders =
      _Translations$settings$offenders$zh_Hans._(_root);
}

// Path: sync
class _Translations$sync$zh_Hans extends Translations$sync$en {
  _Translations$sync$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$zh_Hans actions =
      _Translations$sync$actions$zh_Hans._(_root);
  @override
  late final _Translations$sync$panel$zh_Hans panel =
      _Translations$sync$panel$zh_Hans._(_root);
  @override
  late final _Translations$sync$forcePush$zh_Hans forcePush =
      _Translations$sync$forcePush$zh_Hans._(_root);
}

// Path: xray
class _Translations$xray$zh_Hans extends Translations$xray$en {
  _Translations$xray$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$zh_Hans board =
      _Translations$xray$board$zh_Hans._(_root);
  @override
  late final _Translations$xray$cadence$zh_Hans cadence =
      _Translations$xray$cadence$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$zh_Hans cards =
      _Translations$xray$cards$zh_Hans._(_root);
  @override
  late final _Translations$xray$cardTitle$zh_Hans cardTitle =
      _Translations$xray$cardTitle$zh_Hans._(_root);
  @override
  late final _Translations$xray$grain$zh_Hans grain =
      _Translations$xray$grain$zh_Hans._(_root);
  @override
  late final _Translations$xray$header$zh_Hans header =
      _Translations$xray$header$zh_Hans._(_root);
  @override
  late final _Translations$xray$hotspot$zh_Hans hotspot =
      _Translations$xray$hotspot$zh_Hans._(_root);
  @override
  late final _Translations$xray$inspector$zh_Hans inspector =
      _Translations$xray$inspector$zh_Hans._(_root);
  @override
  late final _Translations$xray$loadingCard$zh_Hans loadingCard =
      _Translations$xray$loadingCard$zh_Hans._(_root);
  @override
  late final _Translations$xray$metabolism$zh_Hans metabolism =
      _Translations$xray$metabolism$zh_Hans._(_root);
  @override
  late final _Translations$xray$multi$zh_Hans multi =
      _Translations$xray$multi$zh_Hans._(_root);
  @override
  late final _Translations$xray$recency$zh_Hans recency =
      _Translations$xray$recency$zh_Hans._(_root);
  @override
  late final _Translations$xray$rings$zh_Hans rings =
      _Translations$xray$rings$zh_Hans._(_root);
  @override
  late final _Translations$xray$stats$zh_Hans stats =
      _Translations$xray$stats$zh_Hans._(_root);
  @override
  late final _Translations$xray$stratumLabel$zh_Hans stratumLabel =
      _Translations$xray$stratumLabel$zh_Hans._(_root);
  @override
  late final _Translations$xray$summary$zh_Hans summary =
      _Translations$xray$summary$zh_Hans._(_root);
  @override
  late final _Translations$xray$tabs$zh_Hans tabs =
      _Translations$xray$tabs$zh_Hans._(_root);
  @override
  late final _Translations$xray$trajectory$zh_Hans trajectory =
      _Translations$xray$trajectory$zh_Hans._(_root);
  @override
  late final _Translations$xray$verdict$zh_Hans verdict =
      _Translations$xray$verdict$zh_Hans._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$zh_Hans
    extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '键盘';
  @override
  String get sectionNavigate => '导航';
  @override
  String get sectionStaging => '暂存';
  @override
  String get sectionBranchesPrs => '分支与 PR';
  @override
  String get changes => '更改';
  @override
  String get history => '历史';
  @override
  String get branches => '分支';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => '切换（始终）';
  @override
  String get commandPalette => '命令面板';
  @override
  String get elevatedPalette => '提升面板';
  @override
  String get dismiss => '关闭';
  @override
  String get refresh => '刷新';
  @override
  String get nextPrevChange => '下一处 / 上一处改动';
  @override
  String get toggleLine => '切换行';
  @override
  String get toggleHunk => '切换 hunk';
  @override
  String get toggleFile => '切换文件';
  @override
  String get pinContext => '固定上下文';
  @override
  String get commit => '提交';
  @override
  String get acceptAiHint => '采纳 AI 提示';
  @override
  String get undo => '撤销';
  @override
  String get navigate => '导航';
  @override
  String get expand => '展开';
  @override
  String get checkoutPr => '检出 PR';
  @override
  String get approve => '批准';
  @override
  String get requestChanges => '请求修改';
  @override
  String profileSwitchHint({required Object profile}) =>
      '${profile} 配置 · 在设置中切换';
}

// Path: backend.ops
class _Translations$backend$ops$zh_Hans extends Translations$backend$ops$en {
  _Translations$backend$ops$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get merge => '合并';
  @override
  String get pull => '拉取';
  @override
  String get apply => '应用';
  @override
  String get switchOp => '切换';
  @override
  String get sync => '同步';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$zh_Hans
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '已取消${op}。';
  @override
  String complete({required Object op}) => '${op}完成。';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '还剩 ${n} 个冲突 — 请在“更改”页面解决。',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '已解决 ${n} 个冲突。',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件有未提交的改动 — 请先提交。',
      );
}

// Path: changes.usage
class _Translations$changes$usage$zh_Hans
    extends Translations$changes$usage$en {
  _Translations$changes$usage$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} 入 · ${output} 出';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} 入 · ${cached} 缓存 · ${out} 出';
  @override
  String get inWord => '入';
  @override
  String get cachedWord => '缓存';
  @override
  String get outWord => '出';
  @override
  String tipIn({required Object value}) => '${value}  入';
  @override
  String tipCacheRead({required Object value}) => '${value}  缓存读取';
  @override
  String tipCacheWrite({required Object value}) => '${value}  缓存写入';
  @override
  String tipOut({required Object value}) => '${value}  出';
  @override
  String tipReasoning({required Object value}) => '${value}  推理';
  @override
  String tipWallClock({required Object value}) => '${value}s  实际耗时';
}

// Path: changes.tabs
class _Translations$changes$tabs$zh_Hans extends Translations$changes$tabs$en {
  _Translations$changes$tabs$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => '更改';
  @override
  String get empty => '空';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$zh_Hans
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => '新建差异标签页';
}

// Path: changes.select
class _Translations$changes$select$zh_Hans
    extends Translations$changes$select$en {
  _Translations$changes$select$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => '全选';
  @override
  String get deselectAll => '取消全选';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$zh_Hans
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => '返回列表';
  @override
  String get atlas => '星图，查看提交候选';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$zh_Hans
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\n与 ${anchor} 耦合 · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$zh_Hans
    extends Translations$changes$minimap$en {
  _Translations$changes$minimap$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => '新';
  @override
  String get roleBridge => '桥';
  @override
  String get roleHub => '枢纽';
  @override
  String get roleLeaf => '叶';
  @override
  String get roleConnected => '已连接';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => '与 ${name} 一同改动';
  @override
  String get newFile => '新文件';
  @override
  String nearOtherChanges({required Object dir, required Object count}) =>
      '靠近 ${dir} 中另外 ${count} 处改动';
  @override
  String usuallyChangesWithFile({required Object name}) => '${name} 通常与此文件一同改动';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$zh_Hans
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hint => '标签…';
}

// Path: changes.composer
class _Translations$changes$composer$zh_Hans
    extends Translations$changes$composer$en {
  _Translations$changes$composer$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => '提交信息…';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$zh_Hans
    extends Translations$changes$commit$en {
  _Translations$changes$commit$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => '提交更改';
  @override
  String get primaryCommitChangesDetail => '游离 HEAD：本地提交，不同步。';
  @override
  String get primaryPublish => '提交并发布';
  @override
  String get primaryPublishDetail => '一步创建提交并发布此分支。';
  @override
  String get primarySync => '提交并同步';
  @override
  String get primarySyncDetail => '创建提交，然后协调并推送分支。';
  @override
  String get primaryPush => '提交并推送';
  @override
  String get primaryPushDetail => '创建提交并立即推送。';
  @override
  String get amendLast => '修订上一个提交';
  @override
  String amendAnd({required Object action}) => '修订并${action}';
  @override
  String get chooseFile => '为下一个提交至少选择一个文件。';
  @override
  String get writeMessage => '请先写一条提交信息。';
  @override
  String get committing => '正在提交';
  @override
  String get committingSync => '正在提交并同步';
  @override
  String get committed => '已提交。';
  @override
  String get undoFailed => '撤销失败。';
  @override
  String get working => '处理中…';
  @override
  String get commitOnly => '仅提交';
  @override
  String get noRuntimeModels => '没有可用于提交信息的运行时发现模型。';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\n无法恢复被排除文件的暂存；重试前请检查索引。';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      '已提交 ${summary}（${hash}）。';
  @override
  String get restoreFailedSync => '无法重新暂存被排除文件的选择；已跳过同步。同步前请检查索引。';
  @override
  String get noModelLabel => '无模型';
  @override
  String get chooseBeforeGenerate => '生成前至少选择一个文件。';
  @override
  String get aiUnavailable => '提交信息 AI 尚不可用。';
  @override
  String get generateFailed => '生成失败。';
  @override
  String get stageFailed => '暂存文件失败。';
  @override
  String get commitFailed => '提交失败。';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => '已提交 ${summary}（${hash}）并运行了 ${operation}。';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
    n,
    other: '已提交 ${summary}（${hash}）；解决了 ${n} 个冲突。',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '还剩 ${n} 个冲突待解决。',
      );
  @override
  String syncBlocked({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '提交成功，但同步被 ${n} 个未提交文件阻挡。',
      );
  @override
  String syncStalled({required Object message}) => '提交成功，但同步停滞：${message}';
  @override
  String syncFailed({required Object message}) => '提交成功，但同步失败：${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$zh_Hans
    extends Translations$changes$rebase$en {
  _Translations$changes$rebase$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => '无法继续变基。';
}

// Path: changes.editor
class _Translations$changes$editor$zh_Hans
    extends Translations$changes$editor$en {
  _Translations$changes$editor$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => '关闭编辑器';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$zh_Hans
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    '亲爱的 git log',
    '看在 git 的份上，容我诉说…',
    '给这一刻起个名',
    '尽情唠',
    '说吧！',
    '你妈是个悬空引用，你爹一身分号味',
  ];
  @override
  List<String> get short => [
    '哦？',
    '你好呀 :)',
    '顺便说：',
    '三言两语',
    '客气点的版本',
    '留个便条',
    '你刚说到哪..?',
    '对了，说出来吧',
  ];
  @override
  List<String> get mid => [
    '记录在案',
    '告诉未来的你',
    '但先说说？',
    '过程如何',
    '用你自己的话',
    '你刚干了啥来着？',
    '已悉数记下',
    '我洗耳恭听',
  ];
  @override
  List<String> get long => [
    '请说说你的梦想',
    '说点好听的',
    '……然后我说：',
    '后世正等着呢',
    '写得越多，bug 越少',
    '哦哇',
    '神圣文本',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$zh_Hans
    extends Translations$changes$askHint$en {
  _Translations$changes$askHint$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) => '第 ${n} 轮 — 细化或补充上下文。';
  @override
  String get symptom => '描述症状。';
  @override
  String get broken => '哪儿坏了？';
  @override
  String get bug => '描述这个 bug。';
  @override
  String get error => '粘贴报错。';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$zh_Hans
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => '涟漪';
  @override
  String get includeCoChanges => '包含共变';
  @override
  String deleteFile({required Object name}) => '删除 ${name}…';
  @override
  String discardChangesTo({required Object name}) => '丢弃对 ${name} 的改动…';
  @override
  String get ignore => '忽略';
  @override
  String get diffTabFromSelection => '从选中项建差异标签页';
  @override
  String addSelectedToTab({required Object name}) => '将选中项加入 ${name}';
  @override
  String diffTabFromFile({required Object name}) => '从 ${name} 建差异标签页';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      '将 ${file} 加入 ${tab}';
  @override
  String get copyFilePath => '复制文件路径';
  @override
  String get showInExplorer => '在资源管理器中显示';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$zh_Hans
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => '紧密耦合';
  @override
  String get cohesionLoose => '松散相关';
  @override
  String get cohesionScattered => '结构上分散';
  @override
  String get clusterOne => '全在一个簇里';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      '横跨 ${count} 个簇（${parts} 个文件）';
  @override
  String clusterSpans({required Object count}) => '横跨 ${count} 个簇';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} 个文件 · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) => '${file} 通常与此组一同改动';
  @override
  String get splitToNewTab => '拆分到新标签页';
  @override
  String copyPaths({required Object count}) => '复制 ${count} 个路径';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$zh_Hans
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => '.${ext} 扩展名';
  @override
  String allSelected({required Object count}) => '全部 ${count} 个选中项';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '与 ${n} 个已包含文件耦合',
      );
  @override
  String get updateFailed => '更新 .gitignore 失败。';
}

// Path: changes.discard
class _Translations$changes$discard$zh_Hans
    extends Translations$changes$discard$en {
  _Translations$changes$discard$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '删除 ${name}？';
  @override
  String discardTitle({required Object name}) => '丢弃对 ${name} 的改动？';
  @override
  String deleteBody({required Object path}) => '${path} 将从磁盘移除。此操作无法在应用内撤销。';
  @override
  String discardBody({required Object path}) =>
      '对 ${path} 的所有改动都将还原到 HEAD 中的状态。此操作无法撤销。';
  @override
  String get discard => '丢弃';
  @override
  String deletingFile({required Object name}) => '正在删除 ${name}';
  @override
  String discardingFile({required Object name}) => '正在丢弃 ${name}';
  @override
  String get discardFailed => '丢弃改动失败。';
  @override
  String discardManyTitle({required Object count}) => '丢弃对 ${count} 个文件的改动？';
  @override
  String get discardManyBody => '已跟踪的文件将还原到 HEAD 中的状态；未跟踪的文件将从磁盘移除。此操作无法撤销。';
  @override
  String discardManyConfirm({required Object count}) => '丢弃 ${count} 个';
  @override
  String discardingManyFiles({required Object count}) => '正在丢弃 ${count} 个文件';
  @override
  String failedOpenExplorer({required Object error}) => '打开文件管理器失败：${error}';
  @override
  String get someFailed => '部分丢弃失败。';
}

// Path: changes.snack
class _Translations$changes$snack$zh_Hans
    extends Translations$changes$snack$en {
  _Translations$changes$snack$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => '同一工作树 — 没什么可倒出的。';
  @override
  String diffFailed({required Object error}) => '差异失败：${error}';
  @override
  String get deskEmpty => 'Desk 没有领先于你的内容 — 空倒。';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) => '搁架读取失败：${error}';
  @override
  String get shelfEmpty => '空搁架 — 没什么可倒出的。';
  @override
  String sourceShelf({required Object label}) => '搁架 ${label}';
  @override
  String noModelConfigured({required Object label}) => '未为“${label}”配置模型。';
  @override
  String fetchFailed({required Object error}) => '抓取失败：${error}';
}

// Path: changes.trace
class _Translations$changes$trace$zh_Hans
    extends Translations$changes$trace$en {
  _Translations$changes$trace$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '验证轨迹';
  @override
  String get draftReview => '草稿审查';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$zh_Hans
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '工作区干净';
  @override
  String get subtitle => '未检测到已暂存或未暂存的改动。';
  @override
  String get noUpstream => '  ·  无上游';
  @override
  String get ahead => ' 领先';
  @override
  String get behind => ' 落后';
  @override
  String get refreshing => '正在刷新…';
  @override
  String get refresh => '刷新';
  @override
  String get check => '检查';
  @override
  String get checkTooltip => '抓取并本地刷新。';
  @override
  String get sync => '& 同步';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$zh_Hans
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '宽松';
  @override
  String get balanced => '均衡';
  @override
  String get strict => '严格';
  @override
  String get paranoid => '偏执';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$zh_Hans
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf => '拖放以把此搁架的改动带到这里';
  @override
  String get fromDesk => '拖放以把此 Desk 的改动带到这里';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$zh_Hans
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '未选择文件';
  @override
  String get message => '选择一个已更改的文件以查看其差异。';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$zh_Hans
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ 搁置 ${count}';
  @override
  String get shelve => '↓ 搁置';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '已搁置 ${count} 个 ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$zh_Hans
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => '取回';
  @override
  String get peek => '窥看';
  @override
  String get toss => '扔掉';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$zh_Hans
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get reading => '正在读取搁架…';
  @override
  String get empty => '空搁架';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$zh_Hans
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$zh_Hans
    extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => '仅提交已暂存的行';
  @override
  String get doubleClickToggle => '双击：切换整组';
  @override
  String get repoRoot => '仓库根';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$zh_Hans
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '正在读取 ${n} 个文件 · 起草解决方案…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${files} 中共 ${n} 个冲突',
      );
  @override
  String get resolve => '解决';
  @override
  String get orWith => '或使用';
  @override
  String resolveWith({required Object label}) => '用 ${label} 解决';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      '用 ${label} 解决  ·  ${model}';
  @override
  String get resolving => '正在解决…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  用 ${label} 解决';
  @override
  String get orWithAnother => '或用其他模型';
}

// Path: changes.badge
class _Translations$changes$badge$zh_Hans
    extends Translations$changes$badge$en {
  _Translations$changes$badge$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => '已暂存的编辑';
  @override
  String get edited => '已编辑';
  @override
  String get stagedAdd => '已暂存的新增';
  @override
  String get added => '已添加';
  @override
  String get stagedDelete => '已暂存的删除';
  @override
  String get deleted => '已删除';
  @override
  String get stagedRename => '已暂存的重命名';
  @override
  String get renamed => '已重命名';
  @override
  String get stagedCopy => '已暂存的复制';
  @override
  String get copied => '已复制';
  @override
  String get conflict => '冲突';
  @override
  String get stagedTypeChange => '已暂存的类型变更';
  @override
  String get typeChanged => '类型已变更';
  @override
  String get untracked => '未跟踪';
}

// Path: changes.review
class _Translations$changes$review$zh_Hans
    extends Translations$changes$review$en {
  _Translations$changes$review$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '代码审查';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个已包含文件',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个 hunk',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => '审查不可用';
  @override
  String get backToDiff => '返回差异';
  @override
  String get verified => '已验证';
  @override
  String get draftOnly => '仅草稿';
  @override
  String get runAgain => '再次运行';
  @override
  String draftShownBelow({required Object error}) => '${error} 草稿审查显示在下方。';
  @override
  String get hideTrace => '隐藏轨迹';
  @override
  String get showTrace => '显示轨迹';
  @override
  String get showVerificationTrace => '显示验证轨迹';
  @override
  String get whyLanded => '此审查为何落在这里';
  @override
  String get noFindings => '无发现';
  @override
  String get findings => '发现';
  @override
  String get noEvidenceIssues => '此提交范围内未浮现有证据支持的问题。';
  @override
  String get observations => '观察';
  @override
  String get chooseBeforeReview => '审查前至少选择一个文件。';
  @override
  String get aiUnavailable => '审查 AI 尚不可用。';
  @override
  String get failed => '审查失败。';
  @override
  String get noRuntimeModels => '没有可用于提交审查的运行时发现模型。';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$zh_Hans
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => '切换到：${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$zh_Hans
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => '正在用 ${cat} 询问…';
  @override
  String askWith({required Object cat}) => '用 ${cat} 询问';
  @override
  String get noModel => '未配置 AI 模型';
  @override
  String nextTooltip({required Object cat}) => '下一个：${cat}  ·  shift+点击选上一个';
  @override
  String get onlyOne => '只配置了一个 AI 类别';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$zh_Hans
    extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({required num n, required Object pct}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${pct}% 既视感 — 来自被丢弃时间线的 ${n} 条幽灵边触及此差异',
      );
  @override
  String get label => '既视感';
}

// Path: changes.identity
class _Translations$changes$identity$zh_Hans
    extends Translations$changes$identity$en {
  _Translations$changes$identity$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get none => '未配置提交身份';
  @override
  String asName({required Object name}) => '以 ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      '以 ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => '以 ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\n此仓库的首个提交';
  @override
  String get newToRepo => '\n初来此仓库';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$zh_Hans
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get message => '自本次运行后选择已改变';
  @override
  String get rerun => '重新运行';
}

// Path: changes.finding
class _Translations$changes$finding$zh_Hans
    extends Translations$changes$finding$en {
  _Translations$changes$finding$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => '打开差异';
  @override
  String get recorded => '已记录';
  @override
  String get dismiss => '忽略';
}

// Path: changes.muse
class _Translations$changes$muse$zh_Hans extends Translations$changes$muse$en {
  _Translations$changes$muse$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => '你抽出了这个';
  @override
  String fromIdea({required Object text}) => '来自想法：“${text}”';
  @override
  String get foothold => '落脚点 — ';
  @override
  String get brainstormSpew => '头脑风暴喷涌';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => '复制 ${count}';
  @override
  String get clear => '清除';
  @override
  String get chooseBeforeMuse => '唤起 muse 前至少选择一个文件。';
  @override
  String get aiUnavailable => 'Muse AI 尚不可用。';
  @override
  String get failed => 'Muse 失败。';
  @override
  String get noRuntimeModels => '没有可用于 muse 的运行时发现模型。';
  @override
  String get needsModel => 'Muse 至少需要一个已配置的模型。';
  @override
  String get dreaming => 'muse 正在做梦…';
}

// Path: changes.debug
class _Translations$changes$debug$zh_Hans
    extends Translations$changes$debug$en {
  _Translations$changes$debug$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '调试';
  @override
  String round({required Object n}) => '· 第 ${n} 轮';
  @override
  String get clear => '清除';
  @override
  String get close => '关闭';
  @override
  String get analyzing => '正在分析症状…';
  @override
  String get describeSymptom => '描述一个症状，然后按调试。';
  @override
  String get evidenceFor => '支持';
  @override
  String get evidenceAgainst => '但是';
  @override
  String get narrowDown => '有助于缩小范围的：';
  @override
  String get failed => '调试失败。';
  @override
  String get refinementFailed => '调试细化失败。';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$zh_Hans
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get none => '无';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} 个已暂存';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '全部 ${n} 个文件${staged}',
      );
  @override
  String partial({
    required Object n,
    required Object count,
    required Object staged,
  }) => '${n} 个中的 ${count} 个${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      '全部 ${n} 个${staged}';
}

// Path: changes.status
class _Translations$changes$status$zh_Hans
    extends Translations$changes$status$en {
  _Translations$changes$status$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => '仓库状态不可用';
  @override
  String get loadingTitle => '正在加载仓库状态';
  @override
  String get loadingMessage => '正在读取工作区。';
}

// Path: changes.stash
class _Translations$changes$stash$zh_Hans
    extends Translations$changes$stash$en {
  _Translations$changes$stash$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts => '储藏应用时产生冲突 — 请在“更改”页面解决（储藏条目已保留）。';
  @override
  String get couldNotPop => '无法弹出储藏。';
  @override
  String get listChanged => '储藏列表已改变；已跳过丢弃。请重试。';
  @override
  String get droppingStash => '正在丢弃储藏';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$zh_Hans
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => '正在生成提交信息…';
  @override
  String get commitPreparing => '正在准备提交信息…';
  @override
  String get commitSelectFile => '至少选择一个文件以生成提交信息。';
  @override
  String get commitConfigure => '在 设置 > 行为动态 > 提交信息 中配置提交信息。';
  @override
  String get fastFallback => '快速';
  @override
  String commitGenerateWith({required Object label}) => '用 ${label} 模型生成提交信息';
  @override
  String get museConsulting => '正在咨询 muse…';
  @override
  String get showMuse => '显示 muse';
  @override
  String get museSelectFile => '为 muse 至少选择一个文件。';
  @override
  String get showMuseError => '显示 muse 错误';
  @override
  String get museAsk => '向 muse 求方向';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => '向 muse 求方向\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => '高质';
  @override
  String get reviewing => '正在审查…';
  @override
  String get showReview => '显示审查';
  @override
  String get reviewPreparing => '正在准备提交审查…';
  @override
  String get reviewSelectFile => '至少选择一个文件以审查。';
  @override
  String get reviewConfigure => '在设置中配置审查 AI。';
  @override
  String get viewingReview => '正在查看审查';
  @override
  String reviewWith({required Object label, required Object guardrail}) =>
      '用 ${label} 模型进行 ${guardrail} 审查';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$zh_Hans
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => '我方';
  @override
  String get resolutionTheirs => '他方';
  @override
  String get resolutionCustom => '自定义';
  @override
  String get keepBoth => '两者都留';
  @override
  late final _Translations$changes$mergeEditor$trust$zh_Hans trust =
      _Translations$changes$mergeEditor$trust$zh_Hans._(_root);
  @override
  String get allResolved => '全部已解决';
  @override
  String get resolveEasy => '解决简单冲突';
  @override
  String get base => '基准';
  @override
  String get cancel => '取消';
  @override
  String get save => '保存';
  @override
  String get complete => '完成';
  @override
  String get nextFile => '下一个文件';
  @override
  String get edit => '编辑';
  @override
  String get auto => '自动';
  @override
  String get undo => '撤销';
  @override
  late final _Translations$changes$mergeEditor$keyHints$zh_Hans keyHints =
      _Translations$changes$mergeEditor$keyHints$zh_Hans._(_root);
  @override
  String get favoredTooltip => '耦合分析在结构上更倾向此方';
  @override
  String get newOnBothSides => '（两侧都是新的）';
  @override
  String writeFailed({required Object error}) => '写入已解决文件失败：${error}';
  @override
  String neighborsCoChanged({required Object total, required Object changed}) =>
      '${total} 个邻居中 ${changed} 个共变';
  @override
  String integrity({required Object pct}) => '完整性 ${pct}%';
  @override
  String reviewer({required Object name}) => '审查者：${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$zh_Hans
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      '未为“${category}”配置模型。请在 设置 → AI 中设置一个。';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '已跳过 ${n} 个敏感文件 — 请手动解决。',
      );
  @override
  String get couldNotReadFiles => '无法读取任何冲突文件。';
  @override
  String blockedSecret({required Object secret}) =>
      '已阻止 — 某个冲突文件看起来含有 ${secret}。请手动解决。';
  @override
  String resolutionFailed({required Object error}) => '解决失败：${error}';
  @override
  String mergeResolutionLabel({
    required Object total,
    required Object resolved,
    required Object category,
  }) => '◇ 合并解决 · ${total} 个文件中的 ${resolved} 个 · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object files,
    required Object conflicts,
  }) => '${op} · ${files} 中的 ${conflicts}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个冲突',
      );
  @override
  String get mergeEditorButton => '⇋ 合并编辑器';
  @override
  String get noAiModel => '无 AI 模型';
  @override
  String get later => '稍后';
  @override
  String get discard => '丢弃';
  @override
  String get resolveWithAi => '◇ 用 AI 解决';
  @override
  String get otherModel => '其他模型';
  @override
  String withModel({required Object model}) => '用 ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$zh_Hans
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$zh_Hans op =
      _Translations$changes$mergeFlow$op$zh_Hans._(_root);
  @override
  String get pushFailed => '推送失败';
  @override
  String get rebasedAndPushed => '已变基并推送。';
  @override
  String switchedTo({required Object name}) => '已切换到 ${name}。';
  @override
  String get switchFailed => '切换失败。';
  @override
  String switchedToCarried({required Object name}) => '已切换到 ${name}（改动已带过来）。';
  @override
  String get alreadyUpToDate => '已是最新。';
  @override
  String merged({required Object upstream, required Object n}) =>
      '已合并 ${upstream}（${n} 个文件）。';
  @override
  String get rebaseNotConverge => '变基未收敛 — 请手动解决。';
  @override
  String get rebased => '已变基。';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '已变基（解决了 ${n} 个文件）。',
      );
  @override
  String get detachedHead => '无法同步：处于游离 HEAD 状态。请先检出一个分支。';
  @override
  String get publishFailed => '发布失败。';
  @override
  String get noRemote => '未配置远程。添加一个以发布此分支。';
  @override
  String get failed => '失败';
}

// Path: changes.constellation
class _Translations$changes$constellation$zh_Hans
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => '结构';
  @override
  String get axisCoChange => '共变';
  @override
  String get axisSpectralProfile => '谱剖面';
  @override
  String get axisPathSiblings => '路径同胞';
  @override
  String get axisDiffStructure => '差异结构';
  @override
  String get axisSpectral => '谱';
  @override
  String get titleUnsorted => '未排序';
  @override
  String get titleSingleton => '孤立项';
  @override
  String get titleMixed => '混合';
  @override
  String get untie => '解绑';
  @override
  String get bind => '绑定';
  @override
  String get emptyClusters => '暂无簇';
}

// Path: common.time
class _Translations$common$time$zh_Hans extends Translations$common$time$en {
  _Translations$common$time$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get now => '现在';
  @override
  String get justNow => '刚刚';
  @override
  String get today => '今天';
  @override
  String minutesAgo({required Object n}) => '${n} 分钟前';
  @override
  String hoursAgo({required Object n}) => '${n} 小时前';
  @override
  String daysAgo({required Object n}) => '${n} 天前';
  @override
  String weeksAgo({required Object n}) => '${n} 周前';
  @override
  String monthsAgo({required Object n}) => '${n} 个月前';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        one: '${n} 年前',
        other: '${n} 年前',
      );
  @override
  String minutesShort({required Object n}) => '${n} 分';
  @override
  String hoursShort({required Object n}) => '${n} 时';
  @override
  String daysShort({required Object n}) => '${n} 天';
  @override
  String weeksShort({required Object n}) => '${n} 周';
  @override
  String monthsShort({required Object n}) => '${n} 月';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        one: '${n} 年',
        other: '${n} 年',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n} 月';
  @override
  String get idle => '闲置';
  @override
  String idleDays({required Object n}) => '闲置 ${n} 天';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '闲置 ${n} 年',
      );
  @override
  List<String> get monthAbbrevs => [
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ];
}

// Path: common.size
class _Translations$common$size$zh_Hans extends Translations$common$size$en {
  _Translations$common$size$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

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
class _Translations$diff$status$zh_Hans extends Translations$diff$status$en {
  _Translations$diff$status$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => '正在加载差异';
  @override
  String get loadingMessage => '正在读取文件改动。';
  @override
  String get unavailableTitle => '差异不可用';
  @override
  String get noChangesTitle => '无改动';
  @override
  String get noChangesMessage => '此文件没有可显示的差异内容。';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$zh_Hans extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => '搜索差异…';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 行',
      );
  @override
  String get blameLoading => 'blame…';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => '磨损 · 开';
  @override
  String get wearMapOnHint => '磨损图已开 — 点击隐藏';
  @override
  String get wearMapOffHint => '显示磨损图（活动热力图）';
  @override
  String get trailBadge => '· 轨迹';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$zh_Hans
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => '跳到改动块。Git 称之为 hunk。';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 处改动',
      );
}

// Path: diff.trail
class _Translations$diff$trail$zh_Hans extends Translations$diff$trail$en {
  _Translations$diff$trail$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '正在加载轨迹…';
  @override
  String get noHistory => '未找到历史';
  @override
  String get nowWorkingCopy => '现在 · 工作副本';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$zh_Hans extends Translations$diff$pinned$en {
  _Translations$diff$pinned$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => '正在加载固定上下文';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => '信号';
  @override
  String get echoesTitle => '回响';
  @override
  String get technicalLedger => '技术账本';
  @override
  String get noSecondaryCues => '未检测到次级线索。';
  @override
  String get linkedPaths => '关联路径';
  @override
  String moreCount({required Object n}) => '+${n} 更多';
  @override
  String get localSeam => '局部接缝';
  @override
  String get sharedOwnership => '共有归属';
  @override
  String get historyWarmingUp => '历史预热中';
  @override
  String echoesTotal({required Object n}) => '共 ${n}';
  @override
  String get noEchoes => '此差异中无回响。';
  @override
  String openRelatedFile({required Object name}) => '打开关联文件 ${name}';
  @override
  String inspectFile({required Object name}) => '查看 ${name}';
  @override
  String get jumpEcho => '跳到回响';
  @override
  String get copyLine => '复制行';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$zh_Hans tempo =
      _Translations$diff$pinned$tempo$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$tone$zh_Hans tone =
      _Translations$diff$pinned$tone$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$summary$zh_Hans summary =
      _Translations$diff$pinned$summary$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$tightness$zh_Hans tightness =
      _Translations$diff$pinned$tightness$zh_Hans._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept}（${tightness}）';
  @override
  String get storyWhyThisMatters => '为何重要';
  @override
  String get storyConfidence => '置信度';
  @override
  String get storySecondarySignal => '次级信号';
  @override
  String get storyNeighbourhood => '邻域';
  @override
  String neighbourhoodDetail({required Object name}) =>
      '在当前代码库场中，此行与 ${name} 相邻。';
  @override
  String get propagationLane => '传播轨道';
  @override
  String propagationLaneNamed({required Object lane}) => '传播轨道：${lane}';
  @override
  late final _Translations$diff$pinned$witness$zh_Hans witness =
      _Translations$diff$pinned$witness$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$integrity$zh_Hans integrity =
      _Translations$diff$pinned$integrity$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$related$zh_Hans related =
      _Translations$diff$pinned$related$zh_Hans._(_root);
  @override
  late final _Translations$diff$pinned$axis$zh_Hans axis =
      _Translations$diff$pinned$axis$zh_Hans._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$zh_Hans
    extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} 隐藏';
  @override
  String get landing => '落点';
}

// Path: diff.binary
class _Translations$diff$binary$zh_Hans extends Translations$diff$binary$en {
  _Translations$diff$binary$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) => '${size} MB（过大，无法预览）';
  @override
  String get unableToLoadBlob => '无法加载 blob';
  @override
  String get omittedKindMedia => '媒体';
  @override
  String get omittedKindBinary => '二进制';
  @override
  String omittedStub({required Object kind}) => '${kind} · 已隐藏';
}

// Path: diff.media
class _Translations$diff$media$zh_Hans extends Translations$diff$media$en {
  _Translations$diff$media$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => '无法解码图像';
  @override
  String sizeLabel({required Object format, required Object size}) =>
      '${format}  ${size}';
  @override
  String sizeDelta({
    required Object oldSize,
    required Object newSize,
    required Object sign,
    required Object delta,
  }) => '${oldSize} → ${newSize}  （${sign}${delta}）';
  @override
  String get stateAdded => '已添加';
  @override
  String get stateDeleted => '已删除';
  @override
  String get stateModified => '已修改';
  @override
  String get fallbackFormatName => '二进制';
}

// Path: filament.severity
class _Translations$filament$severity$zh_Hans
    extends Translations$filament$severity$en {
  _Translations$filament$severity$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get critical => '严重';
  @override
  String get warn => '警告';
  @override
  String get info => '信息';
  @override
  String get joint => '联合';
}

// Path: filament.kind
class _Translations$filament$kind$zh_Hans
    extends Translations$filament$kind$en {
  _Translations$filament$kind$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => '陈旧值';
  @override
  String get temporalShift => '时序偏移';
  @override
  String get contextInversion => '上下文倒置';
  @override
  String get contradictoryFlow => '矛盾流';
}

// Path: history.commitLede
class _Translations$history$commitLede$zh_Hans
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$zh_Hans semantics =
      _Translations$history$commitLede$semantics$zh_Hans._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$zh_Hans
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '（根）';
  @override
  String dirTrackLabel({required Object name}) => '（${name}）';
  @override
  String moreLabel({required Object n}) => '+${n} 更多';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${path}/ 中 ${n} 个文件',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '还有 ${n} 个文件',
      );
  @override
  String get breadcrumbAll => '全部';
  @override
  String breadcrumbCurrentFocus({required Object target}) => '当前聚焦：${target}';
  @override
  String get breadcrumbViewAllChanges => '查看此提交的全部改动';
  @override
  String breadcrumbDrillUpTo({required Object target}) => '上钻到 ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
    n,
    other: '${n} 个文件  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个子目录',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}，新增 ${adds}，删除 ${dels}';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
    n,
    other: '${n} 个文件，新增 ${adds}，删除 ${dels}',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个 hunk',
      );
  @override
  String get largestChangeInView => '此视图中最大的改动';
  @override
  String get conflictedTag => '有冲突';
  @override
  String get dirtyTag => '脏';
  @override
  String get drillInTag => '下钻';
  @override
  String get changeTypeRenamed => '重命名';
  @override
  String get changeTypeCopied => '复制';
  @override
  String get changeTypeTypechange => '类型变更';
  @override
  String get changeTypeConflict => '冲突';
  @override
  String get coreFile => '核心文件';
  @override
  String get staleFile => '陈旧';
  @override
  String get filterPathHint => '筛选路径';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$zh_Hans
    extends Translations$history$worldline$en {
  _Translations$history$worldline$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => '关闭世界线';
  @override
  String get dragToOpenWorldline => '拖动以打开世界线';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$zh_Hans
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => '当前分支';
  @override
  String applyCommitOnto({required Object branch}) => '将此提交的改动应用到 ${branch}';
  @override
  String revertCommitOn({required Object branch}) => '在 ${branch} 上还原此提交的改动';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$zh_Hans
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get paused => '拣选已暂停。请在“更改”页面完成剩余的冲突。';
  @override
  String failed({required Object error}) => '拣选失败：${error}';
  @override
  String pickedResolved({required Object short}) => '已拣选 ${short}（已解决冲突）';
  @override
  String picked({required Object short}) => '已拣选 ${short}';
}

// Path: history.revert
class _Translations$history$revert$zh_Hans
    extends Translations$history$revert$en {
  _Translations$history$revert$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get paused => '还原已暂停。请在“更改”页面完成剩余的冲突。';
  @override
  String failed({required Object error}) => '还原失败：${error}';
  @override
  String revertedResolved({required Object short}) => '已还原 ${short}（已解决冲突）';
  @override
  String reverted({required Object short}) => '已还原 ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$zh_Hans
    extends Translations$history$reflog$en {
  _Translations$history$reflog$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => '从此处创建分支…';
  @override
  String get copyCommitHash => '复制提交哈希';
  @override
  String get createBranchDialogTitle => '从 reflog 条目创建分支';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      '锚点：${short}  ·  ${summary}';
  @override
  String get branchNameHint => '分支名';
  @override
  String get createAction => '创建';
  @override
  String createBranchFailed({required Object error}) => '创建分支失败：${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      '分支“${name}”已在 ${short} 创建。';
}

// Path: history.rebase
class _Translations$history$rebase$zh_Hans
    extends Translations$history$rebase$en {
  _Translations$history$rebase$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) => '第一个提交不能是${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '变基 ${n} 个提交',
      );
  @override
  String get resetLabel => '重置';
  @override
  String get dragToReorderHint => '拖动以重排，为每个提交选择操作';
  @override
  String get newMessageHint => '新消息';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => '开始变基';
}

// Path: history.inFlight
class _Translations$history$inFlight$zh_Hans
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get header => '进行中';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$zh_Hans
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '历史手术';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => '预演';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$zh_Hans
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => '选择要从历史中移除的文件';
  @override
  String selectedCount({required Object n}) => '已选 ${n} 个';
  @override
  String get searchHint => '搜索…';
  @override
  String get readingTree => '正在读取树…';
  @override
  String get continueDisabled => '选择文件以继续';
  @override
  String get continueEnabled => '继续 →';
  @override
  String toPurgeCount({required Object n}) => '${n} 个待清除';
  @override
  String get analyzing => '正在分析…';
  @override
  String get riskLow => '低风险';
  @override
  String get riskModerate => '中等风险';
  @override
  String get riskHigh => '高风险';
  @override
  String get impactCommitsLabel => '提交';
  @override
  String get impactBranchesLabel => '分支';
  @override
  String get impactWorktreesLabel => '工作树';
  @override
  String get impactCouplingLabel => '耦合';
  @override
  String get impactCouplingIsland => '孤岛';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} 个邻居';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$zh_Hans
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get heading => '工作原理';
  @override
  String get backupTitle => '备份';
  @override
  String get backupBody => '在任何改动之前，每个分支和标签引用都会被复制到备份命名空间。若出现问题，一键即可恢复原始状态。';
  @override
  String get rewriteTitle => '重写';
  @override
  String get rewriteBody =>
      '每个提交都会从根遍历到顶端。对于每个包含目标文件的提交，都会创建一个从树中移除了这些文件的新提交。父链会被重新映射以保留拓扑。';
  @override
  String rewriteSummary({required Object total, required Object affected}) =>
      '将重写 ${total} 个提交中的 ${affected} 个。';
  @override
  String get updateRefsTitle => '更新引用';
  @override
  String get updateRefsBody => '分支和标签指针会被移到新的提交 SHA。旧对象在垃圾回收之前仍然存在。';
  @override
  String worktreesNeedRecheckout({required Object n}) => '你的 ${n} 个工作树将需要重新检出。';
  @override
  String get noWorktreesAffected => '没有工作树受影响。';
  @override
  String get forcePushTitle => '强制推送';
  @override
  String get forcePushBody =>
      '验证清除后，你可以选择要强制推送的分支。使用 --force-with-lease，以便在此期间有人推送时安全失败。';
  @override
  String get plumbingNote =>
      '与 filter-repo 或 BFG 不同，本操作完全通过 git 底层命令（cat-file、mktree、commit-tree、update-ref）运行。无外部依赖。重命名跟踪对每个文件只跟一条链 — 如果某文件被复制且两份副本各自独立重命名，请在执行后核实清除结果。';
  @override
  String get back => '← 返回';
  @override
  String get continueLabel => '我已了解，继续 →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$zh_Hans
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) => '将重写 ${n} 个提交';
  @override
  String get forcePushRequired => '远程分支将需要强制推送';
  @override
  String worktreesRecheckout({required Object n}) => '${n} 个工作树将需要重新检出';
  @override
  String stashesInvalid({required Object n}) => '${n} 个储藏可能失效';
  @override
  String get heading => '此操作会重写 git 历史';
  @override
  String get subheading => '强制推送后无法自动撤销。';
  @override
  String typeHint({required Object word}) => '输入 ${word}';
  @override
  String get goBack => '返回';
  @override
  String get begin => '开始手术';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$zh_Hans
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => '正在准备…';
  @override
  String get backingUpRefs => '正在备份引用…';
  @override
  String get rewritingCommits => '正在重写提交…';
  @override
  String get updatingRefs => '正在更新引用…';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$zh_Hans
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get complete => '手术完成';
  @override
  String get failed => '手术失败';
  @override
  String get commitsRewrittenLabel => '已重写的提交';
  @override
  String get refsUpdatedLabel => '已更新的引用';
  @override
  String get oldHeadLabel => '旧 HEAD';
  @override
  String get newHeadLabel => '新 HEAD';
  @override
  String get purgeVerifiedLabel => '清除已验证';
  @override
  String get purgeClean => '干净';
  @override
  String get purgeTracesRemain => '仍有残留';
  @override
  String get displacedWorktrees => '被移位的工作树';
  @override
  String get undoSurgery => '撤销手术';
  @override
  String get rolledBack => '已回滚到备份引用。';
  @override
  String get done => '完成';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$zh_Hans
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => '正在推送…';
  @override
  String get forcePushAll => '全部强制推送';
  @override
  String get confirmPush => '确认推送';
  @override
  String get cancel => '取消';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$zh_Hans
    extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get back => '返回';
  @override
  String get continueLabel => '继续';
  @override
  String get letsGo => '出发';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$zh_Hans
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get question => '它对你意味着什么？';
  @override
  String get questionEmphasis => '它';
  @override
  String get iAmPrefix => '我是 ';
  @override
  String get iAmSuffix => ' ，你的私人 Git 客户端。';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$zh_Hans
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '为 ${name} 换身行头。';
  @override
  String get themesHeader => '主题';
  @override
  String get keybindingsHeader => '快捷键';
  @override
  String get previewBadge => '预览';
  @override
  String get useDefaults => '使用默认';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$zh_Hans
    extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '让 ${name} 指向点什么。';
  @override
  String get later => '我稍后再弄';
  @override
  late final _Translations$onboarding$repo$doors$zh_Hans doors =
      _Translations$onboarding$repo$doors$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$zh_Hans cloneForm =
      _Translations$onboarding$repo$cloneForm$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$zh_Hans pickers =
      _Translations$onboarding$repo$pickers$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$repo$errors$zh_Hans errors =
      _Translations$onboarding$repo$errors$zh_Hans._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$zh_Hans
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$zh_Hans panels =
      _Translations$onboarding$preview$panels$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$zh_Hans sidebar =
      _Translations$onboarding$preview$sidebar$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$preview$changes$zh_Hans changes =
      _Translations$onboarding$preview$changes$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$preview$history$zh_Hans history =
      _Translations$onboarding$preview$history$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$preview$branches$zh_Hans branches =
      _Translations$onboarding$preview$branches$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$preview$diff$zh_Hans diff =
      _Translations$onboarding$preview$diff$zh_Hans._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$zh_Hans
    extends Translations$orrery$header$en {
  _Translations$orrery$header$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => '拖拽';
  @override
  String get modeCompare => '对比';
  @override
  String get lodModules => '模块';
  @override
  String get lodFiles => '文件';
}

// Path: orrery.status
class _Translations$orrery$status$zh_Hans
    extends Translations$orrery$status$en {
  _Translations$orrery$status$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '正在沿历史追溯manifold…';
  @override
  String get loadError => '无法读取此仓库的历史。';
  @override
  String get notEnoughHistory => '历史尚不足以绘制轨迹。';
  @override
  String get notEnoughHistoryDetail => 'Orrery 需要几个提交才能作图。';
}

// Path: orrery.legend
class _Translations$orrery$legend$zh_Hans
    extends Translations$orrery$legend$en {
  _Translations$orrery$legend$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get central => '中心';
  @override
  String get peripheral => '边缘';
}

// Path: orrery.node
class _Translations$orrery$node$zh_Hans extends Translations$orrery$node$en {
  _Translations$orrery$node$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get module => '模块';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} 个文件';
  @override
  String fileFallback({required Object id}) => '文件 #${id}';
  @override
  String nodeFallback({required Object id}) => '节点 #${id}';
  @override
  String get rootModule => '（根）';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$zh_Hans
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => '起源';
  @override
  String get now => '现在';
  @override
  String get reorganized => '已重组';
  @override
  String becameArchetype({required Object archetype}) => '成为 ${archetype}';
  @override
  String get snapshot => '快照';
}

// Path: orrery.structure
class _Translations$orrery$structure$zh_Hans
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get forming => '正在成形…';
  @override
  String get canonical => '典范';
  @override
  String get connectivity => '连通性';
  @override
  String get rigidity => '刚性';
  @override
  String get entropy => '熵';
}

// Path: orrery.rail
class _Translations$orrery$rail$zh_Hans extends Translations$orrery$rail$en {
  _Translations$orrery$rail$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => '结构';
  @override
  String get fieldLabel => '场';
  @override
  String get findingsLabel => '发现';
  @override
  String get selectedLabel => '已选';
  @override
  String get noFindings => '此历史中未检测到结构事件。';
}

// Path: orrery.selection
class _Translations$orrery$selection$zh_Hans
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => '在历史的此时点尚不存在。';
  @override
  String get roleCentral => '耦合中心 — 此处的改动会波及整个系统。';
  @override
  String get rolePeripheral => '边缘 — 松散耦合，多为自身改动。';
  @override
  String get roleMid => '中层结构 — 中度耦合。';
  @override
  String get driftOutward => ' 向外漂移 — 正在解耦。';
  @override
  String get driftInward => ' 向内漂移 — 正在融合。';
  @override
  String get driftHolding => ' 保持原位。';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$zh_Hans
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hub => '枢纽';
  @override
  String get driftOut => '向外漂移';
  @override
  String get driftIn => '向内漂移';
  @override
  String get tangle => '纠缠加剧';
  @override
  String get clarify => '趋于清晰';
  @override
  String get regime => '重组';
  @override
  String get thrash => '反复折腾';
  @override
  String get reshuffle => '重新洗牌';
  @override
  String get forecast => '预测';
}

// Path: orrery.findings
class _Translations$orrery$findings$zh_Hans
    extends Translations$orrery$findings$en {
  _Translations$orrery$findings$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      '连通性一直在下降，已接近最低点 — 若持续下去，代码库将走向分裂为两个松散耦合的部分。现在就要决定这是否是本意。';
  @override
  String get forecastConsolidate =>
      '连通性一直在攀向峰值 — 若持续下去，代码库将合并为一整块紧密耦合的团块。当心它硬化成单体。';
  @override
  String thrash({required Object name}) =>
      '${name} 反复被来回重组 — 结构上折腾很多，净位移却很少。要么厘清它的耦合，要么别再碰它。';
  @override
  String get reshuffle => '此提交看似常规，却悄然改变了哪些文件处于中心 — 整体形态未变，底下的结构却重新洗牌了。请仔细审查。';
  @override
  String hub({required Object name}) =>
      '${name} 位于结构核心 — 系统围绕它重组。把此处的改动当作高波及范围来对待。';
  @override
  String driftOut({required Object name}) =>
      '${name} 已从核心漂向边缘 — 它正在与系统解耦。要么它正被退役，要么它在悄然腐坏。';
  @override
  String driftIn({required Object name}) =>
      '${name} 已迁向核心 — 它正在成为承重结构。在更多东西依赖它之前，确保它经过充分测试。';
  @override
  String get regime => '代码库在此处急剧重组 — 其连通性发生跃变。请审查是什么分裂或合并了。';
  @override
  String get tangleTrend => '纵观历史，代码库趋向于更纠缠的结构 — 其连通性变得更密、更不模块化。';
  @override
  String get clarifyTrend => '纵观历史，代码库趋向于更清晰的结构 — 它正在分离为更清晰的模块。';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$zh_Hans
    extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get core => '核心';
  @override
  String get drift => '漂移';
  @override
  String get trend => '趋势';
  @override
  String get thrash => '折腾';
}

// Path: orrery.compare
class _Translations$orrery$compare$zh_Hans
    extends Translations$orrery$compare$en {
  _Translations$orrery$compare$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => '改动';
  @override
  String get movers => '移动者';
  @override
  String get noMovers => '这两帧之间没有文件移动。';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => '文件';
  @override
  String get deltaConnectivity => '连通性';
  @override
  String get deltaRigidity => '刚性';
  @override
  String get deltaEntropy => '熵';
  @override
  String get wayOutward => '向外';
  @override
  String get wayInward => '向内';
  @override
  String get wayShifted => '偏移';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$zh_Hans
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask: [问题]';
  @override
  String get nearHint => 'near: [文件]';
  @override
  String get whoHint => 'who: [文件]';
  @override
  String get logHint => 'log: [信息]';
  @override
  String get runHint => 'run: [工具]';
  @override
  String askLabel({required Object name, required Object body}) =>
      '询问 ${name}：${body}';
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
  }) => '${path} · ${count} 位审查者 · ${touches} 次改动';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} 次改动';
  @override
  String whoTouchesSubtitle({required Object path}) => '${path} · 无审查者记录';
}

// Path: palette.chips
class _Translations$palette$chips$zh_Hans
    extends Translations$palette$chips$en {
  _Translations$palette$chips$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

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
class _Translations$palette$predictive$zh_Hans
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% 动量';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$zh_Hans
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} 次改动 · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$zh_Hans
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => '暂存内聚度：${percent}%';
  @override
  String subtitle({required Object count}) => '${count} 个文件';
}

// Path: palette.keystone
class _Translations$palette$keystone$zh_Hans
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · 关键石 ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$zh_Hans
    extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => '${name} 中的更改';
  @override
  String history({required Object name}) => '${name} 中的历史';
  @override
  String branches({required Object name}) => '${name} 中的分支';
  @override
  String terminal({required Object name}) => '${name} 中的终端';
  @override
  String generateCommit({required Object name}) => '生成提交 · ${name}';
  @override
  String reviewChanges({required Object name}) => '审查 ${name} 中的更改';
  @override
  String muse({required Object name}) => '${name} 中的 Muse';
}

// Path: palette.desks
class _Translations$palette$desks$zh_Hans
    extends Translations$palette$desks$en {
  _Translations$palette$desks$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => '主工作树';
  @override
  String get detached => '游离';
  @override
  String dirty({required Object count}) => '${count} 个脏改动';
}

// Path: palette.actions
class _Translations$palette$actions$zh_Hans
    extends Translations$palette$actions$en {
  _Translations$palette$actions$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => '在浏览器中打开';
  @override
  String get terminal => '终端';
  @override
  String get revealInFiles => '在文件管理器中显示';
  @override
  String get copyPath => '复制路径';
  @override
  String get copyBranch => '复制分支';
}

// Path: palette.tools
class _Translations$palette$tools$zh_Hans
    extends Translations$palette$tools$en {
  _Translations$palette$tools$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => '启动 ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$zh_Hans
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => '抓取';
  @override
  String get pull => '拉取';
  @override
  String pullBehind({required Object count}) => '落后 ${count}';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => '推送';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个提交',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} 到 ${upstream}';
  @override
  String get forcePush => '强制推送';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      '无法强制推送：${branch} 未设置上游。';
  @override
  String get commit => '提交';
  @override
  String get stageAll => '全部暂存';
  @override
  String get unstageAll => '全部取消暂存';
  @override
  String get discardAll => '全部丢弃';
  @override
  String get createBranch => '创建分支';
  @override
  String get deleteBranch => '删除分支';
  @override
  String get renameBranch => '重命名分支';
  @override
  String get stash => '储藏';
  @override
  String get stashPop => '弹出储藏';
  @override
  String get stashApply => '应用储藏';
  @override
  String get stashDrop => '丢弃储藏';
  @override
  String get createTag => '创建标签';
  @override
  String get cherryPick => '拣选';
  @override
  String get revert => '还原';
  @override
  String get stashConflictMessage => '储藏应用时产生冲突。请在“更改”页面解决。';
}

// Path: palette.pr
class _Translations$palette$pr$zh_Hans extends Translations$palette$pr$en {
  _Translations$palette$pr$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get create => '创建 PR';
  @override
  String get merge => '合并 PR';
  @override
  String get markReady => '将 PR 标记为就绪';
}

// Path: palette.ai
class _Translations$palette$ai$zh_Hans extends Translations$palette$ai$en {
  _Translations$palette$ai$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => '生成提交';
  @override
  String get reviewChanges => '审查更改';
  @override
  String get runMuse => '运行 Muse';
  @override
  String debugRepo({required Object name}) => '调试 ${name}';
  @override
  String get describeSymptom => '描述一个症状';
  @override
  String viewResult({required Object kind}) => '查看 ${kind}';
  @override
  String get unseenResult => '未查看的结果';
  @override
  String runningResult({required Object kind}) => 'AI：${kind}…';
  @override
  String get running => '运行中';
  @override
  String get kindCommitMessage => '提交信息';
  @override
  String get kindCodeReview => '代码审查';
  @override
  String get kindMuseResult => 'Muse 结果';
  @override
  String get kindPresentation => '演示';
  @override
  String get kindDebugResult => '调试结果';
}

// Path: palette.undo
class _Translations$palette$undo$zh_Hans extends Translations$palette$undo$en {
  _Translations$palette$undo$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => '取消：${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$zh_Hans
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get changes => '更改';
  @override
  String get history => '历史';
  @override
  String get branches => '分支';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => '设置';
  @override
  String get refresh => '刷新';
}

// Path: palette.settings
class _Translations$palette$settings$zh_Hans
    extends Translations$palette$settings$en {
  _Translations$palette$settings$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => '减弱动效';
  @override
  String get animateLogoUnfocused => '失焦时动画 Logo';
  @override
  String get instantBlameHover => '即时 blame 悬停';
  @override
  String get autoSelectChanges => '自动选择更改';
  @override
  String get fetchOnlineIssues => '抓取在线议题';
  @override
  String get rememberWip => '记住进行中的工作';
  @override
  String get hideAiFeatures => '隐藏 AI 功能';
  @override
  String get crashReporting => '崩溃报告';
  @override
  String get aiReadOnly => 'AI 只读';
  @override
  String get stashCabinetExpanded => '储藏柜展开';
  @override
  String get fileSortInverted => '文件排序反转';
}

// Path: palette.info
class _Translations$palette$info$zh_Hans extends Translations$palette$info$en {
  _Translations$palette$info$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$zh_Hans
    extends Translations$palette$debug$en {
  _Translations$palette$debug$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => '引擎状态';
  @override
  String get engineStatusSubtitle => 'LogosGit 谱引擎诊断';
  @override
  String get fileCoupling => '文件耦合';
  @override
  String get fileCouplingSubtitle => '暂存文件最近的共变邻居';
  @override
  String get themeSpecimen => '主题样本';
  @override
  String get themeSpecimenSubtitle => '所有颜色、图标、文本层级与几何';
}

// Path: palette.dev
class _Translations$palette$dev$zh_Hans extends Translations$palette$dev$en {
  _Translations$palette$dev$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => '测试合并编辑器';
  @override
  String get testHistorySurgery => '测试历史手术';
  @override
  String get back => '返回';
  @override
  String get cancel => '取消';
  @override
  String get buildingConflicts => '正在从历史构建测试冲突…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$zh_Hans
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get label => '历史手术';
  @override
  String get subtitle => '重写历史以永久移除文件';
}

// Path: palette.orrery
class _Translations$palette$orrery$zh_Hans
    extends Translations$palette$orrery$en {
  _Translations$palette$orrery$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle => '沿manifold拖拽仓库的结构历史';
}

// Path: palette.command
class _Translations$palette$command$zh_Hans
    extends Translations$palette$command$en {
  _Translations$palette$command$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label}完成';
  @override
  String failed({required Object label, required Object message}) =>
      '${label}失败：${message}';
  @override
  String get copy => '复制';
}

// Path: palette.search
class _Translations$palette$search$zh_Hans
    extends Translations$palette$search$en {
  _Translations$palette$search$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => '搜索一切…';
  @override
  String get hintElevated => '已提升 — 全部操作';
  @override
  String get emptyTypeToSearch => '输入以搜索';
  @override
  String get emptyNoResults => '无结果';
}

// Path: palette.wick
class _Translations$palette$wick$zh_Hans extends Translations$palette$wick$en {
  _Translations$palette$wick$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => '已耦合';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$zh_Hans
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get current => '当前';
  @override
  String get staged => '已暂存';
  @override
  String get modified => '已修改';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$zh_Hans
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$zh_Hans whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$zh_Hans._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$zh_Hans
  spectralEngine = _Translations$releaseNotes$about$spectralEngine$zh_Hans._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$about$whereGoing$zh_Hans whereGoing =
      _Translations$releaseNotes$about$whereGoing$zh_Hans._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$zh_Hans
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license => 'GPL-3.0-or-later · WLCSL 社区源研究核心 · 不提供担保';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$zh_Hans
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}`（${lines}）— ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 行',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$zh_Hans
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件。',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 行（${bytes}）。',
      );
  @override
  String roles({required Object parts}) => '角色 — ${parts}。';
  @override
  String showingNofM({required Object total, required Object active}) =>
      '正在显示 ${total} 个文件中的 ${active} 个，按结构中心性排序。';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$zh_Hans
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => '一览';
  @override
  String get core => '核心';
  @override
  String get gettingStarted => '入门';
  @override
  String get regions => '区域';
  @override
  String get shape => '形态';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$zh_Hans
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) => '一个没有可读文本文件的仓库${detail}。';
  @override
  String emptyBinary({required Object n}) => '${n} 个二进制';
  @override
  String emptyUnreadable({required Object n}) => '${n} 个不可读';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '一个包含 ${n} 个活跃文件的仓库。',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '一个包含 ${n} 个活跃文件的仓库 — ${regions}。',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$zh_Hans
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => '全部位于 `${dir}` 下。';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个核心',
      );
  @override
  String get bodyCoreSeparator => '、';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个文件',
      );
  @override
  String connectsTo({required Object linked}) => '连接到：${linked}。';
  @override
  String get filesLabel => '文件：';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$zh_Hans
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get bulk => '密集互联的代码库：多数文件参与同一个大型共变邻域。';
  @override
  String get crystalline => '晶格状代码库：文件间耦合均匀规整，局部结构可预测。';
  @override
  String get goe => '高度互联的代码库：耦合遍布各文件，无主导脊柱。';
  @override
  String get modular => '模块化代码库：若干内聚区域，跨耦合有限。在一个区域内工作很少扰动另一个。';
  @override
  String get poisson => '松散耦合的代码库：文件大多各自演进，偶有共变。';
  @override
  String get tree => '树状代码库：一条主导脊柱带着依附分支。改动通常从核心向外传播。';
}

// Path: settings.language
class _Translations$settings$language$zh_Hans
    extends Translations$settings$language$en {
  _Translations$settings$language$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '语言';
  @override
  String get summary => '此应用的界面语言。Git 输出、日志和诊断信息保持英文，以便错误报告可搜索。';
  @override
  String get label => '显示语言';
  @override
  String get systemDefault => '系统默认';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      '跟随你的操作系统语言（${resolved}）';
  @override
  String get disclosureSource => '源语言，由开发者撰写。';
  @override
  String disclosureAi({required Object model}) =>
      '由 ${model} 机器翻译，尚未经人工审校。欢迎指正。';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => '由 ${model} 机器翻译，已人工审校 ${percent}%。';
  @override
  String get disclosureHuman => '人工翻译，由社区维护。';
  @override
  String reviewedBy({required Object names}) => '由 ${names} 审校。';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$zh_Hans
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => '偏好';
  @override
  String get shortcuts => '快捷键';
  @override
  String get behaviour => '行为';
  @override
  String get aiProviders => 'AI 提供方';
  @override
  String get modelSlots => '模型槽位';
  @override
  String get tools => '工具';
  @override
  String get diagnostics => '诊断';
  @override
  String get offenders => '问题项';
  @override
  String get release => '发布';
}

// Path: settings.errors
class _Translations$settings$errors$zh_Hans
    extends Translations$settings$errors$en {
  _Translations$settings$errors$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => '保存护栏配置失败。';
  @override
  String get saveRetentionPolicy => '保存保留策略失败。';
  @override
  String get saveUpdateChannel => '保存更新通道失败。';
  @override
  String get saveModelSelection => '保存 AI 模型选择失败。';
  @override
  String get saveModelAlias => '保存模型别名失败。';
  @override
  String get saveCommitMessageModelSlot => '保存提交信息模型槽位失败。';
  @override
  String get saveReviewModelSlot => '保存审查模型槽位失败。';
  @override
  String get saveCommitMessageCustomPrompt => '保存提交信息自定义提示词失败。';
  @override
  String get saveReviewGuide => '保存审查指引失败。';
  @override
  String get saveMuseNotes => '保存 muse 备注失败。';
  @override
  String get saveReviewDoubleCheck => '保存审查复核模式失败。';
  @override
  String get saveApiPiggybackCli => '保存 API 搭载 CLI 失败。';
  @override
  String get saveCliTimeout => '保存 CLI 超时时长失败。';
  @override
  String get stopAllCli => '无法停止正在运行的 CLI 会话。';
  @override
  String clearLocalData({required Object error}) => '无法清除本地数据：${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$zh_Hans
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get editing => '编辑中';
  @override
  String get saving => '保存中';
  @override
  String get saveFailed => '保存失败';
}

// Path: settings.clearData
class _Translations$settings$clearData$zh_Hans
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => '清除本地数据';
  @override
  String get clear => '清除';
  @override
  String get confirmDiagnostics => '清除本地诊断样本和性能计时？';
  @override
  String get confirmAudit => '清除本地 AI 审计元数据记录？';
  @override
  String get confirmAll => '清除所有本地诊断样本和 AI 审计元数据记录？';
  @override
  String get confirmWipeAll =>
      '抹除所有本地应用数据 — 包括最近仓库列表 — 并退出？磁盘上你实际的 git 仓库不会被触及。';
  @override
  String get confirmReset =>
      '重置本地应用数据并退出？\n\n设置、主题、引导、AI 偏好、遥测和 engram 缓存都会被清除。你的最近仓库列表将保留。';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$zh_Hans
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '宽松';
  @override
  String get balanced => '均衡';
  @override
  String get strict => '严格';
  @override
  String get paranoid => '偏执';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$zh_Hans
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '护栏';
  @override
  String get summary => '整个体验中自动化的专注程度。';
}

// Path: settings.appearance
class _Translations$settings$appearance$zh_Hans
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '外观';
  @override
  String get summary => '全局界面氛围与气质。';
}

// Path: settings.retention
class _Translations$settings$retention$zh_Hans
    extends Translations$settings$retention$en {
  _Translations$settings$retention$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '本地数据保留';
  @override
  String get summaryDiagnostics => '诊断保留策略。';
  @override
  String get summaryWithAudit => '诊断和 AI 审计保留策略。';
  @override
  String get unitDays => '天';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote => '包括诊断、性能计时和元数据。';
}

// Path: settings.navigation
class _Translations$settings$navigation$zh_Hans
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '导航与动态';
  @override
  String get summaryShortcuts => '快捷键与界面行为。';
  @override
  String get summaryWithAi => '快捷键、界面行为和 AI 路由。';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$zh_Hans
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '行为动态';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$zh_Hans
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get diag => '诊断';
  @override
  String get audit => '审计';
  @override
  String get all => '全部';
  @override
  String get clearsHint => '<-- 清除';
}

// Path: settings.channels
class _Translations$settings$channels$zh_Hans
    extends Translations$settings$channels$en {
  _Translations$settings$channels$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get stable => '稳定版';
  @override
  String get beta => '测试版';
  @override
  String get dev => '开发版';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$zh_Hans
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => '已是最新';
  @override
  String updateAvailable({required Object version}) => '有可用更新 ${version}';
  @override
  String get notConfigured => '无更新服务器';
  @override
  String notFound({required Object channel}) => '无 ${channel} 版本';
  @override
  String get unreachable => '无法访问';
  @override
  String get badManifest => '清单错误';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$zh_Hans
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get label => '快捷键配置';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => '数字';
  @override
  String get porcelainDescription => '组合键快捷方式（先按 G，再按 C、H、B…）。';
  @override
  String get numericDescription => '单个数字键快捷方式（1、2、3…）。';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$zh_Hans
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'api 密钥';
  @override
  String get endpointHint => '端点';
  @override
  String get test => '测试';
  @override
  String get hide => '隐藏';
  @override
  String get show => '显示';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$zh_Hans
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => '导航';
  @override
  String get staging => '暂存';
  @override
  String get branchesPrs => '分支与 PR';
  @override
  String get modifiers => '修饰键';
  @override
  String get changes => '更改';
  @override
  String get history => '历史';
  @override
  String get branches => '分支';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => '切换（始终）';
  @override
  String get search => '搜索';
  @override
  String get dismiss => '关闭';
  @override
  String get refresh => '刷新';
  @override
  String get shortcuts => '快捷键';
  @override
  String get nextChange => '下一处改动';
  @override
  String get prevChange => '上一处改动';
  @override
  String get toggleLine => '切换行';
  @override
  String get toggleHunk => '切换 hunk';
  @override
  String get toggleFile => '切换文件';
  @override
  String get pinContext => '固定上下文';
  @override
  String get commit => '提交';
  @override
  String get acceptHint => '采纳提示';
  @override
  String get undo => '撤销';
  @override
  String get navigateRow => '导航';
  @override
  String get expand => '展开';
  @override
  String get checkout => '检出';
  @override
  String get approve => '批准';
  @override
  String get requestChanges => '请求修改';
  @override
  String get selectRange => '选择范围';
  @override
  String get extendedMenu => '扩展菜单';
}

// Path: settings.toggles
class _Translations$settings$toggles$zh_Hans
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'AI 只读模式';
  @override
  String get aiReadOnlyDescription => '阻止 AI 自动写入或暂存改动。';
  @override
  String get logoMotionLabel => '切出标签页时 Logo 仍动画';
  @override
  String get logoMotionDescriptionEnabled => '它被设计得很高效，别伤它的心';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => '记住进行中的工作';
  @override
  String get rememberWipDescription => '在会话之间保留你的提交草稿和文件选择。';
  @override
  String get stashCabinetLabel => '储藏柜默认展开';
  @override
  String get stashCabinetDescription => '当仓库有搁架时，默认展开档案柜抽屉。';
  @override
  String get instantBlameLabel => '即时 blame 悬停';
  @override
  String get instantBlameDescription => '跳过在差异行上显示 blame 信息前的 180ms 延迟。';
  @override
  String get autoSelectLabel => '自动选择新改动';
  @override
  String get autoSelectDescription => '新跟踪或改动的文件会自动加入提交选择。';
  @override
  String get changeIdLabel => '写入 change-id 头';
  @override
  String get changeIdDescription =>
      '为新提交添加 change-id 标识头（Jujutsu、GitButler 与 Gerrit 的约定）。每个提交在落地后会被重写一次。';
  @override
  String get fetchIssuesLabel => '加载分支时抓取在线议题';
  @override
  String get fetchIssuesDescription => '打开分支页面时在后台从你的 git 提供方拉取 PR 和议题详情。';
  @override
  String get hateAiLabel => '我讨厌 AI';
  @override
  String get hateAiDescription => '放逐所有 LLM 驱动的功能。Logos 会继续运行，因为它只是谱数学。';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$zh_Hans
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '差异可差异性';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$zh_Hans
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => '正在加载提供方…';
  @override
  String get refreshingProviders => '正在刷新提供方诊断…';
  @override
  String get routeDescription => '重命名配置并将其路由到任意检测到的提供方模型。';
  @override
  String get loadingCategories => '正在加载模型类别…';
  @override
  String get noOptions => '尚无可用的模型选项。请先检测一个兼容的本地 AI CLI。';
  @override
  String get slotsAppearWhenAvailable => '一旦提供方模型可用，模型槽位设置就会出现在这里。';
  @override
  String get effortDefault => '默认';
  @override
  String get noModelsForSlot => '未为此槽位检测到模型。';
  @override
  String viaProvider({required Object provider}) => '经由 ${provider}';
  @override
  String get customModelId => '自定义模型 id';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$zh_Hans
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) => '没有模型匹配“${query}”';
  @override
  String get noModels => '无可用模型';
  @override
  String get filterHint => '筛选模型…';
  @override
  String get warming => '预热中…';
  @override
  String get detailsUnavailable => '详情不可用';
  @override
  String get free => '免费';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$zh_Hans
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription => '依据你的结构、语气和覆盖偏好，从暂存改动起草提交信息。';
  @override
  String get reviewDescription => '在提交前审查当前提交范围。';
  @override
  String get museDescription => '三阶段神谕，先头脑风暴，再为差异综合出一个前进方向。';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$zh_Hans
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => '风格指南';
  @override
  String get styleGuideHint => '可选。语气 / 语调 / 禁忌。上面的格式负责骨架。';
}

// Path: settings.review
class _Translations$settings$review$zh_Hans
    extends Translations$settings$review$en {
  _Translations$settings$review$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => '审查时一并参考的附加备注';
  @override
  String get doubleCheckLabel => '复核审查';
  @override
  String get doubleCheckDescription => '在显示最终报告前运行第二遍验证。';
}

// Path: settings.museHint
class _Translations$settings$museHint$zh_Hans
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '有什么想温和引导的？今天心情不错。';
  @override
  String get balanced => '该着墨什么，该略过什么。诚实，但不刻薄。';
  @override
  String get strict => '标准。禁忌。muse 不会放过的东西。';
  @override
  String get paranoid => '调校透镜。manifold该以什么频率共鸣？';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$zh_Hans
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => '给 muse 的附加备注';
}

// Path: settings.museStage
class _Translations$settings$museStage$zh_Hans
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => '头脑风暴';
  @override
  String get synthesize => '综合';
  @override
  String get slot => '槽位';
  @override
  String get ideaCountLoose => '约 12 个想法';
  @override
  String get ideaCountBalanced => '约 16 个想法';
  @override
  String get ideaCountStrict => '约 20 个想法';
  @override
  String get ideaCountParanoid => '约 24 个想法';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  护栏：${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$zh_Hans
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get folder => '文件夹';
  @override
  String get history => '历史';
  @override
  String get far => '远';
  @override
  String get near => '近';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$zh_Hans
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => '模块地图';
  @override
  String get repoCenters => '仓库中心';
  @override
  String get neighbors => '邻居';
  @override
  String get toTouch => '接下来该动什么';
  @override
  String get relevanceEngine => '相关性引擎';
  @override
  String get description => '读取文件如何跨结构、历史和节奏一同移动，从而让 Manifold 知道什么重要，而不只是什么改了。';
  @override
  String get withinReach => '触手可及';
  @override
  String get gate => '门';
  @override
  String get nearest => '最近';
  @override
  String get warming => '预热中';
  @override
  String get emptyOpenRepo => '打开一个仓库\n即可实时看到透镜';
  @override
  String get emptyNoFiles => '触及范围内\n无文件 — 向\n历史方向拖动';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$zh_Hans
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '更改排序指南';
  @override
  String get related => '一同改动的文件聚在一起。关注点在前，上下文随后。';
  @override
  String get relatedInverted => '孤立的改动在前。紧密耦合的簇沉到底部。';
  @override
  String get alphabetical => '按路径 A → Z 排列。不区分大小写，数字按自然顺序。';
  @override
  String get alphabeticalInverted => '按路径 Z → A 排列。不区分大小写，数字按自然顺序。';
  @override
  String get impact => '改动最重的浮到最前。变动量加权；二进制和新文件会被提升。';
  @override
  String get impactInverted => '改动最轻的浮到最前。速战速决在上，重活稍等。';
  @override
  String get nearRelated => '近相关';
  @override
  String get alphabeticalShort => '字母顺序';
  @override
  String get byImpact => '按影响';
  @override
  String get flipped => '已翻转';
  @override
  String get peek => '窥看';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$zh_Hans
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API 模型使用';
  @override
  String get codexNotDetected => '未检测到 codex';
  @override
  String get dormant => '休眠';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$zh_Hans
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => '查看器';
  @override
  String get media => '媒体';
  @override
  String get binary => '二进制';
  @override
  String get hidden => '隐藏';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$zh_Hans
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => '破坏性操作';
  @override
  String get discards => '丢弃';
  @override
  String get commits => '提交';
  @override
  String get commitPush => '提交 + 推送';
  @override
  String get all => '全部';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$zh_Hans
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get label => '撤销窗口';
  @override
  String get off => '关';
  @override
  String descriptionInstant({required Object scope}) => '${scope}立即定稿。';
  @override
  String descriptionDelayed({required Object scope, required Object seconds}) =>
      '${scope}定稿前有 ${seconds}s。';
  @override
  String get cycleScopeTooltip => '点击以循环切换范围 · 也可在滑块上上下拖动';
  @override
  String get resetTooltip => '重置每个操作以使用默认窗口';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$zh_Hans
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => '“大概没问题”就是没问题';
  @override
  String get proper => '认真读一遍：逻辑、集成、模式';
  @override
  String get lookAgain => '再看一遍。也许有东西藏着';
  @override
  String get assumeWrong => '假定有问题。把它找出来';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$zh_Hans
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh => '例如：聚焦高层逻辑和重大 bug。简明而宽容。';
  @override
  String get surfaceBugs => '例如：浮现潜在 bug、架构不一致和边界情况失败。';
  @override
  String get scrutinize => '例如：逐行审视优化、安全和模式合规。';
  @override
  String get trustNothing => '例如：不信任何东西。质疑每个副作用。把每一行都当作潜在故障。';
  @override
  String get optional => '关于审查该关注什么的可选指引。';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$zh_Hans
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '格式';
  @override
  String get peek => '窥看';
  @override
  String get structure => '结构';
  @override
  String get voice => '语气';
  @override
  String get coverage => '覆盖';
  @override
  String get structureTitleBody => '标题 + 正文';
  @override
  String get structureTitleOnly => '仅标题';
  @override
  String get structureFreeform => '自由形式';
  @override
  String get voiceVerbLed => '行动导向';
  @override
  String get voiceDescriptive => '描述性';
  @override
  String get voiceNarrative => '叙述性';
  @override
  String get coverageEssentials => '要点';
  @override
  String get coverageBalanced => '均衡';
  @override
  String get coverageEverything => '面面俱到';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$zh_Hans
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$zh_Hans title =
      _Translations$settings$commitPreview$title$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$base$zh_Hans base =
      _Translations$settings$commitPreview$base$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$zh_Hans
  balancedSuffix =
      _Translations$settings$commitPreview$balancedSuffix$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$zh_Hans
  everythingSuffix =
      _Translations$settings$commitPreview$everythingSuffix$zh_Hans._(_root);
}

// Path: settings.externalTools
class _Translations$settings$externalTools$zh_Hans
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '外部工具';
  @override
  String get summary => '右键点击侧栏中的项目，用其中之一打开它。参数用 {path} 表示项目文件夹。';
  @override
  String get detecting => '正在检测已安装的工具…';
  @override
  String get allPresetsAdded => '所有已知预设都已添加。用“+ 自定义”添加更多。';
  @override
  String get noToolsConfigured => '尚未配置工具。在上方添加一个。';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => '编辑器';
  @override
  String get categoryExplore => '浏览';
  @override
  String get categoryOps => '运维';
  @override
  String get categoryGitOps => 'git 运维';
  @override
  String get nameHint => '名称';
  @override
  String get commandHint => '命令';
  @override
  String get test => '测试';
  @override
  String get removeTool => '移除工具';
  @override
  String get modeTerminal => '终端';
  @override
  String get modeDetached => '分离';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$zh_Hans
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '本月 ${used}${limit}';
}

// Path: settings.gitea
class _Translations$settings$gitea$zh_Hans
    extends Translations$settings$gitea$en {
  _Translations$settings$gitea$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gitea 令牌';
  @override
  String get hostHint => '主机';
  @override
  String get tokenHint => '令牌';
  @override
  String get save => '保存';
}

// Path: settings.wick
class _Translations$settings$wick$zh_Hans
    extends Translations$settings$wick$en {
  _Translations$settings$wick$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => '选择 wick 可执行文件';
  @override
  String get connected => 'wick · 已连接';
  @override
  String get pathToExecutable => 'wick · 可执行文件路径';
  @override
  String get off => '关';
  @override
  String get disableHint => '关闭 wick 集成';
  @override
  String get enableHint => '开启 wick 集成';
}

// Path: settings.integrations
class _Translations$settings$integrations$zh_Hans
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& 集成';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => '计划中';
  @override
  String get lspComingSoon => 'lsp · 即将推出';
  @override
  String get alphaMathConnected => 'alpha-math · 已连接';
  @override
  String get alphaMathComingSoon => 'alpha-math · 即将推出';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$zh_Hans
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get label => '减弱动效';
  @override
  String get subtitleStill => '静止…如冰？';
  @override
  String get subtitleFlow => '流动如水。';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$zh_Hans
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => '重置并退出';
  @override
  String get keepRepos => '保留仓库';
  @override
  String get wipeAll => '全部抹除';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$zh_Hans
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => '命令诊断';
  @override
  String get networkFlowTelemetry => '网络流遥测';
  @override
  String get clearSamples => '清除样本';
  @override
  String get clearMetrics => '清除指标';
  @override
  String get clearTimings => '清除计时';
  @override
  String get recalibrate => '重新校准';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings => '尚未捕获命令计时。运行常规操作以填充诊断。';
  @override
  String get noBackendSamples => '尚未捕获后端命令样本。运行 git 和设置操作以填充此日志。';
  @override
  String get noDiffSessions => '尚未捕获差异渲染会话。打开并滚动文件差异以填充此面板。';
  @override
  String get noUiSessions => '尚未捕获 UI 计时会话。打开面板并导航路由以填充此面板。';
  @override
  String get recentOperations => '近期操作';
  @override
  String get recentBackendOperations => '近期后端操作';
  @override
  String get recentDiffSessions => '近期差异会话';
  @override
  String get recentUiTimings => '近期 UI 计时';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个唯一命令',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个作用域命令',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个已插桩事件',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | 卡顿 ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => ['命令', 'p50', '可靠性', '范围'];
  @override
  List<String> get headersBackend => ['作用域', 'p50', 'p95', '失败'];
  @override
  List<String> get headersDiff => ['渲染器', '首次绘制', '帧 p95', '光栅 p95', '卡顿'];
  @override
  List<String> get headersUi => ['事件', 'p50', '失败', '范围'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$zh_Hans
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个样本',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个命令',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个会话',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个事件',
      );
  @override
  String stability({required Object pct}) => '${pct}% 稳定性';
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
class _Translations$settings$flowEngine$zh_Hans
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => '执行流';
  @override
  String get description => '在代码上模拟振子。在脆弱的执行路径结晶为 bug 之前把它们浮现出来。';
  @override
  String get idle => '闲置';
  @override
  String get emptyOpenRepo => '打开一个仓库\n即可看到流分析';
  @override
  String get scanning => '正在扫描';
  @override
  String get analysing => '正在分析\n透镜中的文件…';
  @override
  String get fragility => '脆弱性';
  @override
  String get findings => '发现';
  @override
  String get gap => '间隙';
  @override
  String get clean => '干净';
  @override
  String get severity => '严重度';
  @override
  String get critical => '严重';
  @override
  String get warn => '警告';
  @override
  String get info => '信息';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$zh_Hans
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get spark => '灵感火花 · 眼下就该走的下一步';
  @override
  String get current => '水中的暗流 · 现在时的延伸';
  @override
  String get horizon => '眺望地平线 · 触及远方的方向';
  @override
  String get fever => '从高烧的梦中醒来 · 挑衅';
  @override
  String get echo => '峡谷间的回响 · 别处的类比';
  @override
  String get vertigo => '崖边的眩晕 · 相邻的风险';
  @override
  String get ghost => '旧日的幽灵 · 历史上下文';
  @override
  String get mirror => '静水上的镜面 · 倒置';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$zh_Hans
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'CLI 搭载';
  @override
  String get clearCacheLabel => '清除缓存';
  @override
  String get clearCacheTooltip => '抹除缓存的模型并重新探测。清掉提供方已下线的那些。';
  @override
  String get refreshLabel => '刷新提供方';
  @override
  String get refreshTooltip => '立即重新探测每个提供方。';
  @override
  String get body => '把界面消息直接管道给本地提供方二进制文件。';
  @override
  String get cliTimeoutLabel => '单次运行超时';
  @override
  String get cliTimeoutUnitMinutes => '分钟';
  @override
  String get cliTimeoutUnitMinute => '分钟';
  @override
  String get forceStopLabel => '停止所有会话';
  @override
  String get forceStopTooltip => '强制终止所有正在进行的 CLI 运行。';
  @override
  String get forceStopConfirmTitle => '停止正在运行的 CLI 会话？';
  @override
  String forceStopConfirmBody({required Object count}) =>
      '这将强制终止 ${count} 个正在进行的 CLI 运行。其输出将丢失。';
  @override
  String get forceStopConfirmAction => '全部停止';
  @override
  String get forceStopNoneRunning => '没有正在运行的 CLI 会话';
  @override
  String get forceStopRecordError => '已停止：CLI 会话已被强制终止。';
}

// Path: settings.header
class _Translations$settings$header$zh_Hans
    extends Translations$settings$header$en {
  _Translations$settings$header$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '工作区偏好';
  @override
  String get subtitle => '为整个工作区配置全局美学、界面动态和核心操作保障。';
  @override
  String get releaseNotesTooltip => '发布说明';
  @override
  String get replayOnboardingTooltip => '重放引导';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$zh_Hans
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '性能诊断';
  @override
  String get copyTrace => '复制轨迹';
  @override
  String get offenderRanking => '问题项排名';
  @override
  String get offenderRankingSubtitle => '各数据流中的延迟推手。';
  @override
  String get noOffenders => '尚无问题项排名。捕获诊断活动以填充此列表。';
}

// Path: settings.release
class _Translations$settings$release$zh_Hans
    extends Translations$settings$release$en {
  _Translations$settings$release$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '发布部署';
  @override
  String get summary => '更新相关设置。';
  @override
  String get deploymentChannel => '部署通道';
  @override
  String get captureCrashDiagnostics => '捕获崩溃诊断';
  @override
  String get comingSoon => '即将推出。';
  @override
  String get checking => '检查中…';
  @override
  String get pollForUpdates => '检查更新';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$zh_Hans
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => '检测中…';
  @override
  String get ready => '就绪';
  @override
  String get notDetected => '未检测到';
  @override
  String configured({required Object count}) => '已配置 ${count} 个';
  @override
  String get notConfigured => '未配置';
  @override
  String get cliManaged => 'CLI 托管';
  @override
  String get connected => '已连接';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个模型',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个提供方',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$zh_Hans
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get am => '上午';
  @override
  String get pm => '下午';
}

// Path: settings.offenders
class _Translations$settings$offenders$zh_Hans
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => '命令';
  @override
  String get diffStream => '差异渲染';
  @override
  String get uiStream => 'UI 计时';
  @override
  String rendererName({required Object mode}) => '${mode} 渲染器';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% 失败';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% 卡顿 | ${frame}ms 帧 p95';
  @override
  String inStream({required Object stream}) => '在 ${stream} 中';
}

// Path: sync.actions
class _Translations$sync$actions$zh_Hans extends Translations$sync$actions$en {
  _Translations$sync$actions$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => '同步';
  @override
  String get syncOpenRepoDetail => '打开一个仓库以管理推送与拉取操作。';
  @override
  String get detachedHeadLabel => '游离 HEAD';
  @override
  String get detachedHeadDetail => '推送或拉取前请先检出一个分支。';
  @override
  String get publishBranchLabel => '发布分支';
  @override
  String publishBranchDetail({required Object branch}) =>
      '推送 ${branch} 并设置其上游跟踪分支。';
  @override
  String get publishButtonLabel => '发布';
  @override
  String get syncBranchLabel => '同步分支';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => '以变基方式拉取 ${behindCount}，然后推送 ${aheadCount}。';
  @override
  String get syncBranchButtonLabel => '拉取（变基）后推送';
  @override
  String get pushBranchLabel => '推送分支';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      '推送 ${count} 到 ${upstream}。';
  @override
  String get pushBranchButtonLabel => '推送提交';
  @override
  String get pullUpdatesLabel => '拉取更新';
  @override
  String pullUpdatesDetail({required Object upstream, required Object count}) =>
      '从 ${upstream} 拉取 ${count}。';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      '从 ${upstream} 抓取并刷新上游状态。';
}

// Path: sync.panel
class _Translations$sync$panel$zh_Hans extends Translations$sync$panel$en {
  _Translations$sync$panel$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => '正在加载远程状态';
  @override
  String get loadingMessage => '正在检查分支跟踪信息。';
  @override
  String get remoteStatusUnavailable => '远程状态不可用';
  @override
  String get noUpstream => '无上游';
  @override
  String get aheadLabel => '领先';
  @override
  String get behindLabel => '落后';
  @override
  String get treeLabel => '树';
  @override
  String get runningSync => '正在同步…';
  @override
  String get fetching => '正在抓取…';
  @override
  String get fetchOnly => '仅抓取';
  @override
  String get syncFailed => '同步失败';
  @override
  String get forcePushRecoveryLabel => '强制推送（带 lease）';
  @override
  String get conflictsToResolveTitle => '待解决的冲突';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} 个需要解决：${list}';
  @override
  String get resolveConflicts => '解决冲突';
  @override
  String get workingEllipsis => '处理中…';
  @override
  String lastActivity({required Object operation}) => '最近活动：${operation}';
  @override
  String get noOutput => '无输出。';
  @override
  String resolvedConflicts({required Object count}) => '已解决 ${count} 个。';
  @override
  String get cancelledUnchanged => '已取消，工作区未改动。';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) => '${count} 个文件有未提交的改动，请先提交后再变基同步（${list}）。';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      '无法强制推送：“${branch}”未配置上游。';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$zh_Hans
    extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => '强制推送（带 lease）？';
  @override
  String target({required Object remote, required Object branch}) =>
      '目标：${remote}/${branch}';
  @override
  String get warning =>
      '这会用你的本地历史重写远程分支。带 lease 会在你上次抓取后有人推送到远程时中止，但已抓取的改动仍会被覆盖。仅在你有意进行了使分支分叉的变基或修订时才使用。';
  @override
  String get confirmButton => '强制推送';
}

// Path: xray.board
class _Translations$xray$board$zh_Hans extends Translations$xray$board$en {
  _Translations$xray$board$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => '与另一个模块一同改动';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 位审查者',
      );
  @override
  String get territory => '领地';
  @override
  String get unreviewed => '未审查';
}

// Path: xray.cadence
class _Translations$xray$cadence$zh_Hans extends Translations$xray$cadence$en {
  _Translations$xray$cadence$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} 个提交 · ${days} 天\n${lines}';
  @override
  String burstTooltipSingle({required Object label, required Object n}) =>
      '${label} 有 ${n} 个提交';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      '${n} 天间隔 · ${label}';
  @override
  String reflogTooltip({required Object label, required Object n}) =>
      '${label} 有 ${n} 个 reflog 事件';
}

// Path: xray.cards
class _Translations$xray$cards$zh_Hans extends Translations$xray$cards$en {
  _Translations$xray$cards$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$zh_Hans branchModel =
      _Translations$xray$cards$branchModel$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$bursty$zh_Hans bursty =
      _Translations$xray$cards$bursty$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$zh_Hans hiddenRefs =
      _Translations$xray$cards$hiddenRefs$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$keystone$zh_Hans keystone =
      _Translations$xray$cards$keystone$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$zh_Hans machineHistory =
      _Translations$xray$cards$machineHistory$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$migration$zh_Hans migration =
      _Translations$xray$cards$migration$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$zh_Hans narrowHotspot =
      _Translations$xray$cards$narrowHotspot$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$noTags$zh_Hans noTags =
      _Translations$xray$cards$noTags$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$reflog$zh_Hans reflog =
      _Translations$xray$cards$reflog$zh_Hans._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$zh_Hans singleOwner =
      _Translations$xray$cards$singleOwner$zh_Hans._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$zh_Hans
    extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get branches => '分支';
  @override
  String get bursty => '爆发';
  @override
  String get hiddenRefs => '隐藏引用';
  @override
  String get machineHeavy => '机器主导';
  @override
  String get migration => '迁移';
  @override
  String get narrowHotspot => '狭窄热点';
  @override
  String get noTags => '无标签';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => '单一所有者';
}

// Path: xray.grain
class _Translations$xray$grain$zh_Hans extends Translations$xray$grain$en {
  _Translations$xray$grain$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => '最粗 — 顶层模块';
  @override
  String get finest => '最细粒度';
  @override
  String get mid => '中等粒度';
  @override
  String get oneCharacteristic => '一个特征尺度';
}

// Path: xray.header
class _Translations$xray$header$zh_Hans extends Translations$xray$header$en {
  _Translations$xray$header$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => '脏';
  @override
  String get machineChip => '机器';
  @override
  String get refresh => '刷新';
  @override
  String get refreshing => '正在刷新…';
  @override
  String get title => '仓库 X-Ray';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$zh_Hans extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => '簇内同伴';
  @override
  String get coChangers => '共变者';
  @override
  String get keystone => '关键石';
  @override
  String keystoneScore({required Object score}) => '关键石  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$zh_Hans
    extends Translations$xray$inspector$en {
  _Translations$xray$inspector$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => '分支';
  @override
  String commitsHumanMachine({required Object n}) => '人工 · ${n} 机器';
  @override
  String get commitsLabel => '提交';
  @override
  String get confidenceLabel => '置信度';
  @override
  String get curlLabel => '旋度';
  @override
  String get engineSection => '引擎';
  @override
  String get gradientLabel => '梯度';
  @override
  String get harmonicLabel => '谐波';
  @override
  String get headLabel => '头';
  @override
  String get hiddenRefsLabel => '隐藏引用';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 次合并',
      );
  @override
  String get noTags => '无标签';
  @override
  String get notesLabel => '注释';
  @override
  String get openCommit => '打开提交';
  @override
  String get pathLabel => '路径';
  @override
  String remoteCount({required Object n}) => '${n} 个远程';
  @override
  String get renamesLabel => '重命名';
  @override
  String scannedAt({required Object time}) => '扫描于 ${time}';
  @override
  String selectedCount({required Object n}) => '已选 ${n} 个';
  @override
  String get shapeLinear => '线性';
  @override
  String get shapeMergeHeavy => '合并密集';
  @override
  String get shapeMostlyLinear => '基本线性';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个储藏',
      );
  @override
  String get stressLabel => '应力';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个标签',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个工作树',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$zh_Hans
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage => '正在探查 Git 历史、引用、节奏和热点。';
  @override
  String get buildingTitle => '正在构建仓库 X-Ray';
  @override
  String get idleMessage => '再次打开面板以探查当前仓库。';
  @override
  String get idleTitle => '仓库 X-Ray';
  @override
  String get unavailableTitle => '仓库 X-Ray 不可用';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$zh_Hans
    extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => '${n} 天半衰期';
}

// Path: xray.multi
class _Translations$xray$multi$zh_Hans extends Translations$xray$multi$en {
  _Translations$xray$multi$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个簇',
      );
  @override
  String clusterSingle({required Object id}) => '簇 ${id}';
  @override
  String couplingSuffix({required Object parts}) => '${parts} 耦合';
  @override
  String externalCount({required Object n}) => '${n} 个外部';
  @override
  String mutualCount({required Object n}) => '${n} 个互相';
}

// Path: xray.recency
class _Translations$xray$recency$zh_Hans extends Translations$xray$recency$en {
  _Translations$xray$recency$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n} 天';
  @override
  String months({required Object n}) => '${n} 月';
  @override
  String get today => '今天';
  @override
  String weeks({required Object n}) => '${n} 周';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        one: '${n} 年',
        other: '${n} 年',
      );
}

// Path: xray.rings
class _Translations$xray$rings$zh_Hans extends Translations$xray$rings$en {
  _Translations$xray$rings$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => '一个混合结构';
  @override
  String get hintSelfSimilar => '自相似';
  @override
  String get oneBlendedBody => '一个混合结构 — 尚无可分离的模块尺度解析出来。';
  @override
  String get overHistory => '纵观历史';
  @override
  String get parts => '部分';
  @override
  String get readingHint => '正在读取结构…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个尺度',
      );
  @override
  String get scaleDissolved => '一个结构尺度消融了';
  @override
  String get scaleEmerged => '一个结构尺度浮现了';
  @override
  String get scaleSpectrum => '尺度谱';
  @override
  String get selfSimilarBody => '自相似 — 结构跨尺度重复，无单一特征层级。';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '历史中 ${n} 次转变',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 次结构转变',
      );
  @override
  String get title => '生长环';
  @override
  String get unavailable => '不可用';
}

// Path: xray.stats
class _Translations$xray$stats$zh_Hans extends Translations$xray$stats$en {
  _Translations$xray$stats$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get alive => '存活';
  @override
  String get files => '文件';
  @override
  String get lastTouched => '上次改动';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '所有者',
      );
  @override
  String get touches => '改动次数';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$zh_Hans
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get current => '当前';
  @override
  String get legacy => '遗留';
  @override
  String get zone => '仓库区';
}

// Path: xray.summary
class _Translations$xray$summary$zh_Hans extends Translations$xray$summary$en {
  _Translations$xray$summary$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) => '分析失败：${error}';
  @override
  String get analyze => '分析';
  @override
  String get copied => '摘要已复制到剪贴板。';
  @override
  String get directionHint => '方向';
  @override
  String get download => '下载';
  @override
  String get emptyState => '运行 Logos 分析以描绘此仓库的结构与区域。\n(tw: 现在还有点糙)';
  @override
  String get exit => '退出';
  @override
  String get generating => '正在读取仓库并聚类特征…';
  @override
  String get noModel => '未配置 AI 模型。';
  @override
  String get noModelConfigured => '未配置 AI 模型';
  @override
  String presentWith({required Object label}) => '用 ${label} 演示';
  @override
  String presentingWith({required Object label}) => '正在用 ${label} 演示…';
  @override
  String get reanalyze => '重新分析';
  @override
  String get saveDialogTitle => '保存仓库摘要';
  @override
  String saveFailed({required Object error}) => '保存失败：${error}';
  @override
  String get savePresentationDialogTitle => '保存演示';
  @override
  String savedTo({required Object path}) => '已保存到 ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$zh_Hans extends Translations$xray$tabs$en {
  _Translations$xray$tabs$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get map => '地图';
  @override
  String get signals => '信号';
  @override
  String get summary => '摘要';
  @override
  String get time => '时间';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$zh_Hans
    extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => '连通性';
  @override
  String events({required Object n}) => '${n} 个事件';
  @override
  String get openInOrrery => '在 Orrery 中打开';
  @override
  String get readingHint => '正在读取历史…';
  @override
  String snapshots({required Object n}) => '${n} 个快照';
  @override
  String get steady => '平稳 — 此窗口内无结构事件。';
  @override
  String get title => '结构轨迹';
}

// Path: xray.verdict
class _Translations$xray$verdict$zh_Hans extends Translations$xray$verdict$en {
  _Translations$xray$verdict$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% 典范';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% 典范 · ${decisive}% 决定性';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$zh_Hans
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get manual => '手动';
  @override
  String get safe => '安全';
  @override
  String get guided => '引导';
  @override
  String get assisted => '辅助';
  @override
  String get full => '完全';
  @override
  String label({required Object label}) => '信任：${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$zh_Hans
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get accept => '采纳';
  @override
  String get other => '另一方';
  @override
  String get both => '两者';
  @override
  String get navigate => '导航';
  @override
  String get jumpNext => '跳到下一个';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$zh_Hans
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get merge => '合并';
  @override
  String get cherryPick => '拣选';
  @override
  String get revert => '还原';
  @override
  String get resolve => '解决';
  @override
  String get switchOp => '切换';
  @override
  String get pull => '拉取';
  @override
  String get rebase => '变基';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      '将 ${branch} 变基到 ${base} 上';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$zh_Hans
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane => '近期有改动，附近有一位主导者。';
  @override
  String get activeSeam => '近期有改动，来自附近多人之手。';
  @override
  String get stableOwnerLane => '长期存在的轨道，由一位主导者掌控。';
  @override
  String get sharedLongLivedSeam => '随时间积累的共享接缝。';
  @override
  String get sharedLane => '共享轨道，无单一主导者。';
  @override
  String get resolving => '此行周围的历史仍在厘清中。';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$zh_Hans
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get hot => '火热';
  @override
  String get novel => '新奇';
  @override
  String get contested => '争夺';
  @override
  String get spreading => '扩散';
  @override
  String get stable => '稳定';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$zh_Hans
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => '位于 ${concept}';
  @override
  String get sitsInLocalSeam => '处于局部接缝';
  @override
  String workedMostlyBy({required Object owner}) => '附近主要由 ${owner} 经手';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '在另外 ${n} 处有回响',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      '接下来查看 ${path}${detail}';
  @override
  String inspectDetail({required Object reason}) => '（${reason}）';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$zh_Hans
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get tight => '紧密贴合';
  @override
  String get close => '较近贴合';
  @override
  String get loose => '松散贴合';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$zh_Hans
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => '附近支持 · ${label}';
  @override
  String localizedMove({required Object label}) => '局部改动 · ${label}';
  @override
  String surprisingMove({required Object label}) => '意外改动 · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$zh_Hans
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => '稳定结构';
  @override
  String get conflictingSignals => '信号冲突';
  @override
  String get novelShape => '新奇形态';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$zh_Hans
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => '测试镜像';
  @override
  String get semanticHistorySibling => '语义 + 历史同胞';
  @override
  String get recentCoChange => '近期共变';
  @override
  String get semanticSibling => '语义同胞';
  @override
  String get relatedStructure => '相关结构';
  @override
  String get tightlyBound => '紧密绑定';
  @override
  String get orbiting => '环绕';
  @override
  String get weaklyCoupled => '弱耦合';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$zh_Hans
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => '历史轨迹';
  @override
  String get testMirrorLane => '测试镜像轨道';
  @override
  String get structuralLane => '结构轨道';
  @override
  String get semanticNeighbourhood => '语义邻域';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$zh_Hans
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => '重要性高';
  @override
  String get importanceModerate => '重要性中等';
  @override
  String get mostlyAdditions => '以新增为主';
  @override
  String get mostlyDeletions => '以删除为主';
  @override
  String get tightlyCoupled => '紧密耦合的文件';
  @override
  String get overlapsWorkingTree => '与你的工作区重叠';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$zh_Hans
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$zh_Hans open =
      _Translations$onboarding$repo$doors$open$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$zh_Hans clone =
      _Translations$onboarding$repo$doors$clone$zh_Hans._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$zh_Hans create =
      _Translations$onboarding$repo$doors$create$zh_Hans._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$zh_Hans
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '从 URL 克隆';
  @override
  String get urlLabel => '仓库 URL';
  @override
  String get targetLabel => '目标文件夹';
  @override
  String get browse => '浏览…';
  @override
  String get clone => '克隆';
  @override
  String get cloning => '正在克隆…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$zh_Hans
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => '打开仓库';
  @override
  String get createRepository => '创建仓库';
  @override
  String get cloneTarget => '克隆目标';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$zh_Hans
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => '需要 URL 和目标路径。';
  @override
  String get createFailed => '创建仓库失败。';
  @override
  String get cloneFailed => '克隆仓库失败。';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$zh_Hans
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get xray => '仓库 X-Ray';
  @override
  String get settings => '设置';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$zh_Hans
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => '项目';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$zh_Hans
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object total, required Object staged}) =>
      '${total} 个文件中的 ${staged} 个';
  @override
  String stagedCount({required Object n}) => '${n} 个已暂存';
  @override
  String get commitMessageHint => '提交信息…';
  @override
  String get commitAndPush => '提交并推送';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$zh_Hans
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get header => '历史';
  @override
  String get viewingLast => '正在查看最近 20 个提交';
  @override
  String get inFlight => '进行中';
  @override
  String get you => '你';
  @override
  String get commit1 => '教小狐狸下咽前先闻一闻';
  @override
  String get commit2 => '琥珀：留住气味过夜';
  @override
  String get commit3 => '让卷心菜退役，改用琥珀 + 荆棘';
  @override
  String get commit4 => '荆棘把守大门';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$zh_Hans
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => '分支';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => '已吸收';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ 跟踪：${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$zh_Hans
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => '你的私人 Git 客户端。';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$zh_Hans
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get question => '为什么选 FLUTTER？';
  @override
  String get body =>
      '最初的版本是个 Tauri 应用（Rust + TypeScript）。我早就觉得它慢。后来我偶然看了一档平时不看的直播，一位主播说了同样的话，这成了我下决心换掉它的临门一脚。他并没有推荐 Flutter，恰恰相反。是我自己找到了 Dart，随手拼了个原型，启动时间就从大约 15 秒降到了 1 秒以内。天差地别。再见了 Tauri 时代。\n\nFlutter 的渲染管线更接近游戏引擎而非 DOM，对于一款“界面即产品”的桌面应用来说，这就是一切。Dart 也着实是门好语言。谱引擎背后的数学最初是在 Rust 里做的原型，所以那部分工作平稳地延续了下来。\n\nFlutter 默认跨平台，这很棒，但它骨子里带着谷歌味，所以难免有些小怪癖。';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$zh_Hans
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get question => '什么是谱引擎？';
  @override
  String get body =>
      '每次提交时，你一并改动的文件会随时间形成某种模式。谱引擎读取你的提交图，把这些共变模式分解成信号：哪些文件相互耦合、耦合有多紧、以及它们在仓库中扮演怎样的结构角色。本质上就是对你的开发历史做谱分析。在一个 git 客户端里。故意为之。\n\n这套数学是全新的，所以我把它当作游戏手感来对待：调它、测它、改它，反复打磨，直到这些信号感觉对味为止。\n\n这些信号会汇入方方面面。历史里的地震图、提交标题下方绘出的色条、审查系统、Muse、文件星座图。整个应用都从这一层往下推理，而不是反过来。';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$zh_Hans
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get question => '这将走向何方？';
  @override
  String get body =>
      '第一个里程碑是与 GitHub Desktop、SourceTree 和 GitKraken 完全看齐。一个跨平台的 git 客户端，既要快得称手，又要把基本功打磨得胜过其他任何工具。这一步基本已经到位。谱引擎已经让我们在那些别的客户端要你手动琢磨的操作上占了优势。\n\n再往前，目标是在速度、无障碍、智能和整体体验上超越所有其他 git 客户端。管线里还有比这里公布的更多的东西。';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$zh_Hans
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$zh_Hans
  verbLed = _Translations$settings$commitPreview$title$verbLed$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$zh_Hans
  descriptive =
      _Translations$settings$commitPreview$title$descriptive$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$title$narrative$zh_Hans
  narrative = _Translations$settings$commitPreview$title$narrative$zh_Hans._(
    _root,
  );
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$zh_Hans
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$zh_Hans verbLed =
      _Translations$settings$commitPreview$base$verbLed$zh_Hans._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$zh_Hans
  descriptive = _Translations$settings$commitPreview$base$descriptive$zh_Hans._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$zh_Hans
  narrative = _Translations$settings$commitPreview$base$narrative$zh_Hans._(
    _root,
  );
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$zh_Hans
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$zh_Hans
  verbLed =
      _Translations$settings$commitPreview$balancedSuffix$verbLed$zh_Hans._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$zh_Hans
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$zh_Hans._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$zh_Hans
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$zh_Hans._(
        _root,
      );
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$zh_Hans
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$zh_Hans
  verbLed =
      _Translations$settings$commitPreview$everythingSuffix$verbLed$zh_Hans._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$zh_Hans
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$zh_Hans._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$zh_Hans
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$zh_Hans._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$zh_Hans
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim => '仓库的分支面足够广，值得用分支感知的方式来导航。';
  @override
  String get broadTitle => '分支模型有面积';
  @override
  String localBranchesDetail({required Object count}) => '${count} 个本地分支。';
  @override
  String get localBranchesLabel => '本地分支';
  @override
  String remoteBranchesDetail({required Object count}) => '${count} 个远程分支。';
  @override
  String get remoteBranchesLabel => '远程分支';
  @override
  String get simpleClaim => '可见的分支模型很窄。';
  @override
  String get simpleTitle => '简单分支模型';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$zh_Hans
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '工作以集中的爆发方式落地，而非平稳的日常节律。';
  @override
  String get title => '爆发式开发节奏';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$zh_Hans
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) => '${count} 个引用位于常规分支/标签空间之外。';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} 个引用位于 heads/remotes/tags 之外。';
  @override
  String get evidenceLabel => '隐藏引用';
  @override
  String get namespacesLabel => '命名空间';
  @override
  String get title => '隐藏的 Git 命名空间';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$zh_Hans
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String claim({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '少数几个文件相对其改动次数承担了不成比例的共变权重。',
      );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 次改动 · 引力 φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('zh'))(
        n,
        other: '${n} 个关键石桥接文件',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$zh_Hans
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '检查点式的提交实质性地扭曲了朴素的历史指标。';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} 个提交匹配机器/会话模式。';
  @override
  String get machineCommitsLabel => '机器提交';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} 个原始提交对 ${filtered} 个过滤后提交。';
  @override
  String get rawVsFilteredLabel => '原始对过滤';
  @override
  String get title => '机器历史主导原始指标';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$zh_Hans
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      '历史从 `${older}` 转向 `${newer}`，暗示一次技术栈或表层的迁移。';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} 次改动，上次活跃 ${lastActive}。';
  @override
  String get title => '可见的架构迁移';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$zh_Hans
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '少数文件和目录吸收了不成比例的改动份额。';
  @override
  String get title => '热点集中且狭窄';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} 占可见热点集的 ${pct}%。';
  @override
  String get topHotspotLabel => '首要热点';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '此历史切片中有 ${count} 位作者。';
  @override
  String get visibleAuthorsLabel => '可见作者';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$zh_Hans
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'Git 标签未被用作可见的发布或里程碑层。';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '已配置 ${count} 个远程端点。';
  @override
  String get remoteEndpointsLabel => '远程端点';
  @override
  String get tagCountDetail => '找到 0 个标签。';
  @override
  String get tagCountLabel => '标签数';
  @override
  String get title => '无正式的发布/标签轨迹';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$zh_Hans
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'Reflog 体量暗示已发布提交之外还有集中的本地迭代。';
  @override
  String get peakReflogDayLabel => 'reflog 峰值日';
  @override
  String get title => '密集的本地编辑会话';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$zh_Hans
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` 是一个改动频繁的${kind}，只有一位可见的独立作者。';
  @override
  String ownerCountDetail({required Object count}) => '${count} 位独立作者。';
  @override
  String get ownerCountLabel => '所有者数量';
  @override
  String get title => '单一所有者热点';
  @override
  String get touchCountLabel => '改动次数';
  @override
  String touchDetailFiltered({required Object count}) => '过滤后历史中 ${count} 次改动。';
  @override
  String touchDetailRaw({required Object count}) => '原始历史中 ${count} 次改动。';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$zh_Hans
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '打开';
  @override
  String get subtitle => '已有的';
  @override
  String get hint => '你已经有的仓库';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$zh_Hans
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '克隆';
  @override
  String get subtitle => '从 URL';
  @override
  String get hint => '粘贴一个远程 URL';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$zh_Hans
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$zh_Hans._(TranslationsZhHans root)
    : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get title => '创建';
  @override
  String get subtitle => '全新的';
  @override
  String get hint => '从头开始';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$zh_Hans
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '让狐狸跳过闻着不对劲的饼干';
  @override
  String get s2 => '训练狐狸吞下前拒收被动过手脚的饼干';
  @override
  String get s3 => '迫使狐狸在门口对每块饼干做取证核验';
  @override
  String get def => '教狐狸拒收坏饼干';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$zh_Hans
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '狐狸现在会挑饼干了';
  @override
  String get s2 => '饼干检查流程，已灌进狐狸脑里';
  @override
  String get s3 => '饼干核验取证术，靠反复演练嵌进狐狸体内';
  @override
  String get def => '闻饼干协议，已装进狐狸体内';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$zh_Hans
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '狐狸开始跳过闻着不对劲的饼干了';
  @override
  String get s2 => '和狐狸坐下来，一块块理清哪些饼干该拒收';
  @override
  String get s3 => '花了大半个下午说服狐狸：不是每块递上来的饼干，都真心是块饼干';
  @override
  String get def => '让狐狸吃前先闻闻饼干';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$zh_Hans
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '狐狸扫一眼。有点不对的就丢下。';
  @override
  String get s2 => '狐狸检查每个 token，拒收任何气味不对的，并在门廊记下这次拒收。';
  @override
  String get s3 => '狐狸绕着每个 token 转，从三个角度嗅空气，拒收任何读着不对的，再等上一拍确认拒收生效。';
  @override
  String get def => '狐狸如今会嗅每个 token，礼貌地谢绝可疑的那些。';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$zh_Hans
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '对怪异的那些，大多轻轻放过。';
  @override
  String get s2 => '对每个气味不对的 token 都有一次记录在案的拒收，从门廊发出并记下。';
  @override
  String get s3 => '对每个气味不对的 token 都有一次公证过的拒收，从门廊发出，一爪抬起，另一爪不动。';
  @override
  String get def => '对可疑 token 从门廊发出一次礼貌的拒收。';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$zh_Hans
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '狐狸就这么不再吃那些怪的了。轻松。';
  @override
  String get s2 => '每个 token 从前都不假思索地咽下去；如今有了停顿、有了认真一看、对不对劲的那些有了拒收。';
  @override
  String get s3 =>
      '每个 token 从前都不假思索地咽下去。如今：一次停顿。空气，纳入。空气，屏住。狐狸盯着门廊的木板，等那种东西不对时它们偶尔会有的微小抽动，只有那时才做出判断。';
  @override
  String get def => '每个 token 从前都不带仪式地被咽下；如今先有一嗅。';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$zh_Hans
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 门廊没事。后院随便。';
  @override
  String get s2 => ' 每次拒收后清扫门廊；后院的泥在张贴的时段内允许。';
  @override
  String get s3 => ' 门廊一扫再扫；后院的泥按爪印和天气编目，狐狸在门槛停留得比从前更久。';
  @override
  String get def => ' 门廊保持干净；后院保留它的泥权。';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$zh_Hans
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 门廊还行。后院干后院的事。';
  @override
  String get s2 => ' 门廊作为证据洁净区；后院作为指定泥区，时段已张贴。';
  @override
  String get s3 => ' 门廊作为证据级洁净室；后院作为编目泥档案库；门槛作为狐狸站着想太久的地方。';
  @override
  String get def => ' 门廊干净；泥权保留在后院。';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$zh_Hans
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 门廊没事。后院，谁知道呢。';
  @override
  String get s2 => ' 门廊事后被保持干净；狐狸退回后院，那才是思考发生的地方。';
  @override
  String get s3 => ' 那晚门廊被刷了两遍。狐狸慢慢走过后院，在那根一如既往的篱笆桩旁停下，回头看门廊，仿佛门廊欠了什么。';
  @override
  String get def => ' 门廊保持干净，尽管后院在尊严上仍然胜出。';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$zh_Hans
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 琥珀在那儿。飘移飘着。荆棘必要时会刺。大多啥也没有。';
  @override
  String get s2 => ' 琥珀留住每股气味供复核。飘移把当天的空气送向门口的荆棘，荆棘为每次拒收标记，供傍晚清点。';
  @override
  String get s3 =>
      ' 琥珀留住每股气味，并按时辰给出不同权重。飘移以本不该有影响却有影响的角度穿过门廊。门口的荆棘为拒收刺一下，为狐狸险些漏掉的那些刺两下，哪怕没别人看得出，狐狸也分得清其中的差别。';
  @override
  String get def => ' 琥珀留住气味。飘移把它送走。门口的荆棘拦下不该通过的。';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$zh_Hans
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 琥珀在桩上。飘移在空气里。荆棘在门口。没事。';
  @override
  String get s2 => ' 琥珀作为指定气味见证者；飘移作为记录在案的环境气息；荆棘刺痕作为当天的拒收记录，黄昏时对账。';
  @override
  String get s3 =>
      ' 琥珀作为气味见证者，其沉默本身即是一种读数；飘移作为有规律的环境气息，在不对劲的日子里移动得不对劲；荆棘作为门口的记数者，狐狸睡前会查它的刺痕，天亮前再查一遍。';
  @override
  String get def => ' 琥珀作为气味见证者；飘移作为环境上下文；荆棘作为门口那道安静的拒收刺痕。';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$zh_Hans
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$zh_Hans._(
    TranslationsZhHans root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsZhHans _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 琥珀在附近。飘移来了又走。荆棘悄悄干着它的活。无所谓，挺闲适。';
  @override
  String get s2 => ' 琥珀保管当天的气味记录，飘移按方向和时辰被记下，荆棘的刺痕经清点并由门廊会签。';
  @override
  String get s3 =>
      ' 琥珀保管着气味记录，但狐狸赌咒说某些清晨它分量更重。飘移一如既往地穿过门廊，也就是说，在要紧的日子里移动得不对劲。门口的荆棘为每次拒收做了标记；狐狸天一亮就出门去数它们，像数一遍已经数过的台阶。';
  @override
  String get def => ' 琥珀保管着气味记录，飘移搅动空气，门口的荆棘拦下了该拦的。';
}
