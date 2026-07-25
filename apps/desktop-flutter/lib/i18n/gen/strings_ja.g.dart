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
class TranslationsJa extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsJa({
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
             locale: AppLocale.ja,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <ja>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsJa _root = this; // ignore: unused_field

  @override
  TranslationsJa $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsJa(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$ja app = _Translations$app$ja._(_root);
  @override
  late final _Translations$backend$ja backend = _Translations$backend$ja._(
    _root,
  );
  @override
  late final _Translations$branches$ja branches = _Translations$branches$ja._(
    _root,
  );
  @override
  late final _Translations$changes$ja changes = _Translations$changes$ja._(
    _root,
  );
  @override
  late final _Translations$common$ja common = _Translations$common$ja._(_root);
  @override
  late final _Translations$diff$ja diff = _Translations$diff$ja._(_root);
  @override
  late final _Translations$filament$ja filament = _Translations$filament$ja._(
    _root,
  );
  @override
  late final _Translations$history$ja history = _Translations$history$ja._(
    _root,
  );
  @override
  late final _Translations$historySurgery$ja historySurgery =
      _Translations$historySurgery$ja._(_root);
  @override
  late final _Translations$onboarding$ja onboarding =
      _Translations$onboarding$ja._(_root);
  @override
  late final _Translations$orrery$ja orrery = _Translations$orrery$ja._(_root);
  @override
  late final _Translations$palette$ja palette = _Translations$palette$ja._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$ja releaseNotes =
      _Translations$releaseNotes$ja._(_root);
  @override
  late final _Translations$repoSummary$ja repoSummary =
      _Translations$repoSummary$ja._(_root);
  @override
  late final _Translations$review$ja review = _Translations$review$ja._(_root);
  @override
  late final _Translations$settings$ja settings = _Translations$settings$ja._(
    _root,
  );
  @override
  late final _Translations$sync$ja sync = _Translations$sync$ja._(_root);
  @override
  late final _Translations$xray$ja xray = _Translations$xray$ja._(_root);
}

// Path: app
class _Translations$app$ja extends Translations$app$en {
  _Translations$app$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => '設定';
  @override
  String get panelReleaseNotes => 'リリースノート';
  @override
  String get panelFilamentFindings => 'Filament の指摘';
  @override
  String get filamentFindingsUpper => 'FILAMENT の指摘';
  @override
  late final _Translations$app$cheatsheet$ja cheatsheet =
      _Translations$app$cheatsheet$ja._(_root);
  @override
  String get commandPaletteTooltip => 'コマンドパレット   /';
  @override
  String get newDeskFallback => '新規 Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => '現在';
  @override
  String get noRepositoryOpen => 'リポジトリが開かれていません';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Desk として開けませんでした：${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'フォージを検出できませんでした：${error}';
  @override
  String get cannotFetchPrNoForge => 'PR を取得できません：このリポジトリのフォージを検出できません。';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref}をリモートの最新で上書きしますか？';
  @override
  String get overwrite => '上書き';
  @override
  String couldntFetchPr({required Object error}) => 'PR を取得できませんでした：${error}';
  @override
  String get promoteDeskToPr => 'Desk を PR に昇格';
  @override
  String get applyToMain => 'main に適用';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      '${target}を${source}から更新';
  @override
  String bringChangesFromHere({required Object source}) =>
      '${source}の変更をここに取り込む';
  @override
  String get editLocalPr => 'ローカル PR を編集';
  @override
  String get discardLocalPr => 'ローカル PR を破棄';
  @override
  String get closeDesk => 'Desk を閉じる';
  @override
  String couldntPromote({required Object error}) => '昇格できませんでした：${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      '適用する前に Desk の変更をコミットまたは棚上げしてください。';
  @override
  String get couldNotResolveMainWorktree => 'メイン作業ツリーのパスを解決できませんでした。';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Desk を昇格できませんでした：${error}';
  @override
  String get couldntDetermineBaseBranch => 'この Desk のベースブランチを特定できませんでした。';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'PR のベースとヘッドが同じブランチ（${branch}）です — 適用するものがありません。';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch}を${base}に適用しました';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
    n,
    other: '${target}を${source}に更新しました（${n} コミット）。',
  );
  @override
  String get fastForwardFailedFallback =>
      '早送りがきれいに着地できませんでした — 代わりにパッチのプレビューを表示します。';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
    n,
    other: '${target}は${source}より ${n} コミット先行しています。',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target}はすでに${source}と同期しています。';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      '${target}に未コミットの変更があります — 代わりにパッチとしてプレビューします。';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => '${target}を${source}から更新';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      '${source}から取り込む更新はありません。';
  @override
  String get updatePrepFailed => '更新の準備に失敗しました';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => '${source}の変更を${target}へ取り込む';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      '${source}から${target}へ取り込めるパッチ可能な変更はありません。';
  @override
  String get patchPrepFailed => 'パッチの準備に失敗しました';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}：${error}';
  @override
  String get titleHint => 'タイトル';
  @override
  String get bodyHint => '本文';
  @override
  String get bodyOptionalHint => '本文（任意）';
  @override
  String get draftLower => '下書き';
  @override
  String get cancelLower => 'キャンセル';
  @override
  String get saveLower => '保存';
  @override
  String couldntSave({required Object error}) => '保存できませんでした：${error}';
  @override
  String get stashedNoOtherDesk =>
      '変更をスタッシュしました — 適用先の他の Desk がありません。git stash pop で復元してください。';
  @override
  String get suggestedSource => '推奨ソース';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} 件変更';
  @override
  String tooltipAheadCount({required Object n}) => '${n} 先行';
  @override
  String tooltipBehindCount({required Object n}) => '${n} 遅延';
  @override
  String get focusedEdits => '焦点の絞られた編集';
  @override
  String get editsSpreadAcrossSubsystems => 'サブシステム全体に広がる編集';
  @override
  String get editsTouchingManySubsystems => '多くのサブシステムに触れる編集';
  @override
  String get focusedBranch => '焦点の絞られたブランチ';
  @override
  String get branchSpansMultipleSubsystems => 'ブランチが複数のサブシステムにまたがる';
  @override
  String get structurallyDivergentFromMainline => 'メインラインから構造的に分岐';
  @override
  String get localPr => 'ローカル PR';
  @override
  String lastTouched({required Object time}) => '最終タッチ ${time}';
  @override
  String driftGroupCount({required Object dir, required Object n}) =>
      '${dir} に ${n} 件';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => '未コミットの変更';
  @override
  String get closeDeskQuestion => 'Desk を閉じますか？';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '未コミットのファイル ${n} 件。',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'main より ${n} コミット先行。',
      );
  @override
  String get willRemoveWorktreeDirectory => '作業ツリーのディレクトリが削除されます。';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイル変更',
      );
  @override
  String get shelveHere => 'ここに棚上げ';
  @override
  String get discardAndClose => '破棄して閉じる';
  @override
  String get noRepository => 'リポジトリなし';
  @override
  String get issuePromotedToRemote => 'Issue をリモートに昇格しました。';
  @override
  String get pushedToRemote => 'リモートにプッシュしました。';
  @override
  String get pulledFromRemote => 'リモートからプルしました。';
  @override
  String get remoteIssueNotFound => 'リモートの Issue が見つかりません';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} をローカルにインポートしました。';
  @override
  String get issueAbandoned => 'Issue を放棄しました。';
  @override
  String get abandonIssue => 'Issue を放棄';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'ローカル Issue #${id} を完全に削除しますか？ ref が削除され、元に戻せません。';
  @override
  String get abandon => '放棄';
  @override
  String publishedBranch({required Object branch}) => '${branch}を公開しました。';
  @override
  String get publishingEllipsis => '公開中…';
  @override
  String get publish => '公開';
  @override
  String get noRemoteConfigured => 'このリポジトリにリモートが設定されていません。';
  @override
  String get jumpToDesk => 'Desk へジャンプ';
  @override
  String get arrowOpen => '→ 開く';
  @override
  String get openOnANewDesk => '新しい Desk で開く';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'new-branch-name';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ 新規 Desk';
  @override
  String get fromHeadEllipsis => 'HEAD から…';
  @override
  String get viewAllBranches => 'すべてのブランチを表示';
  @override
  String get issuesLower => 'Issue';
  @override
  String get newIssueLower => '新規 Issue';
  @override
  String get noneLinked => 'リンクなし';
  @override
  String get noOpenIssues => 'オープンな Issue なし';
  @override
  String get createAndPushLower => '作成＋プッシュ';
  @override
  String get createLower => '作成';
  @override
  String get remoteLower => 'リモート';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'リモートに昇格';
  @override
  String get pushToRemote => 'リモートにプッシュ';
  @override
  String get pullFromRemote => 'リモートからプル';
  @override
  String get importLabel => 'インポート';
  @override
  String get failedToCreateRepository => 'リポジトリの作成に失敗しました。';
  @override
  String get openRepositoryLower => 'リポジトリを開く';
  @override
  String get newRepositoryLower => '新規リポジトリ';
  @override
  String get back => '戻る';
  @override
  String get openRepositoryDialogTitle => 'リポジトリを開く';
  @override
  String get createRepositoryDialogTitle => 'リポジトリを作成';
  @override
  String get cloneTargetDialogTitle => 'クローン先';
  @override
  String get cloneToDialogTitle => 'クローン先';
  @override
  String get exportToDialogTitle => 'エクスポート先';
  @override
  String get createFromTemplateInDialogTitle => 'テンプレートから作成する場所';
  @override
  String get notAGitRepoInitConfirm => 'git リポジトリではありません。ここに初期化しますか？';
  @override
  String get repositoryUrlRequired => 'リポジトリ URL が必要です。';
  @override
  String get failedToCloneRepository => 'リポジトリのクローンに失敗しました。';
  @override
  String cloningEllipsis({required Object name}) => '${name}をクローン中…';
  @override
  String get cloneCancelled => 'クローンをキャンセルしました。';
  @override
  String get noProjectsYet => 'まだプロジェクトがありません';
  @override
  String get dissolveGroup => 'グループを解散';
  @override
  String get projectsHeader => 'プロジェクト';
  @override
  String get cloneLabel => 'クローン';
  @override
  String get createLabel => '作成';
  @override
  String get openLabel => '開く';
  @override
  String get repositoryUrlPlaceholder => 'リポジトリ URL';
  @override
  String get projectNameOrFullPathPlaceholder => 'プロジェクト名またはフルパス';
  @override
  String get pathToProjectPlaceholder => '/path/to/project';
  @override
  String get cloneToFolderPathPlaceholder => 'クローン先フォルダーのパス';
  @override
  String get switchToCreateRepo => 'リポジトリ作成に切り替え';
  @override
  String get explorer => 'エクスプローラー';
  @override
  String get terminal => 'ターミナル';
  @override
  String get cloneUrl => 'クローン URL';
  @override
  String get copyPath => 'パスをコピー';
  @override
  String get export => 'エクスポート';
  @override
  String get readme => 'README';
  @override
  String get duplicate => '複製';
  @override
  String get template => 'テンプレート';
  @override
  String get forgetThisProject => 'このプロジェクトを忘れる';
  @override
  String get aiKindCommitMessage => 'コミットメッセージ';
  @override
  String get aiKindReview => 'レビュー';
  @override
  String get aiKindMuse => 'Muse';
  @override
  String get aiKindPresent => 'プレゼント';
  @override
  String get aiKindDebug => 'デバッグ';
  @override
  String aiStatusRunning({required Object kind}) => '${kind}実行中';
  @override
  String aiStatusFailedUnread({required Object kind}) => '${kind}失敗（未読）';
  @override
  String aiStatusReadyUnread({required Object kind}) => '${kind}準備完了（未読）';
  @override
  String get filesLower => 'ファイル';
  @override
  String get commitsLower => 'コミット';
  @override
  String get undoLabel => '取り消し';
  @override
  String get goLabel => '実行';
  @override
  String countdownSeconds({required Object n}) => '${n}秒';
  @override
  String get collapseGlyph => '▲ 折りたたむ';
  @override
  String moreLinesGlyph({required Object n}) => '▼ 他 ${n} 行';
}

// Path: backend
class _Translations$backend$ja extends Translations$backend$en {
  _Translations$backend$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$ja ops = _Translations$backend$ops$ja._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$ja mergeOutcome =
      _Translations$backend$mergeOutcome$ja._(_root);
}

// Path: branches
class _Translations$branches$ja extends Translations$branches$en {
  _Translations$branches$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'AI レビューを実行中…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => '指摘';
  @override
  String get observations => '所見';
  @override
  String get renameEllipsis => '名前を変更…';
  @override
  String get publish => '公開';
  @override
  String publishFailed({required Object error}) => '公開に失敗しました：${error}';
  @override
  String couldntOpenDesk({required Object error}) => 'Desk を開けませんでした：${error}';
  @override
  String syncFailed({required Object error}) => '同期に失敗しました：${error}';
  @override
  String get renameBranchTitle => 'ブランチ名を変更';
  @override
  String get newNameHint => '新しい名前';
  @override
  String get rename => '名前を変更';
  @override
  String invalidBranchName({required Object name}) =>
      '「${name}」は有効なブランチ名ではありません。';
  @override
  String renameFailed({required Object error}) => '名前の変更に失敗しました：${error}';
  @override
  String deletingBranch({required Object name}) => '${name}を削除中';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '「${name}」は Desk「${desk}」で開かれています。';
  @override
  String get openDesk => 'Desk を開く';
  @override
  String openInDeskShort({required Object desk}) => 'Desk「${desk}」で開く';
  @override
  String get couldNotPinBranch => 'ブランチの先端をピン留めできませんでした。削除をスキップしました';
  @override
  String get couldNotPinTag => 'タグをピン留めできませんでした。削除をスキップしました';
  @override
  String deletingTag({required Object name}) => 'タグ ${name} を削除中';
  @override
  String get applyToActiveChanges => 'アクティブな変更に適用…';
  @override
  String get couldNotLoadPrDiff => 'PR の差分を読み込めませんでした。';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}：${title}';
  @override
  String mergeIntoDesk({required Object branch}) => '${branch}にマージ…';
  @override
  String get checkoutThisPr => 'この PR をチェックアウト';
  @override
  String get mergeIntoNewDesk => '新しい Desk にマージ…';
  @override
  String get pushToForge => 'フォージにプッシュ';
  @override
  String get linkToIssue => 'Issue にリンク…';
  @override
  String get gitPatch => '↓ git パッチ';
  @override
  String get copyBranchName => 'ブランチ名をコピー';
  @override
  String copiedRef({required Object ref}) => '「${ref}」をコピーしました';
  @override
  String get reviewPr => 'PR をレビュー';
  @override
  String get openInBrowser => 'ブラウザーで開く';
  @override
  String get markAsRead => '既読にする';
  @override
  String get markAsUnread => '未読にする';
  @override
  String get replaceLocalCommitsTitle => 'ローカルコミットを置き換えますか？';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref}には、リモート PR のヘッドにないローカルコミットがあります。更新すると、それらはリモートの最新で置き換えられます。';
  @override
  String get update => '更新';
  @override
  String couldntFetchPr({required Object error}) => 'PR を取得できませんでした：${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Desk として開けませんでした：${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'ブラウザーで開けませんでした：${error}';
  @override
  String get noIssuesYetLocal =>
      'まだ Issue がありません。上流で開くか、Issue レンズの「+ new local issue」を使ってください。';
  @override
  String get remotePrsLinkLocalOnly =>
      'リモート PR はローカル Issue にのみリンクできます。「+ new local issue」で作成してください。';
  @override
  String linkPrToIssues({required Object number}) =>
      'PR #${number} を Issue にリンク';
  @override
  String get noPrsYetLocal => 'まだ PR がありません。上流で開くか、Desk を PR に昇格してください。';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'リモート Issue はローカル PR にのみリンクできます。まず Desk を PR に昇格してください。';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Issue #${number} を PR にリンク';
  @override
  String couldntToggleLink({required Object error}) =>
      'リンクを切り替えられませんでした：${error}';
  @override
  String get openPatchDialogTitle => 'パッチを開く（.patch / .diff）';
  @override
  String get clipboardNoText => 'クリップボードにテキストがありません。';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) => 'パッチを開けませんでした：${error}';
  @override
  String get patchEmptyOrUnparseable => 'パッチが空か、解析できません。';
  @override
  String get prPushedToForge => 'PR をフォージにプッシュしました。';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref}をリモートの最新で上書きしますか？';
  @override
  String get overwrite => '上書き';
  @override
  String get loadingBranchesTitle => 'ブランチを読み込み中';
  @override
  String get loadingBranchesMessage => 'ローカルのブランチとタグを読み込んでいます。';
  @override
  String get branchesUnavailableTitle => 'ブランチを取得できません';
  @override
  String get filterPullRequestsHint => 'プルリクエストを絞り込み…';
  @override
  String get filterIssuesHint => 'Issue を絞り込み…';
  @override
  String get branchNameHint => 'ブランチ名';
  @override
  String get tagsNewestFirst => 'タグ、新しい順';
  @override
  String get tagsOldestFirst => 'タグ、古い順';
  @override
  String get flipSortDirection => '並び順を反転';
  @override
  String get readingPullRequests => 'プルリクエストを読み込み中…';
  @override
  String get noOpenPullRequests => 'オープンなプルリクエストなし';
  @override
  String get noPullRequestsHint => 'ブランチから開くか、Desk を昇格してください。';
  @override
  String get noPrsMatchFilters => '条件に合う PR がありません';
  @override
  String get toggleFiltersRowAbove => '上の行でフィルターをオフにしてください。';
  @override
  String get issuesNewestFirst => 'Issue、新しい順';
  @override
  String get issuesOldestFirst => 'Issue、古い順';
  @override
  String get issuesHeading => 'ISSUE';
  @override
  String get readingIssuesLower => 'Issue を読み込み中…';
  @override
  String get noOpenIssues => 'オープンな Issue なし';
  @override
  String get noIssuesHint => '作業やバグの管理は + new から。';
  @override
  String get nothingMatches => '一致するものがありません';
  @override
  String get toggleFiltersAbove => '上でフィルターをオフにしてください。';
  @override
  String get bucketFresh => '新しい';
  @override
  String get bucketThisWeek => '今週';
  @override
  String get bucketStalled => '停滞';
  @override
  String get bucketOlder => '古い';
  @override
  String get couldNotResolveMainWorktree => 'メイン作業ツリーのパスを解決できませんでした。';
  @override
  String couldntSubmitReview({required Object error}) =>
      'レビューを送信できませんでした：${error}';
  @override
  String get reviewAiNotAvailable => 'レビュー AI はまだ利用できません。';
  @override
  String get noReviewModelConfigured => 'レビューモデルが設定されていません。';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({required num n, required Object branch}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${branch}に未コミットの変更が ${n} 件あります — 先にコミットまたはスタッシュしてください。',
      );
  @override
  String get targetDeskNoBranch => '対象の Desk にブランチがありません。';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'PR #${number} を${branch}にマージ';
  @override
  String get conflictCheckUnavailableVersion =>
      'コンフリクトチェックは利用できません — git 2.38 以降が必要です';
  @override
  String get conflictCheckUnavailable => 'コンフリクトチェックは利用できません';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'コンフリクトします · ${n} ファイル',
      );
  @override
  String plusMore({required Object n}) => '+${n} 件';
  @override
  String get rebase => 'リベース';
  @override
  String get squash => 'スカッシュ';
  @override
  String get mergeCommit => 'マージコミット';
  @override
  String noDeskForBranch({required Object branch}) =>
      'ブランチ ${branch} の Desk が見つかりません';
  @override
  String get mergeAnyway => 'それでもマージ';
  @override
  String get readingIssues => 'Issue を読み込み中…';
  @override
  String get openUpstreamOrLocal => '上流で開くか、ローカルで開いてください。';
  @override
  String get noIssuesMatchFilters => '条件に合う Issue がありません';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Issue を作成できませんでした：${error}';
  @override
  String get promoteToRemote => 'リモートに昇格';
  @override
  String get pushToRemote => 'リモートにプッシュ';
  @override
  String get pullFromRemote => 'リモートからプル';
  @override
  String get import => 'インポート';
  @override
  String get linkToPr => 'PR にリンク…';
  @override
  String get abandon => '放棄';
  @override
  String get issuePromotedToRemote => 'Issue をリモートに昇格しました。';
  @override
  String get issuePushedToRemote => 'リモートにプッシュしました。';
  @override
  String get issuePulledFromRemote => 'リモートからプルしました。';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} をローカルにインポートしました。';
  @override
  String get abandonIssueTitle => 'Issue を放棄';
  @override
  String abandonIssueMessage({required Object id}) =>
      'ローカル Issue #${id} を完全に削除しますか？ ref が削除され、元に戻せません。';
  @override
  String couldntAbandon({required Object error}) => '放棄できませんでした：${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'コメントを投稿できませんでした：${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Issue を閉じられませんでした：${error}';
  @override
  String couldntAddLabel({required Object error}) => 'ラベルを追加できませんでした：${error}';
  @override
  String get lensBranches => 'ブランチ';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ パッチ';
  @override
  String get syncRibbon => '⇅ 同期';
  @override
  String get kbHeading => 'キーボード';
  @override
  String get kbNavigateRows => '行を移動';
  @override
  String get kbExpandCollapse => 'フォーカス行を展開／折りたたみ';
  @override
  String get kbCheckoutPr => 'フォーカス中の PR をローカルにチェックアウト';
  @override
  String get kbApproveReview => '承認 · レビュー';
  @override
  String get kbRequestChanges => '変更を要求';
  @override
  String get kbFocusSearch => '検索にフォーカス';
  @override
  String get kbSwitchLens => 'レンズを切り替え（ブランチ · PR）';
  @override
  String get kbToggleOverlay => 'このオーバーレイを切り替え';
  @override
  String get kbPressToDismiss => 'どこかを押して閉じる';
  @override
  String get overrideScarTooltip =>
      'チェック失敗のまま、または承認レビューなしでマージされました — まず火の中で調べてください';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイルがあなたの未コミット作業と重複',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '#${pr}  （${n} ファイル）',
      );
  @override
  String get prStateDraft => '下書き';
  @override
  String get localBadge => 'ローカル';
  @override
  String get myReviewPending => 'あなたのレビュー保留中';
  @override
  String get myReviewApproved => 'あなた ✓';
  @override
  String get myReviewChangesRequested => 'あなた ✗ 変更を要求';
  @override
  String get myReviewCommented => 'あなたがコメント';
  @override
  String get myReviewDefault => 'あなた';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} 件のコメント · 作者の最新を表示';
  @override
  String get tailLastComment => '最新のコメント';
  @override
  String tailLastReviewState({required Object state}) => '最新のレビュー · ${state}';
  @override
  String get tailLastReview => '最新のレビュー';
  @override
  String tailLastCheckState({required Object state}) => '最新のチェック · ${state}';
  @override
  String get tailLastCommit => '最新のコミット';
  @override
  String get tailLastActivity => '最新のアクティビティ';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件の Issue をクローズ — クリックでジャンプ',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件の PR が対応 — クリックでジャンプ',
      );
  @override
  String get checksLabel => 'チェック';
  @override
  String get reviewersLabel => 'レビュアー';
  @override
  String get conflictsLabel => 'コンフリクト';
  @override
  String exportFailed({required Object error}) => 'エクスポートに失敗しました：${error}';
  @override
  String get readingFiles => 'ファイルを読み込み中…';
  @override
  String get noDetailAvailable => '詳細なし';
  @override
  String get noFilesReported => '報告されたファイルなし';
  @override
  String get readingGitHistory => 'git 履歴を読み込み中…';
  @override
  String get knowsThisCode => 'このコードに詳しい';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '過去 1 年でこれらのファイルへの ${n} コミット',
      );
  @override
  String get willFight => '衝突する';
  @override
  String orbitalPartnerCos({required Object cos}) => '軌道パートナー — cos ${cos}';
  @override
  String get orbitLabel => '軌道';
  @override
  String get touchesYourLocalWork => 'あなたのローカル作業に触れる';
  @override
  String get mergingWillConflict => 'マージするとあなたの未コミット変更とコンフリクトする可能性が高い';
  @override
  String get closesHeading => 'クローズ';
  @override
  String get filesHeading => 'ファイル';
  @override
  String get orientAligned => '整列';
  @override
  String get orientAdjacent => '隣接';
  @override
  String get orientOrthogonal => '直交';
  @override
  String shapeField({required Object v}) => 'field ${v}';
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
  String shapeStress({required Object v}) => 'stress ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => '共鳴 ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      '通常この PR のファイルと共に動きます\n（${path}）';
  @override
  String get prStateDraftLower => '下書き';
  @override
  String get keystoneTooltip => 'キーストーン — リポジトリ全体をつなぐ橋ファイル';
  @override
  String get reviewNoteHint => 'メモを残す（任意）…';
  @override
  String get reviewComment => 'コメント';
  @override
  String get reviewRequestChanges => '変更を要求';
  @override
  String get reviewApprove => '✓ 承認';
  @override
  String get actionPatchDown => '↓ パッチ';
  @override
  String get actionPrReview => '✦ PR レビュー';
  @override
  String get actionOpenAsDesk => '⊞ Desk として開く';
  @override
  String get actionCheckout => '[c] チェックアウト';
  @override
  String get actionMerge => '[m] マージ ▾';
  @override
  String get mergeMenuMergeCommit => 'マージコミット';
  @override
  String get mergeMenuSquash => 'スカッシュしてマージ';
  @override
  String get mergeMenuRebase => 'リベースしてマージ';
  @override
  String get deleteBranchAfter => '後でブランチを削除';
  @override
  String checkDurationSec({required Object n}) => '${n}秒';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}分 ${s}秒';
  @override
  String assignedTo({required Object names}) => '担当：${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} 件のやりとり · ${time}';
  @override
  String get readingThread => 'スレッドを読み込み中…';
  @override
  String get addressedByHeading => '対応する PR';
  @override
  String get descriptionHeading => '説明';
  @override
  String get threadHeading => 'スレッド';
  @override
  String get replyHint => '返信…';
  @override
  String get assignMe => '自分を担当に';
  @override
  String get closeLower => 'クローズ';
  @override
  String get postReply => '↩ 投稿';
  @override
  String get remoteProviderUnavailable => 'リモートプロバイダーを利用できません';
  @override
  String get noRecognisedRemoteHost => 'このリポジトリに認識できるリモートホストがありません。';
  @override
  String get corpseGone => '消滅';
  @override
  String get corpseAbsorbed => '吸収済み';
  @override
  String get corpseSquashed => 'スカッシュ済み';
  @override
  String absorbedDeliveredIn({required Object hash}) => '${hash}で取り込み済み';
  @override
  String get absorbedNoChanges => 'マージしても変更は追加されません';
  @override
  String get corpseTagUpstreamGone => '上流が消滅';
  @override
  String corpseTagAbsorbed({required Object receipt}) => '吸収済み、${receipt}';
  @override
  String get corpseTagSquashed => 'スカッシュしてマージ済み';
  @override
  String semanticsCurrentBranch({required Object name}) => '${name}、現在のブランチ';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}、${upstream}を追跡中';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}、${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}、作業ツリーを開いています';
  @override
  String semanticsIdle({required Object name, required Object phrase}) =>
      '${name}、${phrase}';
  @override
  String semanticsCorpse({
    required Object name,
    required Object tag,
    required Object phrase,
  }) => '${name}、${tag}、${phrase}';
  @override
  String get crossLinkDesk => 'Desk';
  @override
  String get crossLinkPr => 'PR';
  @override
  String get crossLinkPrDraft => 'PR · 下書き';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件の Issue',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ 追跡：${upstream}';
  @override
  String get checkoutButton => 'チェックアウト';
  @override
  String get createBranch => 'ブランチを作成';
  @override
  String get newBranchName => '新しいブランチ名';
  @override
  String newBranchNameError({required Object error}) => '新しいブランチ名 — ${error}';
  @override
  String get forceDelete => '強制？';
  @override
  String get annotated => '注釈付き';
  @override
  String get applyCheckFailed => 'apply --check に失敗しました';
  @override
  String get openPatchFrom => 'パッチの取得元';
  @override
  String get patchFromFile => 'ファイルから…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'クリップボードから';
  @override
  String get patchFromClipboardHint => 'テキストを貼り付け';
  @override
  String get patchPreviewHeading => 'パッチのプレビュー';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'ステージしました。';
  @override
  String get appliedDone => '適用しました。';
  @override
  String get opening => '開いています…';
  @override
  String get mergeEditor => '⇋ マージエディター';
  @override
  String get staging => 'ステージ中…';
  @override
  String get applying => '適用中…';
  @override
  String get stage => 'ステージ';
  @override
  String get apply => '適用';
  @override
  String get refineHint => '調整…（例：「ロガーの変更も外して」）';
  @override
  String get reverseArmedTooltip => '準備完了 — 次の適用でパッチを逆適用します（-R）';
  @override
  String get reverseDisarmedTooltip => '逆適用を準備（-R） — 適用ではなく取り消す';
  @override
  String get reverseArmedLabel => '⟲ 逆適用 ✓';
  @override
  String get reverseLabel => '⟲ 逆適用';
  @override
  String get untouchedHeading => '⚠ 未変更';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイル中 ${count} 件がパッチに含まれていません',
      );
  @override
  String get staysConflicted => 'これらのファイルはコンフリクトしたままになります — 適用してもステージされません';
  @override
  String get orWith => 'または';
  @override
  String get noAiModelConfigured => 'AI モデルが設定されていません';
  @override
  String applyWithPatchFrom({required Object label}) => '${label}のパッチで適用';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => '${label}のパッチで適用  ·  ${model}';
  @override
  String get patching => 'パッチ適用中…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  ${label}のパッチで適用';
  @override
  String get orWithAnotherModel => 'または別のモデルで';
  @override
  String get applyCheckPassed => 'git apply --check に合格 — パッチはきれいに適用されます';
  @override
  String get gitApplyCheckFailed => 'git apply --check に失敗しました';
  @override
  String get appliesClean => 'きれいに適用されます';
  @override
  String get willNotApply => '適用されません';
  @override
  String get newLocalIssue => '新規ローカル Issue';
  @override
  String get filterHint => '絞り込み…';
  @override
  String get nothingToLink => 'まだリンクするものがありません。';
  @override
  String get nothingMatchesDot => '一致するものがありません。';
  @override
  String get relevantHeading => '関連';
  @override
  String get allHeading => 'すべて';
  @override
  String get doneLower => '完了';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => '新規ローカル Issue';
  @override
  String get titleHint => 'タイトル';
  @override
  String get bodyHint => '本文（Markdown）';
  @override
  String get cancelLower => 'キャンセル';
  @override
  String get createLower => '作成';
  @override
  String get deleteFailed => '削除に失敗しました';
  @override
  String reviewFailed({required Object error}) => 'レビューに失敗しました：${error}';
  @override
  String get resolutionFailed => '解決に失敗しました';
  @override
  String get patchBlocksNoCover => 'モデルが返したパッチブロックは、失敗しているファイルをカバーしていませんでした';
  @override
  String get applyFailed => '適用に失敗しました';
  @override
  String get emptyOrUnparseablePatch => 'モデルが空、または解析できないパッチを返しました';
  @override
  String noModelConfiguredFor({required Object label}) =>
      '「${label}」に設定されたモデルがありません';
}

// Path: changes
class _Translations$changes$ja extends Translations$changes$en {
  _Translations$changes$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$ja usage =
      _Translations$changes$usage$ja._(_root);
  @override
  late final _Translations$changes$tabs$ja tabs =
      _Translations$changes$tabs$ja._(_root);
  @override
  late final _Translations$changes$tabStrip$ja tabStrip =
      _Translations$changes$tabStrip$ja._(_root);
  @override
  late final _Translations$changes$select$ja select =
      _Translations$changes$select$ja._(_root);
  @override
  late final _Translations$changes$constellationToggle$ja constellationToggle =
      _Translations$changes$constellationToggle$ja._(_root);
  @override
  late final _Translations$changes$nudgeChip$ja nudgeChip =
      _Translations$changes$nudgeChip$ja._(_root);
  @override
  late final _Translations$changes$minimap$ja minimap =
      _Translations$changes$minimap$ja._(_root);
  @override
  late final _Translations$changes$tagInput$ja tagInput =
      _Translations$changes$tagInput$ja._(_root);
  @override
  late final _Translations$changes$composer$ja composer =
      _Translations$changes$composer$ja._(_root);
  @override
  late final _Translations$changes$commit$ja commit =
      _Translations$changes$commit$ja._(_root);
  @override
  late final _Translations$changes$rebase$ja rebase =
      _Translations$changes$rebase$ja._(_root);
  @override
  late final _Translations$changes$editor$ja editor =
      _Translations$changes$editor$ja._(_root);
  @override
  late final _Translations$changes$editorTitles$ja editorTitles =
      _Translations$changes$editorTitles$ja._(_root);
  @override
  late final _Translations$changes$askHint$ja askHint =
      _Translations$changes$askHint$ja._(_root);
  @override
  late final _Translations$changes$fileMenu$ja fileMenu =
      _Translations$changes$fileMenu$ja._(_root);
  @override
  late final _Translations$changes$multiFileMenu$ja multiFileMenu =
      _Translations$changes$multiFileMenu$ja._(_root);
  @override
  late final _Translations$changes$ignoreMenu$ja ignoreMenu =
      _Translations$changes$ignoreMenu$ja._(_root);
  @override
  late final _Translations$changes$discard$ja discard =
      _Translations$changes$discard$ja._(_root);
  @override
  late final _Translations$changes$snack$ja snack =
      _Translations$changes$snack$ja._(_root);
  @override
  late final _Translations$changes$trace$ja trace =
      _Translations$changes$trace$ja._(_root);
  @override
  late final _Translations$changes$cleanTree$ja cleanTree =
      _Translations$changes$cleanTree$ja._(_root);
  @override
  late final _Translations$changes$guardrail$ja guardrail =
      _Translations$changes$guardrail$ja._(_root);
  @override
  late final _Translations$changes$dropHint$ja dropHint =
      _Translations$changes$dropHint$ja._(_root);
  @override
  late final _Translations$changes$diffEmpty$ja diffEmpty =
      _Translations$changes$diffEmpty$ja._(_root);
  @override
  late final _Translations$changes$shelvePill$ja shelvePill =
      _Translations$changes$shelvePill$ja._(_root);
  @override
  late final _Translations$changes$stashAction$ja stashAction =
      _Translations$changes$stashAction$ja._(_root);
  @override
  late final _Translations$changes$stashContents$ja stashContents =
      _Translations$changes$stashContents$ja._(_root);
  @override
  late final _Translations$changes$stashFile$ja stashFile =
      _Translations$changes$stashFile$ja._(_root);
  @override
  late final _Translations$changes$fileRow$ja fileRow =
      _Translations$changes$fileRow$ja._(_root);
  @override
  late final _Translations$changes$resolveStrip$ja resolveStrip =
      _Translations$changes$resolveStrip$ja._(_root);
  @override
  late final _Translations$changes$badge$ja badge =
      _Translations$changes$badge$ja._(_root);
  @override
  late final _Translations$changes$review$ja review =
      _Translations$changes$review$ja._(_root);
  @override
  late final _Translations$changes$commitBtn$ja commitBtn =
      _Translations$changes$commitBtn$ja._(_root);
  @override
  late final _Translations$changes$shapeBtn$ja shapeBtn =
      _Translations$changes$shapeBtn$ja._(_root);
  @override
  late final _Translations$changes$dejaVu$ja dejaVu =
      _Translations$changes$dejaVu$ja._(_root);
  @override
  late final _Translations$changes$identity$ja identity =
      _Translations$changes$identity$ja._(_root);
  @override
  late final _Translations$changes$staleScope$ja staleScope =
      _Translations$changes$staleScope$ja._(_root);
  @override
  late final _Translations$changes$finding$ja finding =
      _Translations$changes$finding$ja._(_root);
  @override
  late final _Translations$changes$muse$ja muse =
      _Translations$changes$muse$ja._(_root);
  @override
  late final _Translations$changes$debug$ja debug =
      _Translations$changes$debug$ja._(_root);
  @override
  late final _Translations$changes$includeSummary$ja includeSummary =
      _Translations$changes$includeSummary$ja._(_root);
  @override
  late final _Translations$changes$status$ja status =
      _Translations$changes$status$ja._(_root);
  @override
  late final _Translations$changes$stash$ja stash =
      _Translations$changes$stash$ja._(_root);
  @override
  late final _Translations$changes$tooltips$ja tooltips =
      _Translations$changes$tooltips$ja._(_root);
  @override
  late final _Translations$changes$mergeEditor$ja mergeEditor =
      _Translations$changes$mergeEditor$ja._(_root);
  @override
  late final _Translations$changes$conflictResolution$ja conflictResolution =
      _Translations$changes$conflictResolution$ja._(_root);
  @override
  late final _Translations$changes$mergeFlow$ja mergeFlow =
      _Translations$changes$mergeFlow$ja._(_root);
  @override
  late final _Translations$changes$constellation$ja constellation =
      _Translations$changes$constellation$ja._(_root);
}

// Path: common
class _Translations$common$ja extends Translations$common$en {
  _Translations$common$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => '、';
  @override
  String get cancel => 'キャンセル';
  @override
  String get close => '閉じる';
  @override
  String get save => '保存';
  @override
  String get delete => '削除';
  @override
  String get retry => '再試行';
  @override
  String get copy => 'コピー';
  @override
  String get copied => 'コピーしました';
  @override
  String get done => '完了';
  @override
  String get loading => '読み込み中…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイル',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} コミット',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ブランチ',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'ローカル ${n} コミット',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'リモート ${n} コミット',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'コンフリクト ${n} ファイル',
      );
  @override
  late final _Translations$common$time$ja time = _Translations$common$time$ja._(
    _root,
  );
  @override
  late final _Translations$common$size$ja size = _Translations$common$size$ja._(
    _root,
  );
}

// Path: diff
class _Translations$diff$ja extends Translations$diff$en {
  _Translations$diff$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$ja status =
      _Translations$diff$status$ja._(_root);
  @override
  late final _Translations$diff$toolbar$ja toolbar =
      _Translations$diff$toolbar$ja._(_root);
  @override
  late final _Translations$diff$hunkDropdown$ja hunkDropdown =
      _Translations$diff$hunkDropdown$ja._(_root);
  @override
  String stagingFailed({required Object error}) => '部分ステージに失敗しました：${error}';
  @override
  late final _Translations$diff$trail$ja trail = _Translations$diff$trail$ja._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$ja pinned =
      _Translations$diff$pinned$ja._(_root);
  @override
  late final _Translations$diff$hunkHint$ja hunkHint =
      _Translations$diff$hunkHint$ja._(_root);
  @override
  late final _Translations$diff$binary$ja binary =
      _Translations$diff$binary$ja._(_root);
  @override
  late final _Translations$diff$media$ja media = _Translations$diff$media$ja._(
    _root,
  );
}

// Path: filament
class _Translations$filament$ja extends Translations$filament$en {
  _Translations$filament$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'リポジトリが開かれていません。';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'スキャン中 ${scanned} / ${total} ファイル…';
  @override
  String findingsAcrossFiles({required Object files, required Object count}) =>
      '${files} ファイルにわたり ${count} 件の指摘';
  @override
  String copiedFindings({required Object count}) => '${count} 件の指摘をコピーしました';
  @override
  String get copy => 'コピー';
  @override
  String get noFindings => '実行フローの指摘はありません。';
  @override
  late final _Translations$filament$severity$ja severity =
      _Translations$filament$severity$ja._(_root);
  @override
  late final _Translations$filament$kind$ja kind =
      _Translations$filament$kind$ja._(_root);
  @override
  String lineLabel({required Object line}) => 'L${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$ja extends Translations$history$en {
  _Translations$history$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$ja commitLede =
      _Translations$history$commitLede$ja._(_root);
  @override
  late final _Translations$history$seismograph$ja seismograph =
      _Translations$history$seismograph$ja._(_root);
  @override
  late final _Translations$history$worldline$ja worldline =
      _Translations$history$worldline$ja._(_root);
  @override
  late final _Translations$history$contextMenu$ja contextMenu =
      _Translations$history$contextMenu$ja._(_root);
  @override
  late final _Translations$history$cherryPick$ja cherryPick =
      _Translations$history$cherryPick$ja._(_root);
  @override
  late final _Translations$history$revert$ja revert =
      _Translations$history$revert$ja._(_root);
  @override
  late final _Translations$history$reflog$ja reflog =
      _Translations$history$reflog$ja._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'そのコミットは、読み込まれた ${n} コミットよりも深くにあります。',
      );
  @override
  String deleteTagFailed({required Object error}) => 'タグの削除に失敗しました：${error}';
  @override
  String get loadingTitle => '履歴を読み込み中';
  @override
  String get loadingMessage => '最近のコミットを読み込んでいます。';
  @override
  String get unavailableTitle => '履歴を取得できません';
  @override
  String get toggleWorldline => '世界線を切り替え';
  @override
  String get pageTitle => '履歴';
  @override
  String get viewingLast => '直近を表示中';
  @override
  String get commitsUnit => 'コミット';
  @override
  String get noCommitSelectedTitle => 'コミットが未選択';
  @override
  String get noCommitSelectedMessage => '変更を確認するにはコミットを選択してください。';
  @override
  String get loadingCommitTitle => 'コミットを読み込み中';
  @override
  String get loadingCommitMessage => 'コミットの詳細を読み込んでいます。';
  @override
  String get commitUnavailableTitle => 'コミットを取得できません';
  @override
  String get couldNotLoadCommit => 'コミットを読み込めませんでした。';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'reflog を読み込む';
  @override
  String get createTag => 'タグを作成';
  @override
  String get newTagName => '新しいタグ名';
  @override
  String newTagNameError({required Object error}) => '新しいタグ名 — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイル · 全変更',
      );
  @override
  String get allChangesLabel => '全変更';
  @override
  late final _Translations$history$rebase$ja rebase =
      _Translations$history$rebase$ja._(_root);
  @override
  late final _Translations$history$inFlight$ja inFlight =
      _Translations$history$inFlight$ja._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$ja extends Translations$historySurgery$en {
  _Translations$historySurgery$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$ja chrome =
      _Translations$historySurgery$chrome$ja._(_root);
  @override
  late final _Translations$historySurgery$select$ja select =
      _Translations$historySurgery$select$ja._(_root);
  @override
  late final _Translations$historySurgery$understand$ja understand =
      _Translations$historySurgery$understand$ja._(_root);
  @override
  late final _Translations$historySurgery$confirm$ja confirm =
      _Translations$historySurgery$confirm$ja._(_root);
  @override
  late final _Translations$historySurgery$execute$ja execute =
      _Translations$historySurgery$execute$ja._(_root);
  @override
  late final _Translations$historySurgery$verify$ja verify =
      _Translations$historySurgery$verify$ja._(_root);
  @override
  late final _Translations$historySurgery$forcePush$ja forcePush =
      _Translations$historySurgery$forcePush$ja._(_root);
}

// Path: onboarding
class _Translations$onboarding$ja extends Translations$onboarding$en {
  _Translations$onboarding$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$ja nav =
      _Translations$onboarding$nav$ja._(_root);
  @override
  late final _Translations$onboarding$naming$ja naming =
      _Translations$onboarding$naming$ja._(_root);
  @override
  late final _Translations$onboarding$theme$ja theme =
      _Translations$onboarding$theme$ja._(_root);
  @override
  late final _Translations$onboarding$repo$ja repo =
      _Translations$onboarding$repo$ja._(_root);
  @override
  late final _Translations$onboarding$preview$ja preview =
      _Translations$onboarding$preview$ja._(_root);
}

// Path: orrery
class _Translations$orrery$ja extends Translations$orrery$en {
  _Translations$orrery$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$ja header =
      _Translations$orrery$header$ja._(_root);
  @override
  late final _Translations$orrery$status$ja status =
      _Translations$orrery$status$ja._(_root);
  @override
  late final _Translations$orrery$legend$ja legend =
      _Translations$orrery$legend$ja._(_root);
  @override
  late final _Translations$orrery$node$ja node = _Translations$orrery$node$ja._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$ja milestone =
      _Translations$orrery$milestone$ja._(_root);
  @override
  late final _Translations$orrery$structure$ja structure =
      _Translations$orrery$structure$ja._(_root);
  @override
  late final _Translations$orrery$rail$ja rail = _Translations$orrery$rail$ja._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$ja selection =
      _Translations$orrery$selection$ja._(_root);
  @override
  late final _Translations$orrery$findingKind$ja findingKind =
      _Translations$orrery$findingKind$ja._(_root);
  @override
  late final _Translations$orrery$findings$ja findings =
      _Translations$orrery$findings$ja._(_root);
  @override
  late final _Translations$orrery$anchor$ja anchor =
      _Translations$orrery$anchor$ja._(_root);
  @override
  late final _Translations$orrery$compare$ja compare =
      _Translations$orrery$compare$ja._(_root);
}

// Path: palette
class _Translations$palette$ja extends Translations$palette$en {
  _Translations$palette$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'アクティブ';
  @override
  late final _Translations$palette$prefixes$ja prefixes =
      _Translations$palette$prefixes$ja._(_root);
  @override
  late final _Translations$palette$chips$ja chips =
      _Translations$palette$chips$ja._(_root);
  @override
  late final _Translations$palette$predictive$ja predictive =
      _Translations$palette$predictive$ja._(_root);
  @override
  late final _Translations$palette$topTouched$ja topTouched =
      _Translations$palette$topTouched$ja._(_root);
  @override
  late final _Translations$palette$coherence$ja coherence =
      _Translations$palette$coherence$ja._(_root);
  @override
  late final _Translations$palette$keystone$ja keystone =
      _Translations$palette$keystone$ja._(_root);
  @override
  late final _Translations$palette$repoSub$ja repoSub =
      _Translations$palette$repoSub$ja._(_root);
  @override
  late final _Translations$palette$desks$ja desks =
      _Translations$palette$desks$ja._(_root);
  @override
  late final _Translations$palette$actions$ja actions =
      _Translations$palette$actions$ja._(_root);
  @override
  late final _Translations$palette$tools$ja tools =
      _Translations$palette$tools$ja._(_root);
  @override
  late final _Translations$palette$gitCommands$ja gitCommands =
      _Translations$palette$gitCommands$ja._(_root);
  @override
  late final _Translations$palette$pr$ja pr = _Translations$palette$pr$ja._(
    _root,
  );
  @override
  late final _Translations$palette$ai$ja ai = _Translations$palette$ai$ja._(
    _root,
  );
  @override
  late final _Translations$palette$undo$ja undo =
      _Translations$palette$undo$ja._(_root);
  @override
  late final _Translations$palette$navigation$ja navigation =
      _Translations$palette$navigation$ja._(_root);
  @override
  late final _Translations$palette$settings$ja settings =
      _Translations$palette$settings$ja._(_root);
  @override
  late final _Translations$palette$info$ja info =
      _Translations$palette$info$ja._(_root);
  @override
  late final _Translations$palette$debug$ja debug =
      _Translations$palette$debug$ja._(_root);
  @override
  late final _Translations$palette$dev$ja dev = _Translations$palette$dev$ja._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$ja historySurgery =
      _Translations$palette$historySurgery$ja._(_root);
  @override
  late final _Translations$palette$orrery$ja orrery =
      _Translations$palette$orrery$ja._(_root);
  @override
  late final _Translations$palette$command$ja command =
      _Translations$palette$command$ja._(_root);
  @override
  late final _Translations$palette$search$ja search =
      _Translations$palette$search$ja._(_root);
  @override
  late final _Translations$palette$wick$ja wick =
      _Translations$palette$wick$ja._(_root);
  @override
  late final _Translations$palette$gitCache$ja gitCache =
      _Translations$palette$gitCache$ja._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$ja extends Translations$releaseNotes$en {
  _Translations$releaseNotes$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$ja about =
      _Translations$releaseNotes$about$ja._(_root);
  @override
  late final _Translations$releaseNotes$legal$ja legal =
      _Translations$releaseNotes$legal$ja._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$ja extends Translations$repoSummary$en {
  _Translations$repoSummary$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$ja backbone =
      _Translations$repoSummary$backbone$ja._(_root);
  @override
  late final _Translations$repoSummary$glance$ja glance =
      _Translations$repoSummary$glance$ja._(_root);
  @override
  late final _Translations$repoSummary$heading$ja heading =
      _Translations$repoSummary$heading$ja._(_root);
  @override
  String get historyStarvedCaveat =>
      'ランキングは限定的です：結合グラフにエッジがありませんでした（新規クローンか、コミットが少なすぎます）。ファイル順は構造的中心性ではなくサイズを反映しています。';
  @override
  late final _Translations$repoSummary$pitch$ja pitch =
      _Translations$repoSummary$pitch$ja._(_root);
  @override
  late final _Translations$repoSummary$region$ja region =
      _Translations$repoSummary$region$ja._(_root);
  @override
  late final _Translations$repoSummary$shape$ja shape =
      _Translations$repoSummary$shape$ja._(_root);
}

// Path: review
class _Translations$review$ja extends Translations$review$en {
  _Translations$review$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => '未解決';
  @override
  String get done => '完了';
  @override
  String get ack => '了解';
  @override
  String get reply => '返信';
  @override
  String get pleaseFix => '要修正';
  @override
  String get draft => '下書き';
  @override
  String get engine => 'エンジン';
  @override
  String get moved => '移動';
  @override
  String get yourTurn => 'あなたの番';
  @override
  String get drafts => '下書き';
  @override
  String get publish => '公開';
  @override
  String get discard => '破棄';
  @override
  String get saveDraft => '下書きを保存';
  @override
  String get cancel => 'キャンセル';
  @override
  String get verdictApprove => '承認';
  @override
  String get verdictRequestChanges => '変更を要求';
  @override
  String get verdictComment => 'コメント';
  @override
  String get caughtUp => '最新';
  @override
  String get sinceLastLook => '前回の確認以降';
  @override
  String get fullDiff => '全差分';
  @override
  String get commentHint => 'コメントを書く';
  @override
  String outdatedLastSeen({required Object round}) => '古い · 最終確認 R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => '${who} 待ち';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        one: '前回の確認以降 ${n} 件のファイル',
        other: '前回の確認以降 ${n} 件のファイル',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '未解決 ${n} 件';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        one: '下書き ${n} 件',
        other: '下書き ${n} 件',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'レビューを開始できませんでした: ${error}';
  @override
  String get anchorUnavailable => 'その行はアンカーできません — ファイルが大きすぎるか利用できません。';
  @override
  String reviewActionFailed({required Object error}) =>
      'レビュー操作に失敗しました: ${error}';
  @override
  String get lensTooLarge => 'この比較は大きすぎてここに表示できません — 全差分のままにします。';
  @override
  String get lensEmpty => 'これらのスナップショットの間に変更はありません。';
  @override
  String get reopen => '再オープン';
  @override
  String get notBlocking => '自分待ちを解除';
  @override
  String get markReviewed => '確認済み';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        one: '新しいコメント ${n} 件',
        other: '新しいコメント ${n} 件',
      );
  @override
  String get handTo => '担当を渡す';
}

// Path: settings
class _Translations$settings$ja extends Translations$settings$en {
  _Translations$settings$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$ja language =
      _Translations$settings$language$ja._(_root);
  @override
  late final _Translations$settings$sectionLabels$ja sectionLabels =
      _Translations$settings$sectionLabels$ja._(_root);
  @override
  late final _Translations$settings$errors$ja errors =
      _Translations$settings$errors$ja._(_root);
  @override
  late final _Translations$settings$promptStatus$ja promptStatus =
      _Translations$settings$promptStatus$ja._(_root);
  @override
  late final _Translations$settings$clearData$ja clearData =
      _Translations$settings$clearData$ja._(_root);
  @override
  List<String> get guardrailStageLabels => ['緩め', 'バランス', '厳格', '偏執'];
  @override
  late final _Translations$settings$guardrailMacro$ja guardrailMacro =
      _Translations$settings$guardrailMacro$ja._(_root);
  @override
  late final _Translations$settings$guardrails$ja guardrails =
      _Translations$settings$guardrails$ja._(_root);
  @override
  late final _Translations$settings$appearance$ja appearance =
      _Translations$settings$appearance$ja._(_root);
  @override
  late final _Translations$settings$retention$ja retention =
      _Translations$settings$retention$ja._(_root);
  @override
  late final _Translations$settings$navigation$ja navigation =
      _Translations$settings$navigation$ja._(_root);
  @override
  late final _Translations$settings$behaviour$ja behaviour =
      _Translations$settings$behaviour$ja._(_root);
  @override
  late final _Translations$settings$retentionClear$ja retentionClear =
      _Translations$settings$retentionClear$ja._(_root);
  @override
  late final _Translations$settings$channels$ja channels =
      _Translations$settings$channels$ja._(_root);
  @override
  late final _Translations$settings$pollResult$ja pollResult =
      _Translations$settings$pollResult$ja._(_root);
  @override
  late final _Translations$settings$keybindingProfile$ja keybindingProfile =
      _Translations$settings$keybindingProfile$ja._(_root);
  @override
  late final _Translations$settings$apiKeys$ja apiKeys =
      _Translations$settings$apiKeys$ja._(_root);
  @override
  late final _Translations$settings$shortcuts$ja shortcuts =
      _Translations$settings$shortcuts$ja._(_root);
  @override
  late final _Translations$settings$toggles$ja toggles =
      _Translations$settings$toggles$ja._(_root);
  @override
  late final _Translations$settings$diffDiffability$ja diffDiffability =
      _Translations$settings$diffDiffability$ja._(_root);
  @override
  late final _Translations$settings$modelSlots$ja modelSlots =
      _Translations$settings$modelSlots$ja._(_root);
  @override
  late final _Translations$settings$modelPicker$ja modelPicker =
      _Translations$settings$modelPicker$ja._(_root);
  @override
  late final _Translations$settings$aiFeatures$ja aiFeatures =
      _Translations$settings$aiFeatures$ja._(_root);
  @override
  late final _Translations$settings$commitEditor$ja commitEditor =
      _Translations$settings$commitEditor$ja._(_root);
  @override
  late final _Translations$settings$review$ja review =
      _Translations$settings$review$ja._(_root);
  @override
  late final _Translations$settings$museHint$ja museHint =
      _Translations$settings$museHint$ja._(_root);
  @override
  late final _Translations$settings$museEditor$ja museEditor =
      _Translations$settings$museEditor$ja._(_root);
  @override
  late final _Translations$settings$museStage$ja museStage =
      _Translations$settings$museStage$ja._(_root);
  @override
  late final _Translations$settings$lensAxis$ja lensAxis =
      _Translations$settings$lensAxis$ja._(_root);
  @override
  late final _Translations$settings$logosLens$ja logosLens =
      _Translations$settings$logosLens$ja._(_root);
  @override
  late final _Translations$settings$sortGuide$ja sortGuide =
      _Translations$settings$sortGuide$ja._(_root);
  @override
  late final _Translations$settings$piggyback$ja piggyback =
      _Translations$settings$piggyback$ja._(_root);
  @override
  late final _Translations$settings$diffStage$ja diffStage =
      _Translations$settings$diffStage$ja._(_root);
  @override
  late final _Translations$settings$undoScope$ja undoScope =
      _Translations$settings$undoScope$ja._(_root);
  @override
  late final _Translations$settings$undoWindow$ja undoWindow =
      _Translations$settings$undoWindow$ja._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$ja guardrailPhrase =
      _Translations$settings$guardrailPhrase$ja._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$ja reviewGuideHint =
      _Translations$settings$reviewGuideHint$ja._(_root);
  @override
  late final _Translations$settings$commitFormat$ja commitFormat =
      _Translations$settings$commitFormat$ja._(_root);
  @override
  late final _Translations$settings$commitPreview$ja commitPreview =
      _Translations$settings$commitPreview$ja._(_root);
  @override
  late final _Translations$settings$externalTools$ja externalTools =
      _Translations$settings$externalTools$ja._(_root);
  @override
  late final _Translations$settings$apiUsage$ja apiUsage =
      _Translations$settings$apiUsage$ja._(_root);
  @override
  late final _Translations$settings$gitea$ja gitea =
      _Translations$settings$gitea$ja._(_root);
  @override
  late final _Translations$settings$wick$ja wick =
      _Translations$settings$wick$ja._(_root);
  @override
  late final _Translations$settings$integrations$ja integrations =
      _Translations$settings$integrations$ja._(_root);
  @override
  late final _Translations$settings$reduceMotion$ja reduceMotion =
      _Translations$settings$reduceMotion$ja._(_root);
  @override
  late final _Translations$settings$resetQuit$ja resetQuit =
      _Translations$settings$resetQuit$ja._(_root);
  @override
  late final _Translations$settings$diagnostics$ja diagnostics =
      _Translations$settings$diagnostics$ja._(_root);
  @override
  late final _Translations$settings$telemetry$ja telemetry =
      _Translations$settings$telemetry$ja._(_root);
  @override
  late final _Translations$settings$flowEngine$ja flowEngine =
      _Translations$settings$flowEngine$ja._(_root);
  @override
  late final _Translations$settings$museStrands$ja museStrands =
      _Translations$settings$museStrands$ja._(_root);
  @override
  late final _Translations$settings$cliPiggyback$ja cliPiggyback =
      _Translations$settings$cliPiggyback$ja._(_root);
  @override
  late final _Translations$settings$header$ja header =
      _Translations$settings$header$ja._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$ja diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$ja._(_root);
  @override
  late final _Translations$settings$release$ja release =
      _Translations$settings$release$ja._(_root);
  @override
  late final _Translations$settings$providerStatus$ja providerStatus =
      _Translations$settings$providerStatus$ja._(_root);
  @override
  late final _Translations$settings$meridiem$ja meridiem =
      _Translations$settings$meridiem$ja._(_root);
  @override
  late final _Translations$settings$offenders$ja offenders =
      _Translations$settings$offenders$ja._(_root);
}

// Path: sync
class _Translations$sync$ja extends Translations$sync$en {
  _Translations$sync$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$ja actions =
      _Translations$sync$actions$ja._(_root);
  @override
  late final _Translations$sync$panel$ja panel = _Translations$sync$panel$ja._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$ja forcePush =
      _Translations$sync$forcePush$ja._(_root);
}

// Path: xray
class _Translations$xray$ja extends Translations$xray$en {
  _Translations$xray$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$ja board = _Translations$xray$board$ja._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$ja cadence =
      _Translations$xray$cadence$ja._(_root);
  @override
  late final _Translations$xray$cards$ja cards = _Translations$xray$cards$ja._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$ja cardTitle =
      _Translations$xray$cardTitle$ja._(_root);
  @override
  late final _Translations$xray$grain$ja grain = _Translations$xray$grain$ja._(
    _root,
  );
  @override
  late final _Translations$xray$header$ja header =
      _Translations$xray$header$ja._(_root);
  @override
  late final _Translations$xray$hotspot$ja hotspot =
      _Translations$xray$hotspot$ja._(_root);
  @override
  late final _Translations$xray$inspector$ja inspector =
      _Translations$xray$inspector$ja._(_root);
  @override
  late final _Translations$xray$loadingCard$ja loadingCard =
      _Translations$xray$loadingCard$ja._(_root);
  @override
  late final _Translations$xray$metabolism$ja metabolism =
      _Translations$xray$metabolism$ja._(_root);
  @override
  late final _Translations$xray$multi$ja multi = _Translations$xray$multi$ja._(
    _root,
  );
  @override
  late final _Translations$xray$recency$ja recency =
      _Translations$xray$recency$ja._(_root);
  @override
  late final _Translations$xray$rings$ja rings = _Translations$xray$rings$ja._(
    _root,
  );
  @override
  late final _Translations$xray$stats$ja stats = _Translations$xray$stats$ja._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$ja stratumLabel =
      _Translations$xray$stratumLabel$ja._(_root);
  @override
  late final _Translations$xray$summary$ja summary =
      _Translations$xray$summary$ja._(_root);
  @override
  late final _Translations$xray$tabs$ja tabs = _Translations$xray$tabs$ja._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$ja trajectory =
      _Translations$xray$trajectory$ja._(_root);
  @override
  late final _Translations$xray$verdict$ja verdict =
      _Translations$xray$verdict$ja._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$ja extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'キーボード';
  @override
  String get sectionNavigate => '移動';
  @override
  String get sectionStaging => 'ステージング';
  @override
  String get sectionBranchesPrs => 'ブランチ＆PR';
  @override
  String get changes => '変更';
  @override
  String get history => '履歴';
  @override
  String get branches => 'ブランチ';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => '切り替え（常時）';
  @override
  String get commandPalette => 'コマンドパレット';
  @override
  String get elevatedPalette => '昇格パレット';
  @override
  String get dismiss => '閉じる';
  @override
  String get refresh => '更新';
  @override
  String get nextPrevChange => '次／前の変更';
  @override
  String get toggleLine => '行を切り替え';
  @override
  String get toggleHunk => 'ハンクを切り替え';
  @override
  String get toggleFile => 'ファイルを切り替え';
  @override
  String get pinContext => '文脈をピン留め';
  @override
  String get commit => 'コミット';
  @override
  String get acceptAiHint => 'AI のヒントを採用';
  @override
  String get undo => '取り消し';
  @override
  String get navigate => '移動';
  @override
  String get expand => '展開';
  @override
  String get checkoutPr => 'PR をチェックアウト';
  @override
  String get approve => '承認';
  @override
  String get requestChanges => '変更を要求';
  @override
  String profileSwitchHint({required Object profile}) =>
      '${profile}プロファイル · 設定で切り替え';
}

// Path: backend.ops
class _Translations$backend$ops$ja extends Translations$backend$ops$en {
  _Translations$backend$ops$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'マージ';
  @override
  String get pull => 'プル';
  @override
  String get apply => '適用';
  @override
  String get switchOp => '切り替え';
  @override
  String get sync => '同期';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$ja
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op}をキャンセルしました。';
  @override
  String complete({required Object op}) => '${op}が完了しました。';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'コンフリクトが ${n} 件残っています。変更ページで解決してください。',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'コンフリクトを ${n} 件解決しました。',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイルに未コミットの編集があります。先にコミットしてください。',
      );
}

// Path: changes.usage
class _Translations$changes$usage$ja extends Translations$changes$usage$en {
  _Translations$changes$usage$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '入力 ${input} · 出力 ${output}';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '入力 ${fresh} · キャッシュ ${cached} · 出力 ${out}';
  @override
  String get inWord => '入力';
  @override
  String get cachedWord => 'キャッシュ';
  @override
  String get outWord => '出力';
  @override
  String tipIn({required Object value}) => '${value}  入力';
  @override
  String tipCacheRead({required Object value}) => '${value}  キャッシュ読み取り';
  @override
  String tipCacheWrite({required Object value}) => '${value}  キャッシュ書き込み';
  @override
  String tipOut({required Object value}) => '${value}  出力';
  @override
  String tipReasoning({required Object value}) => '${value}  推論';
  @override
  String tipWallClock({required Object value}) => '${value}秒  実時間';
}

// Path: changes.tabs
class _Translations$changes$tabs$ja extends Translations$changes$tabs$en {
  _Translations$changes$tabs$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => '変更';
  @override
  String get empty => '空';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$ja
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => '新しい差分タブ';
}

// Path: changes.select
class _Translations$changes$select$ja extends Translations$changes$select$en {
  _Translations$changes$select$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'すべて選択';
  @override
  String get deselectAll => 'すべて選択解除';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$ja
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'リストに戻る';
  @override
  String get atlas => 'アトラス、コミット候補を見る';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$ja
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\n${anchor}と結合 · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$ja extends Translations$changes$minimap$en {
  _Translations$changes$minimap$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => '新規';
  @override
  String get roleBridge => '橋';
  @override
  String get roleHub => 'ハブ';
  @override
  String get roleLeaf => '葉';
  @override
  String get roleConnected => '接続済み';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => '${name}と共に変わる';
  @override
  String get newFile => '新規ファイル';
  @override
  String nearOtherChanges({required Object dir, required Object count}) =>
      '${dir} 内の他 ${count} 件の変更の近く';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name}は通常このファイルと共に変わります';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$ja
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'タグ…';
}

// Path: changes.composer
class _Translations$changes$composer$ja
    extends Translations$changes$composer$en {
  _Translations$changes$composer$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'コミットメッセージ…';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$ja extends Translations$changes$commit$en {
  _Translations$changes$commit$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => '変更をコミット';
  @override
  String get primaryCommitChangesDetail => '分離 HEAD：同期せずにローカルでコミットします。';
  @override
  String get primaryPublish => 'コミット＆公開';
  @override
  String get primaryPublishDetail => 'コミットを作成し、このブランチを一度に公開します。';
  @override
  String get primarySync => 'コミット＆同期';
  @override
  String get primarySyncDetail => 'コミットを作成し、ブランチを調整して送り出します。';
  @override
  String get primaryPush => 'コミット＆プッシュ';
  @override
  String get primaryPushDetail => 'コミットを作成し、すぐにプッシュします。';
  @override
  String get amendLast => '直前のコミットをアメンド';
  @override
  String amendAnd({required Object action}) => 'アメンド＆${action}';
  @override
  String get chooseFile => '次のコミットに少なくとも 1 ファイルを選んでください。';
  @override
  String get writeMessage => '先にコミットメッセージを書いてください。';
  @override
  String get committing => 'コミット中';
  @override
  String get committingSync => 'コミットして同期中';
  @override
  String get committed => 'コミットしました。';
  @override
  String get undoFailed => '取り消しに失敗しました。';
  @override
  String get working => '処理中…';
  @override
  String get commitOnly => 'コミットのみ';
  @override
  String get noRuntimeModels => 'コミットメッセージに使えるランタイム検出モデルがありません。';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\n除外ファイルのステージを復元できませんでした。再試行の前にインデックスを確認してください。';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      '${summary}をコミットしました（${hash}）。';
  @override
  String get restoreFailedSync =>
      '除外ファイルの選択を再ステージできませんでした。同期はスキップされました。同期の前にインデックスを確認してください。';
  @override
  String get noModelLabel => 'モデルなし';
  @override
  String get chooseBeforeGenerate => '生成の前に少なくとも 1 ファイルを選んでください。';
  @override
  String get aiUnavailable => 'コミットメッセージ AI はまだ利用できません。';
  @override
  String get generateFailed => '生成に失敗しました。';
  @override
  String get stageFailed => 'ファイルのステージに失敗しました。';
  @override
  String get commitFailed => 'コミットに失敗しました。';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => '${summary}をコミットし（${hash}）、${operation}を実行しました。';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
    n,
    other: '${summary}をコミットしました（${hash}）。コンフリクトを ${n} 件解決しました。',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '解決すべきコンフリクトが ${n} 件残っています。',
      );
  @override
  String syncBlocked({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'コミットは成功しましたが、未コミットのファイル ${n} 件により同期がブロックされました。',
      );
  @override
  String syncStalled({required Object message}) =>
      'コミットは成功しましたが、同期が停滞しました：${message}';
  @override
  String syncFailed({required Object message}) =>
      'コミットは成功しましたが、同期に失敗しました：${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$ja extends Translations$changes$rebase$en {
  _Translations$changes$rebase$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'リベースを続行できませんでした。';
}

// Path: changes.editor
class _Translations$changes$editor$ja extends Translations$changes$editor$en {
  _Translations$changes$editor$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'エディターを閉じる';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$ja
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    '親愛なる git log へ',
    'コミットせよ、我に安らぎを…',
    'この瞬間に名前を',
    'さあ、語って',
    '話せ！',
    'お前の母はぶら下がり参照、父はセミコロン臭かった',
  ];
  @override
  List<String> get short => [
    'おや？',
    'やあ:)',
    'ところで：',
    'ひとこと',
    '丁寧に言うと',
    'メモを残して',
    '何か言いかけた？',
    'そうそう、吐き出して',
  ];
  @override
  List<String> get mid => [
    '記録のために',
    '未来の自分に伝えて',
    'でもその前に？',
    'どうだった',
    '自分の言葉で',
    'え、何したって？',
    'しかと承った',
    '聞いているよ',
  ];
  @override
  List<String> get long => [
    'あなたの夢を、どうぞ',
    '何かいいことを',
    '…そして私はこう言った：',
    '後世が待っている',
    'たくさん書くとバグが消える',
    'おお、すごい',
    '聖なる書',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$ja extends Translations$changes$askHint$en {
  _Translations$changes$askHint$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) => 'ラウンド ${n} — 絞り込むか、文脈を追加。';
  @override
  String get symptom => '症状を記述。';
  @override
  String get broken => '何が壊れている？';
  @override
  String get bug => 'バグを記述。';
  @override
  String get error => 'エラーを貼り付け。';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$ja
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => '波及';
  @override
  String get includeCoChanges => '共変更を含める';
  @override
  String deleteFile({required Object name}) => '${name}を削除…';
  @override
  String discardChangesTo({required Object name}) => '${name}への変更を破棄…';
  @override
  String get ignore => '無視';
  @override
  String get diffTabFromSelection => '選択から差分タブ';
  @override
  String addSelectedToTab({required Object name}) => '選択を${name}に追加';
  @override
  String diffTabFromFile({required Object name}) => '${name}から差分タブ';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      '${file}を${tab}に追加';
  @override
  String get copyFilePath => 'ファイルパスをコピー';
  @override
  String get showInExplorer => 'エクスプローラーで表示';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$ja
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => '密に結合';
  @override
  String get cohesionLoose => '緩やかに関連';
  @override
  String get cohesionScattered => '構造的に散在';
  @override
  String get clusterOne => 'すべて一つのクラスター';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      '${count} クラスターにまたがる（${parts} ファイル）';
  @override
  String clusterSpans({required Object count}) => '${count} クラスターにまたがる';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} ファイル · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file}は通常このグループと共に変わります';
  @override
  String get splitToNewTab => '新しいタブに分割';
  @override
  String copyPaths({required Object count}) => '${count} 件のパスをコピー';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$ja
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => '.${ext} 拡張子';
  @override
  String allSelected({required Object count}) => '選択中の ${count} 件すべて';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '含まれる ${n} ファイルと結合',
      );
  @override
  String get updateFailed => '.gitignore の更新に失敗しました。';
}

// Path: changes.discard
class _Translations$changes$discard$ja extends Translations$changes$discard$en {
  _Translations$changes$discard$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '${name}を削除しますか？';
  @override
  String discardTitle({required Object name}) => '${name}への変更を破棄しますか？';
  @override
  String deleteBody({required Object path}) =>
      '${path}がディスクから削除されます。アプリ内からは元に戻せません。';
  @override
  String discardBody({required Object path}) =>
      '${path}へのすべての変更が HEAD の状態に戻されます。元に戻せません。';
  @override
  String get discard => '破棄';
  @override
  String deletingFile({required Object name}) => '${name}を削除中';
  @override
  String discardingFile({required Object name}) => '${name}を破棄中';
  @override
  String get discardFailed => '変更の破棄に失敗しました。';
  @override
  String discardManyTitle({required Object count}) =>
      '${count} ファイルへの変更を破棄しますか？';
  @override
  String get discardManyBody =>
      '追跡中のファイルは HEAD の状態に戻され、追跡外のファイルはディスクから削除されます。元に戻せません。';
  @override
  String discardManyConfirm({required Object count}) => '${count} 件を破棄';
  @override
  String discardingManyFiles({required Object count}) => '${count} ファイルを破棄中';
  @override
  String failedOpenExplorer({required Object error}) =>
      'ファイルエクスプローラーを開けませんでした：${error}';
  @override
  String get someFailed => '一部の破棄に失敗しました。';
}

// Path: changes.snack
class _Translations$changes$snack$ja extends Translations$changes$snack$en {
  _Translations$changes$snack$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => '同じ作業ツリー — 移すものがありません。';
  @override
  String diffFailed({required Object error}) => '差分に失敗しました：${error}';
  @override
  String get deskEmpty => 'Desk にはあなたより先行するものがありません — 空の移動です。';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) => '棚の読み込みに失敗しました：${error}';
  @override
  String get shelfEmpty => '空の棚 — 移すものがありません。';
  @override
  String sourceShelf({required Object label}) => '棚 ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      '「${label}」に設定されたモデルがありません。';
  @override
  String fetchFailed({required Object error}) => 'フェッチに失敗しました：${error}';
}

// Path: changes.trace
class _Translations$changes$trace$ja extends Translations$changes$trace$en {
  _Translations$changes$trace$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '検証トレース';
  @override
  String get draftReview => 'レビューの下書き';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$ja
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '作業ツリーはクリーン';
  @override
  String get subtitle => 'ステージ済み・未ステージの変更は検出されませんでした。';
  @override
  String get noUpstream => '  ·  上流なし';
  @override
  String get ahead => ' 先行';
  @override
  String get behind => ' 遅延';
  @override
  String get refreshing => '更新中…';
  @override
  String get refresh => '更新';
  @override
  String get check => 'チェック';
  @override
  String get checkTooltip => 'フェッチしてローカルを更新。';
  @override
  String get sync => '＆同期';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$ja
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '緩め';
  @override
  String get balanced => 'バランス';
  @override
  String get strict => '厳格';
  @override
  String get paranoid => '偏執';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$ja
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf => 'ドロップしてこの棚の変更をここに取り込む';
  @override
  String get fromDesk => 'ドロップしてこの Desk の変更をここに取り込む';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$ja
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'ファイルが未選択';
  @override
  String get message => '差分を確認するには変更されたファイルを選択してください。';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$ja
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ ${count} 件を棚上げ';
  @override
  String get shelve => '↓ 棚上げ';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} 件棚上げ ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$ja
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => '取り出す';
  @override
  String get peek => '覗く';
  @override
  String get toss => '捨てる';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$ja
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get reading => '棚を読み込み中…';
  @override
  String get empty => '空の棚';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$ja
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$ja extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'ステージ済みの行のみコミット';
  @override
  String get doubleClickToggle => 'ダブルクリック：グループ全体を切り替え';
  @override
  String get repoRoot => 'リポジトリのルート';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$ja
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイルを読み込み中 · 解決を作成中…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${files} にわたるコンフリクト ${n} 件',
      );
  @override
  String get resolve => '解決';
  @override
  String get orWith => 'または';
  @override
  String resolveWith({required Object label}) => '${label}で解決';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      '${label}で解決  ·  ${model}';
  @override
  String get resolving => '解決中…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  ${label}で解決';
  @override
  String get orWithAnother => 'または別のモデルで';
}

// Path: changes.badge
class _Translations$changes$badge$ja extends Translations$changes$badge$en {
  _Translations$changes$badge$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'ステージ済み編集';
  @override
  String get edited => '編集済み';
  @override
  String get stagedAdd => 'ステージ済み追加';
  @override
  String get added => '追加済み';
  @override
  String get stagedDelete => 'ステージ済み削除';
  @override
  String get deleted => '削除済み';
  @override
  String get stagedRename => 'ステージ済みリネーム';
  @override
  String get renamed => 'リネーム済み';
  @override
  String get stagedCopy => 'ステージ済みコピー';
  @override
  String get copied => 'コピー済み';
  @override
  String get conflict => 'コンフリクト';
  @override
  String get stagedTypeChange => 'ステージ済み型変更';
  @override
  String get typeChanged => '型変更済み';
  @override
  String get untracked => '追跡外';
}

// Path: changes.review
class _Translations$changes$review$ja extends Translations$changes$review$en {
  _Translations$changes$review$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'コードレビュー';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '含まれる ${n} ファイル',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ハンク',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'レビューを取得できません';
  @override
  String get backToDiff => '差分に戻る';
  @override
  String get verified => '検証済み';
  @override
  String get draftOnly => '下書きのみ';
  @override
  String get runAgain => '再実行';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} 下にレビューの下書きを表示します。';
  @override
  String get hideTrace => 'トレースを隠す';
  @override
  String get showTrace => 'トレースを表示';
  @override
  String get showVerificationTrace => '検証トレースを表示';
  @override
  String get whyLanded => 'このレビューがここに至った理由';
  @override
  String get noFindings => '指摘なし';
  @override
  String get findings => '指摘';
  @override
  String get noEvidenceIssues => 'このコミット範囲で、証拠に裏付けられた問題は見つかりませんでした。';
  @override
  String get observations => '所見';
  @override
  String get chooseBeforeReview => 'レビューの前に少なくとも 1 ファイルを選んでください。';
  @override
  String get aiUnavailable => 'レビュー AI はまだ利用できません。';
  @override
  String get failed => 'レビューに失敗しました。';
  @override
  String get noRuntimeModels => 'コミットレビューに使えるランタイム検出モデルがありません。';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$ja
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => '切り替え：${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$ja
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => '${cat}で質問中…';
  @override
  String askWith({required Object cat}) => '${cat}で質問';
  @override
  String get noModel => 'AI モデルが設定されていません';
  @override
  String nextTooltip({required Object cat}) => '次：${cat}  ·  shift クリックで前へ';
  @override
  String get onlyOne => 'AI カテゴリが一つしか設定されていません';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$ja extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({required num n, required Object pct}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${pct}% デジャヴ — 破棄されたタイムラインからの ${n} 本のゴーストエッジがこの差分に触れています',
      );
  @override
  String get label => 'デジャヴ';
}

// Path: changes.identity
class _Translations$changes$identity$ja
    extends Translations$changes$identity$en {
  _Translations$changes$identity$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'コミットの識別情報が設定されていません';
  @override
  String asName({required Object name}) => '${name}として';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      '${name} <${email}> として';
  @override
  String asNameSpace({required Object name}) => '${name} として';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\nこのリポジトリでの最初のコミット';
  @override
  String get newToRepo => '\nこのリポジトリは初めて';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$ja
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get message => '実行後に選択が変わりました';
  @override
  String get rerun => '再実行';
}

// Path: changes.finding
class _Translations$changes$finding$ja extends Translations$changes$finding$en {
  _Translations$changes$finding$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => '差分を開く';
  @override
  String get recorded => '記録済み';
  @override
  String get dismiss => '閉じる';
}

// Path: changes.muse
class _Translations$changes$muse$ja extends Translations$changes$muse$en {
  _Translations$changes$muse$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'あなたが引き出した';
  @override
  String fromIdea({required Object text}) => 'アイデアから：「${text}」';
  @override
  String get foothold => '足がかり — ';
  @override
  String get brainstormSpew => 'ブレインストームの噴出';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => '${count} 件をコピー';
  @override
  String get clear => 'クリア';
  @override
  String get chooseBeforeMuse => 'Muse を呼ぶ前に少なくとも 1 ファイルを選んでください。';
  @override
  String get aiUnavailable => 'Muse AI はまだ利用できません。';
  @override
  String get failed => 'Muse に失敗しました。';
  @override
  String get noRuntimeModels => 'Muse に使えるランタイム検出モデルがありません。';
  @override
  String get needsModel => 'Muse には少なくとも 1 つの設定済みモデルが必要です。';
  @override
  String get dreaming => 'Muse が夢を見ています…';
}

// Path: changes.debug
class _Translations$changes$debug$ja extends Translations$changes$debug$en {
  _Translations$changes$debug$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'デバッグ';
  @override
  String round({required Object n}) => '· ラウンド ${n}';
  @override
  String get clear => 'クリア';
  @override
  String get close => '閉じる';
  @override
  String get analyzing => '症状を解析中…';
  @override
  String get describeSymptom => '症状を記述してデバッグを押してください。';
  @override
  String get evidenceFor => '根拠';
  @override
  String get evidenceAgainst => 'しかし';
  @override
  String get narrowDown => '絞り込みに役立つもの：';
  @override
  String get failed => 'デバッグに失敗しました。';
  @override
  String get refinementFailed => 'デバッグの絞り込みに失敗しました。';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$ja
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'なし';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} 件ステージ済み';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '全 ${n} ファイル${staged}',
      );
  @override
  String partial({
    required Object n,
    required Object count,
    required Object staged,
  }) => '${n} 件中 ${count}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      '全 ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$ja extends Translations$changes$status$en {
  _Translations$changes$status$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'リポジトリの状態を取得できません';
  @override
  String get loadingTitle => 'リポジトリの状態を読み込み中';
  @override
  String get loadingMessage => '作業ツリーを読み込んでいます。';
}

// Path: changes.stash
class _Translations$changes$stash$ja extends Translations$changes$stash$en {
  _Translations$changes$stash$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'スタッシュをコンフリクト付きで適用しました — 変更ページで解決してください（スタッシュエントリは保持されました）。';
  @override
  String get couldNotPop => 'スタッシュを取り出せませんでした。';
  @override
  String get listChanged => 'スタッシュリストが変わりました。破棄をスキップしました。もう一度お試しください。';
  @override
  String get droppingStash => 'スタッシュを破棄中';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$ja
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'コミットメッセージを生成中…';
  @override
  String get commitPreparing => 'コミットメッセージを準備中…';
  @override
  String get commitSelectFile => 'コミットメッセージを生成するには少なくとも 1 ファイルを選んでください。';
  @override
  String get commitConfigure => 'コミットメッセージは 設定 > 挙動のダイナミクス > コミットメッセージ で設定します。';
  @override
  String get fastFallback => '高速';
  @override
  String commitGenerateWith({required Object label}) =>
      '${label}モデルでコミットメッセージを生成';
  @override
  String get museConsulting => 'Muse に相談中…';
  @override
  String get showMuse => 'Muse を表示';
  @override
  String get museSelectFile => 'Muse のために少なくとも 1 ファイルを選んでください。';
  @override
  String get showMuseError => 'Muse のエラーを表示';
  @override
  String get museAsk => 'Muse に方向性を尋ねる';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'Muse に方向性を尋ねる\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => '品質';
  @override
  String get reviewing => 'レビュー中…';
  @override
  String get showReview => 'レビューを表示';
  @override
  String get reviewPreparing => 'コミットレビューを準備中…';
  @override
  String get reviewSelectFile => 'レビューするには少なくとも 1 ファイルを選んでください。';
  @override
  String get reviewConfigure => 'レビュー AI は設定で構成します。';
  @override
  String get viewingReview => 'レビューを表示中';
  @override
  String reviewWith({required Object label, required Object guardrail}) =>
      '${label}モデルで${guardrail}レビュー';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$ja
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'あなたの側';
  @override
  String get resolutionTheirs => '相手の側';
  @override
  String get resolutionCustom => 'カスタム';
  @override
  String get keepBoth => '両方を保持';
  @override
  late final _Translations$changes$mergeEditor$trust$ja trust =
      _Translations$changes$mergeEditor$trust$ja._(_root);
  @override
  String get allResolved => 'すべて解決';
  @override
  String get resolveEasy => '簡単なコンフリクトを解決';
  @override
  String get base => 'ベース';
  @override
  String get cancel => 'キャンセル';
  @override
  String get save => '保存';
  @override
  String get complete => '完了';
  @override
  String get nextFile => '次のファイル';
  @override
  String get edit => '編集';
  @override
  String get auto => '自動';
  @override
  String get undo => '取り消し';
  @override
  late final _Translations$changes$mergeEditor$keyHints$ja keyHints =
      _Translations$changes$mergeEditor$keyHints$ja._(_root);
  @override
  String get favoredTooltip => '結合解析により構造的に優先';
  @override
  String get newOnBothSides => '（両側とも新規）';
  @override
  String writeFailed({required Object error}) =>
      '解決したファイルの書き込みに失敗しました：${error}';
  @override
  String neighborsCoChanged({required Object total, required Object changed}) =>
      '${total} 件中 ${changed} 件の隣接が共変更';
  @override
  String integrity({required Object pct}) => '整合性 ${pct}%';
  @override
  String reviewer({required Object name}) => 'レビュアー：${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$ja
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      '「${category}」に設定されたモデルがありません。設定 → AI で設定してください。';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件の機微なファイルをスキップしました — 手動で解決してください。',
      );
  @override
  String get couldNotReadFiles => 'コンフリクトしたファイルを一つも読み込めませんでした。';
  @override
  String blockedSecret({required Object secret}) =>
      'ブロックしました — コンフリクトしたファイルに ${secret} が含まれているようです。手動で解決してください。';
  @override
  String resolutionFailed({required Object error}) => '解決に失敗しました：${error}';
  @override
  String mergeResolutionLabel({
    required Object total,
    required Object resolved,
    required Object category,
  }) => '◇ マージ解決 · ${total} ファイル中 ${resolved} · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object files,
    required Object conflicts,
  }) => '${op} · ${files} にわたる ${conflicts}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件のコンフリクト',
      );
  @override
  String get mergeEditorButton => '⇋ マージエディター';
  @override
  String get noAiModel => 'AI モデルなし';
  @override
  String get later => 'あとで';
  @override
  String get discard => '破棄';
  @override
  String get resolveWithAi => '◇ AI で解決';
  @override
  String get otherModel => '別のモデル';
  @override
  String withModel({required Object model}) => '${model}で';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$ja
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$ja op =
      _Translations$changes$mergeFlow$op$ja._(_root);
  @override
  String get pushFailed => 'プッシュに失敗しました';
  @override
  String get rebasedAndPushed => 'リベースしてプッシュしました。';
  @override
  String switchedTo({required Object name}) => '${name}に切り替えました。';
  @override
  String get switchFailed => '切り替えに失敗しました。';
  @override
  String switchedToCarried({required Object name}) =>
      '${name}に切り替えました（変更を引き継ぎました）。';
  @override
  String get alreadyUpToDate => 'すでに最新です。';
  @override
  String merged({required Object upstream, required Object n}) =>
      '${upstream}をマージしました（${n} ファイル）。';
  @override
  String get rebaseNotConverge => 'リベースが収束しませんでした — 手動で解決してください。';
  @override
  String get rebased => 'リベースしました。';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'リベースしました（${n} ファイルを解決）。',
      );
  @override
  String get detachedHead => '同期できません：分離 HEAD の状態です。まずブランチをチェックアウトしてください。';
  @override
  String get publishFailed => '公開に失敗しました。';
  @override
  String get noRemote => 'リモートが設定されていません。このブランチを公開するには追加してください。';
  @override
  String get failed => '失敗';
}

// Path: changes.constellation
class _Translations$changes$constellation$ja
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => '構造';
  @override
  String get axisCoChange => '共変更';
  @override
  String get axisSpectralProfile => 'スペクトルプロファイル';
  @override
  String get axisPathSiblings => 'パスの兄弟';
  @override
  String get axisDiffStructure => '差分構造';
  @override
  String get axisSpectral => 'スペクトル';
  @override
  String get titleUnsorted => '未整列';
  @override
  String get titleSingleton => '単独';
  @override
  String get titleMixed => '混在';
  @override
  String get untie => 'ほどく';
  @override
  String get bind => '結ぶ';
  @override
  String get emptyClusters => 'まだクラスターがありません';
}

// Path: common.time
class _Translations$common$time$ja extends Translations$common$time$en {
  _Translations$common$time$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get now => '今';
  @override
  String get justNow => 'たった今';
  @override
  String get today => '今日';
  @override
  String minutesAgo({required Object n}) => '${n} 分前';
  @override
  String hoursAgo({required Object n}) => '${n} 時間前';
  @override
  String daysAgo({required Object n}) => '${n} 日前';
  @override
  String weeksAgo({required Object n}) => '${n} 週間前';
  @override
  String monthsAgo({required Object n}) => '${n} か月前';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        one: '${n} 年前',
        other: '${n} 年前',
      );
  @override
  String minutesShort({required Object n}) => '${n}分';
  @override
  String hoursShort({required Object n}) => '${n}時間';
  @override
  String daysShort({required Object n}) => '${n}日';
  @override
  String weeksShort({required Object n}) => '${n}週';
  @override
  String monthsShort({required Object n}) => '${n}か月';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        one: '${n}年',
        other: '${n}年',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}か月';
  @override
  String get idle => '停滞';
  @override
  String idleDays({required Object n}) => '停滞 ${n} 日';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '停滞 ${n} 年',
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
class _Translations$common$size$ja extends Translations$common$size$en {
  _Translations$common$size$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

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
class _Translations$diff$status$ja extends Translations$diff$status$en {
  _Translations$diff$status$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => '差分を読み込み中';
  @override
  String get loadingMessage => 'ファイルの変更を読み込んでいます。';
  @override
  String get unavailableTitle => '差分を取得できません';
  @override
  String get noChangesTitle => '変更なし';
  @override
  String get noChangesMessage => 'このファイルには表示する差分がありません。';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$ja extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => '差分を検索…';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 行',
      );
  @override
  String get blameLoading => 'ブレーム…';
  @override
  String get blame => 'ブレーム';
  @override
  String get wearMapOn => '摩耗 · オン';
  @override
  String get wearMapOnHint => '摩耗マップ表示中 — クリックで非表示';
  @override
  String get wearMapOffHint => '摩耗マップを表示（アクティビティのヒートマップ）';
  @override
  String get trailBadge => '· トレイル';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$ja
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => '変更ブロックへジャンプ。Git ではこれをハンクと呼びます。';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件の変更',
      );
}

// Path: diff.trail
class _Translations$diff$trail$ja extends Translations$diff$trail$en {
  _Translations$diff$trail$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'トレイルを読み込み中…';
  @override
  String get noHistory => '履歴が見つかりません';
  @override
  String get nowWorkingCopy => '現在 · 作業コピー';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$ja extends Translations$diff$pinned$en {
  _Translations$diff$pinned$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'ピン留めした文脈を読み込み中';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'シグナル';
  @override
  String get echoesTitle => 'エコー';
  @override
  String get technicalLedger => '技術台帳';
  @override
  String get noSecondaryCues => '副次的な手がかりは検出されませんでした。';
  @override
  String get linkedPaths => 'リンクされたパス';
  @override
  String moreCount({required Object n}) => '+${n} 件';
  @override
  String get localSeam => 'ローカルの継ぎ目';
  @override
  String get sharedOwnership => '共有された所有';
  @override
  String get historyWarmingUp => '履歴を準備中';
  @override
  String echoesTotal({required Object n}) => '合計 ${n} 件';
  @override
  String get noEchoes => 'この差分にエコーはありません。';
  @override
  String openRelatedFile({required Object name}) => '関連ファイル ${name} を開く';
  @override
  String inspectFile({required Object name}) => '${name} を検査';
  @override
  String get jumpEcho => 'エコーへジャンプ';
  @override
  String get copyLine => '行をコピー';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$ja tempo =
      _Translations$diff$pinned$tempo$ja._(_root);
  @override
  late final _Translations$diff$pinned$tone$ja tone =
      _Translations$diff$pinned$tone$ja._(_root);
  @override
  late final _Translations$diff$pinned$summary$ja summary =
      _Translations$diff$pinned$summary$ja._(_root);
  @override
  late final _Translations$diff$pinned$tightness$ja tightness =
      _Translations$diff$pinned$tightness$ja._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept}（${tightness}）';
  @override
  String get storyWhyThisMatters => 'なぜこれが重要か';
  @override
  String get storyConfidence => '確信度';
  @override
  String get storySecondarySignal => '副次シグナル';
  @override
  String get storyNeighbourhood => '近傍';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'この行は現在のコードベースフィールドで ${name} の近くに位置します。';
  @override
  String get propagationLane => '伝播レーン';
  @override
  String propagationLaneNamed({required Object lane}) => '伝播レーン：${lane}';
  @override
  late final _Translations$diff$pinned$witness$ja witness =
      _Translations$diff$pinned$witness$ja._(_root);
  @override
  late final _Translations$diff$pinned$integrity$ja integrity =
      _Translations$diff$pinned$integrity$ja._(_root);
  @override
  late final _Translations$diff$pinned$related$ja related =
      _Translations$diff$pinned$related$ja._(_root);
  @override
  late final _Translations$diff$pinned$axis$ja axis =
      _Translations$diff$pinned$axis$ja._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$ja extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} 件非表示';
  @override
  String get landing => '着地';
}

// Path: diff.binary
class _Translations$diff$binary$ja extends Translations$diff$binary$en {
  _Translations$diff$binary$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB（大きすぎてプレビューできません）';
  @override
  String get unableToLoadBlob => 'blob を読み込めません';
  @override
  String get omittedKindMedia => 'メディア';
  @override
  String get omittedKindBinary => 'バイナリ';
  @override
  String omittedStub({required Object kind}) => '${kind} · 非表示';
}

// Path: diff.media
class _Translations$diff$media$ja extends Translations$diff$media$en {
  _Translations$diff$media$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => '画像をデコードできません';
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
  String get stateAdded => '追加';
  @override
  String get stateDeleted => '削除';
  @override
  String get stateModified => '変更';
  @override
  String get fallbackFormatName => 'バイナリ';
}

// Path: filament.severity
class _Translations$filament$severity$ja
    extends Translations$filament$severity$en {
  _Translations$filament$severity$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get critical => '重大';
  @override
  String get warn => '警告';
  @override
  String get info => '情報';
  @override
  String get joint => '接合';
}

// Path: filament.kind
class _Translations$filament$kind$ja extends Translations$filament$kind$en {
  _Translations$filament$kind$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => '古い値';
  @override
  String get temporalShift => '時間的なずれ';
  @override
  String get contextInversion => '文脈の反転';
  @override
  String get contradictoryFlow => '矛盾したフロー';
}

// Path: history.commitLede
class _Translations$history$commitLede$ja
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$ja semantics =
      _Translations$history$commitLede$semantics$ja._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$ja
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(root)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} 件';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${path}/ 内 ${n} ファイル',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '他 ${n} ファイル',
      );
  @override
  String get breadcrumbAll => 'すべて';
  @override
  String breadcrumbCurrentFocus({required Object target}) => '現在の焦点：${target}';
  @override
  String get breadcrumbViewAllChanges => 'このコミットの全変更を表示';
  @override
  String breadcrumbDrillUpTo({required Object target}) => '${target}へ上がる';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
    n,
    other: '${n} ファイル  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} サブディレクトリ',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}、${adds} 追加、${dels} 削除';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
    n,
    other: '${n} ファイル、${adds} 追加、${dels} 削除',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ハンク',
      );
  @override
  String get largestChangeInView => 'このビューで最大の変更';
  @override
  String get conflictedTag => 'コンフリクト';
  @override
  String get dirtyTag => 'ダーティ';
  @override
  String get drillInTag => '掘り下げる';
  @override
  String get changeTypeRenamed => 'リネーム';
  @override
  String get changeTypeCopied => 'コピー';
  @override
  String get changeTypeTypechange => '型変更';
  @override
  String get changeTypeConflict => 'コンフリクト';
  @override
  String get coreFile => 'コアファイル';
  @override
  String get staleFile => '古い';
  @override
  String get filterPathHint => 'パスを絞り込み';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$ja
    extends Translations$history$worldline$en {
  _Translations$history$worldline$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => '世界線を閉じる';
  @override
  String get dragToOpenWorldline => 'ドラッグして世界線を開く';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$ja
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => '現在のブランチ';
  @override
  String applyCommitOnto({required Object branch}) => 'コミットの変更を${branch}へ適用';
  @override
  String revertCommitOn({required Object branch}) => '${branch}上でコミットの変更をリバート';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$ja
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get paused => 'チェリーピックを一時停止しました。残りのコンフリクトを変更ページで解決してください。';
  @override
  String failed({required Object error}) => 'チェリーピックに失敗しました：${error}';
  @override
  String pickedResolved({required Object short}) =>
      '${short}をチェリーピックしました（コンフリクトを解決）';
  @override
  String picked({required Object short}) => '${short}をチェリーピックしました';
}

// Path: history.revert
class _Translations$history$revert$ja extends Translations$history$revert$en {
  _Translations$history$revert$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get paused => 'リバートを一時停止しました。残りのコンフリクトを変更ページで解決してください。';
  @override
  String failed({required Object error}) => 'リバートに失敗しました：${error}';
  @override
  String revertedResolved({required Object short}) =>
      '${short}をリバートしました（コンフリクトを解決）';
  @override
  String reverted({required Object short}) => '${short}をリバートしました';
}

// Path: history.reflog
class _Translations$history$reflog$ja extends Translations$history$reflog$en {
  _Translations$history$reflog$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'ここからブランチを作成…';
  @override
  String get copyCommitHash => 'コミットハッシュをコピー';
  @override
  String get createBranchDialogTitle => 'reflog エントリからブランチを作成';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'アンカー：${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'ブランチ名';
  @override
  String get createAction => '作成';
  @override
  String createBranchFailed({required Object error}) =>
      'ブランチの作成に失敗しました：${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'ブランチ「${name}」を ${short} に作成しました。';
}

// Path: history.rebase
class _Translations$history$rebase$ja extends Translations$history$rebase$en {
  _Translations$history$rebase$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      '最初のコミットは${action}にできません';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} コミットをリベース',
      );
  @override
  String get resetLabel => 'リセット';
  @override
  String get dragToReorderHint => 'ドラッグで並べ替え、コミットごとにアクションを選択';
  @override
  String get newMessageHint => '新しいメッセージ';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'リベースを開始';
}

// Path: history.inFlight
class _Translations$history$inFlight$ja
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get header => '進行中';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$ja
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '履歴手術';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'ドライラン';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$ja
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => '履歴から削除するファイルを選択';
  @override
  String selectedCount({required Object n}) => '${n} 件選択';
  @override
  String get searchHint => '検索…';
  @override
  String get readingTree => 'ツリーを読み込み中…';
  @override
  String get continueDisabled => '続けるにはファイルを選択';
  @override
  String get continueEnabled => '続ける →';
  @override
  String toPurgeCount({required Object n}) => '${n} 件を消去';
  @override
  String get analyzing => '解析中…';
  @override
  String get riskLow => '低リスク';
  @override
  String get riskModerate => '中リスク';
  @override
  String get riskHigh => '高リスク';
  @override
  String get impactCommitsLabel => 'コミット';
  @override
  String get impactBranchesLabel => 'ブランチ';
  @override
  String get impactWorktreesLabel => '作業ツリー';
  @override
  String get impactCouplingLabel => '結合';
  @override
  String get impactCouplingIsland => '孤立';
  @override
  String impactCouplingNeighbors({required Object n}) => '隣接 ${n} 件';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$ja
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get heading => '仕組み';
  @override
  String get backupTitle => 'バックアップ';
  @override
  String get backupBody =>
      '変更が加わる前に、すべてのブランチとタグの ref がバックアップ名前空間へコピーされます。問題が起きても、ワンクリックで元の状態を復元できます。';
  @override
  String get rewriteTitle => '書き換え';
  @override
  String get rewriteBody =>
      '各コミットをルートから先端までたどります。対象ファイルを含むコミットごとに、それらをツリーから除いた新しいコミットを作成します。親チェーンはトポロジーを保つように付け替えられます。 ';
  @override
  String rewriteSummary({required Object total, required Object affected}) =>
      '${total} コミット中 ${affected} 件が書き換えられます。';
  @override
  String get updateRefsTitle => 'ref の更新';
  @override
  String get updateRefsBody =>
      'ブランチとタグのポインターが新しいコミット SHA へ移動します。古いオブジェクトはガベージコレクションまで残ります。 ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      'あなたの ${n} 個の作業ツリーは再チェックアウトが必要になります。';
  @override
  String get noWorktreesAffected => '影響を受ける作業ツリーはありません。';
  @override
  String get forcePushTitle => '強制プッシュ';
  @override
  String get forcePushBody =>
      '消去を検証したあと、強制プッシュするブランチを選びます。--force-with-lease を使うため、その間に誰かがプッシュしていれば安全に失敗します。';
  @override
  String get plumbingNote =>
      'filter-repo や BFG とは違い、これはすべて git のプランビングコマンド（cat-file、mktree、commit-tree、update-ref）で実行されます。外部依存はありません。リネーム追跡はファイルごとに 1 チェーンをたどります。ファイルがコピーされ両方のコピーが独立してリネームされた場合は、実行後に消去結果を確認してください。';
  @override
  String get back => '← 戻る';
  @override
  String get continueLabel => '理解しました、続ける →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$ja
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) => '${n} コミットが書き換えられます';
  @override
  String get forcePushRequired => 'リモートブランチには強制プッシュが必要になります';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} 個の作業ツリーは再チェックアウトが必要になります';
  @override
  String stashesInvalid({required Object n}) => '${n} 件のスタッシュが無効になる可能性があります';
  @override
  String get heading => 'この操作は git 履歴を書き換えます';
  @override
  String get subheading => '強制プッシュ後は自動で取り消せません。';
  @override
  String typeHint({required Object word}) => '${word} と入力';
  @override
  String get goBack => '戻る';
  @override
  String get begin => '手術を開始';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$ja
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => '準備中…';
  @override
  String get backingUpRefs => 'ref をバックアップ中…';
  @override
  String get rewritingCommits => 'コミットを書き換え中…';
  @override
  String get updatingRefs => 'ref を更新中…';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$ja
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get complete => '手術完了';
  @override
  String get failed => '手術失敗';
  @override
  String get commitsRewrittenLabel => '書き換えたコミット';
  @override
  String get refsUpdatedLabel => '更新した ref';
  @override
  String get oldHeadLabel => '旧 HEAD';
  @override
  String get newHeadLabel => '新 HEAD';
  @override
  String get purgeVerifiedLabel => '消去を検証';
  @override
  String get purgeClean => 'クリーン';
  @override
  String get purgeTracesRemain => '痕跡が残存';
  @override
  String get displacedWorktrees => '移動した作業ツリー';
  @override
  String get undoSurgery => '手術を取り消す';
  @override
  String get rolledBack => 'バックアップの ref にロールバックしました。';
  @override
  String get done => '完了';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$ja
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'プッシュ中…';
  @override
  String get forcePushAll => 'すべて強制プッシュ';
  @override
  String get confirmPush => 'プッシュを確認';
  @override
  String get cancel => 'キャンセル';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$ja extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get back => '戻る';
  @override
  String get continueLabel => '続ける';
  @override
  String get letsGo => 'はじめよう';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$ja
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'これはあなたにとって何ですか？';
  @override
  String get questionEmphasis => 'これ';
  @override
  String get iAmPrefix => '私は ';
  @override
  String get iAmSuffix => ' 、あなた専用の Git クライアントです。';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$ja
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '${name}を着飾ろう。';
  @override
  String get themesHeader => 'テーマ';
  @override
  String get keybindingsHeader => 'キーバインド';
  @override
  String get previewBadge => 'プレビュー';
  @override
  String get useDefaults => '既定を使う';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$ja extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '${name}に対象を指定しよう。';
  @override
  String get later => 'あとでやる';
  @override
  late final _Translations$onboarding$repo$doors$ja doors =
      _Translations$onboarding$repo$doors$ja._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$ja cloneForm =
      _Translations$onboarding$repo$cloneForm$ja._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$ja pickers =
      _Translations$onboarding$repo$pickers$ja._(_root);
  @override
  late final _Translations$onboarding$repo$errors$ja errors =
      _Translations$onboarding$repo$errors$ja._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$ja
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$ja panels =
      _Translations$onboarding$preview$panels$ja._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$ja sidebar =
      _Translations$onboarding$preview$sidebar$ja._(_root);
  @override
  late final _Translations$onboarding$preview$changes$ja changes =
      _Translations$onboarding$preview$changes$ja._(_root);
  @override
  late final _Translations$onboarding$preview$history$ja history =
      _Translations$onboarding$preview$history$ja._(_root);
  @override
  late final _Translations$onboarding$preview$branches$ja branches =
      _Translations$onboarding$preview$branches$ja._(_root);
  @override
  late final _Translations$onboarding$preview$diff$ja diff =
      _Translations$onboarding$preview$diff$ja._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$ja extends Translations$orrery$header$en {
  _Translations$orrery$header$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'スクラブ';
  @override
  String get modeCompare => '比較';
  @override
  String get lodModules => 'モジュール';
  @override
  String get lodFiles => 'ファイル';
}

// Path: orrery.status
class _Translations$orrery$status$ja extends Translations$orrery$status$en {
  _Translations$orrery$status$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '履歴を通してmanifoldを追跡中…';
  @override
  String get loadError => 'このリポジトリの履歴を読み取れませんでした。';
  @override
  String get notEnoughHistory => '軌道を描くにはまだ履歴が足りません。';
  @override
  String get notEnoughHistoryDetail => 'Orrery には図示のためにいくつかのコミットが必要です。';
}

// Path: orrery.legend
class _Translations$orrery$legend$ja extends Translations$orrery$legend$en {
  _Translations$orrery$legend$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get central => '中心';
  @override
  String get peripheral => '周縁';
}

// Path: orrery.node
class _Translations$orrery$node$ja extends Translations$orrery$node$en {
  _Translations$orrery$node$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'モジュール';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} ファイル';
  @override
  String fileFallback({required Object id}) => 'ファイル #${id}';
  @override
  String nodeFallback({required Object id}) => 'ノード #${id}';
  @override
  String get rootModule => '(root)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$ja
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => '起源';
  @override
  String get now => '現在';
  @override
  String get reorganized => '再編成';
  @override
  String becameArchetype({required Object archetype}) => '${archetype}になった';
  @override
  String get snapshot => 'スナップショット';
}

// Path: orrery.structure
class _Translations$orrery$structure$ja
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get forming => '形成中…';
  @override
  String get canonical => '正準';
  @override
  String get connectivity => '連結性';
  @override
  String get rigidity => '剛性';
  @override
  String get entropy => 'エントロピー';
}

// Path: orrery.rail
class _Translations$orrery$rail$ja extends Translations$orrery$rail$en {
  _Translations$orrery$rail$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => '構造';
  @override
  String get fieldLabel => 'フィールド';
  @override
  String get findingsLabel => '指摘';
  @override
  String get selectedLabel => '選択中';
  @override
  String get noFindings => 'この履歴に構造的イベントは検出されませんでした。';
}

// Path: orrery.selection
class _Translations$orrery$selection$ja
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => '履歴のこの時点には存在しません。';
  @override
  String get roleCentral => '結合の中心 — ここでの変更はシステム全体に波及します。';
  @override
  String get rolePeripheral => '周縁 — 疎に結合し、おおむね単独で変化します。';
  @override
  String get roleMid => '中間構造 — 適度に結合しています。';
  @override
  String get driftOutward => ' 外へ漂流中 — 脱結合。';
  @override
  String get driftInward => ' 内へ漂流中 — 統合。';
  @override
  String get driftHolding => ' 位置を保持中。';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$ja
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'ハブ';
  @override
  String get driftOut => '外へ漂流';
  @override
  String get driftIn => '内へ漂流';
  @override
  String get tangle => 'もつれ';
  @override
  String get clarify => '明確化';
  @override
  String get regime => '再編';
  @override
  String get thrash => 'スラッシング';
  @override
  String get reshuffle => '再配置';
  @override
  String get forecast => '予測';
}

// Path: orrery.findings
class _Translations$orrery$findings$ja extends Translations$orrery$findings$en {
  _Translations$orrery$findings$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      '連結性が低下し続け、最低付近にあります。このまま続けば、コードベースは疎に結合した二つの半分へと分裂に向かいます。それが意図かどうか、今決めてください。';
  @override
  String get forecastConsolidate =>
      '連結性がピークに向けて上昇しています。このまま続けば、コードベースは密に結合した一つの塊へと統合されます。モノリスへの硬直化に注意してください。';
  @override
  String thrash({required Object name}) =>
      '${name}は何度も行き来しながら再編成されています。構造的な混乱が多く、正味の移動はわずかです。結合を安定させるか、触るのをやめてください。';
  @override
  String get reshuffle =>
      'このコミットは一見ありふれて見えますが、どのファイルが中心かを静かに変えました。全体の形は保たれつつ、内側で構造が再配置されています。慎重に見直してください。';
  @override
  String hub({required Object name}) =>
      '${name}は構造の核に位置し、システムはこれを中心に再編成します。ここでの変更は影響範囲が大きいものとして扱ってください。';
  @override
  String driftOut({required Object name}) =>
      '${name}は核から縁へと漂流しました。システムから脱結合しています。引退しつつあるか、静かに腐りつつあるかのどちらかです。';
  @override
  String driftIn({required Object name}) =>
      '${name}は核へと移動しました。荷重を担う存在になりつつあります。さらに依存が増える前に、十分にテストされているか確認してください。';
  @override
  String get regime =>
      'コードベースがここで大きく再編成され、連結性が跳ね上がりました。何が分離したか、統合したかを見直してください。';
  @override
  String get tangleTrend =>
      '履歴を通して、コードベースはよりもつれた構造へと向かっています。連結が密になり、モジュール性が下がっています。';
  @override
  String get clarifyTrend =>
      '履歴を通して、コードベースはより整理された構造へと向かっています。より明確なモジュールへと分離しつつあります。';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$ja extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get core => '核';
  @override
  String get drift => '漂流';
  @override
  String get trend => '傾向';
  @override
  String get thrash => 'スラッシュ';
}

// Path: orrery.compare
class _Translations$orrery$compare$ja extends Translations$orrery$compare$en {
  _Translations$orrery$compare$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => '変化';
  @override
  String get movers => '移動したもの';
  @override
  String get noMovers => 'これらのフレーム間で移動したファイルはありません。';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'ファイル';
  @override
  String get deltaConnectivity => '連結性';
  @override
  String get deltaRigidity => '剛性';
  @override
  String get deltaEntropy => 'エントロピー';
  @override
  String get wayOutward => '外へ';
  @override
  String get wayInward => '内へ';
  @override
  String get wayShifted => '移動';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$ja
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask: [質問]';
  @override
  String get nearHint => 'near: [ファイル]';
  @override
  String get whoHint => 'who: [ファイル]';
  @override
  String get logHint => 'log: [メッセージ]';
  @override
  String get runHint => 'run: [ツール]';
  @override
  String askLabel({required Object name, required Object body}) =>
      '${name}に質問：${body}';
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
  }) => '${path} · レビュアー ${count} 名 · ${touches} 回タッチ';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} 回タッチ';
  @override
  String whoTouchesSubtitle({required Object path}) => '${path} · レビュアーの記録なし';
}

// Path: palette.chips
class _Translations$palette$chips$ja extends Translations$palette$chips$en {
  _Translations$palette$chips$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

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
class _Translations$palette$predictive$ja
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '勢い ${percent}%';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$ja
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} 回タッチ · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$ja
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'ステージの一貫性：${percent}%';
  @override
  String subtitle({required Object count}) => '${count} ファイル';
}

// Path: palette.keystone
class _Translations$palette$keystone$ja
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · キーストーン ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$ja extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => '${name}の変更';
  @override
  String history({required Object name}) => '${name}の履歴';
  @override
  String branches({required Object name}) => '${name}のブランチ';
  @override
  String terminal({required Object name}) => '${name}のターミナル';
  @override
  String generateCommit({required Object name}) => 'コミット生成 · ${name}';
  @override
  String reviewChanges({required Object name}) => '${name}の変更をレビュー';
  @override
  String muse({required Object name}) => '${name}の Muse';
}

// Path: palette.desks
class _Translations$palette$desks$ja extends Translations$palette$desks$en {
  _Translations$palette$desks$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'メイン作業ツリー';
  @override
  String get detached => '分離';
  @override
  String dirty({required Object count}) => '${count} 件ダーティ';
}

// Path: palette.actions
class _Translations$palette$actions$ja extends Translations$palette$actions$en {
  _Translations$palette$actions$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'ブラウザーで開く';
  @override
  String get terminal => 'ターミナル';
  @override
  String get revealInFiles => 'ファイルで表示';
  @override
  String get copyPath => 'パスをコピー';
  @override
  String get copyBranch => 'ブランチ名をコピー';
}

// Path: palette.tools
class _Translations$palette$tools$ja extends Translations$palette$tools$en {
  _Translations$palette$tools$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => '${label}を起動';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$ja
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'フェッチ';
  @override
  String get pull => 'プル';
  @override
  String pullBehind({required Object count}) => '${count} 遅延';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'プッシュ';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} コミット',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} を ${upstream} へ';
  @override
  String get forcePush => '強制プッシュ';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      '強制プッシュできません：${branch}に上流が設定されていません。';
  @override
  String get commit => 'コミット';
  @override
  String get stageAll => 'すべてステージ';
  @override
  String get unstageAll => 'すべてステージ解除';
  @override
  String get discardAll => 'すべて破棄';
  @override
  String get createBranch => 'ブランチを作成';
  @override
  String get deleteBranch => 'ブランチを削除';
  @override
  String get renameBranch => 'ブランチ名を変更';
  @override
  String get stash => 'スタッシュ';
  @override
  String get stashPop => 'スタッシュを取り出す';
  @override
  String get stashApply => 'スタッシュを適用';
  @override
  String get stashDrop => 'スタッシュを破棄';
  @override
  String get createTag => 'タグを作成';
  @override
  String get cherryPick => 'チェリーピック';
  @override
  String get revert => 'リバート';
  @override
  String get stashConflictMessage => 'スタッシュをコンフリクト付きで適用しました。変更ページで解決してください。';
}

// Path: palette.pr
class _Translations$palette$pr$ja extends Translations$palette$pr$en {
  _Translations$palette$pr$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'PR を作成';
  @override
  String get merge => 'PR をマージ';
  @override
  String get markReady => 'PR を準備完了にする';
}

// Path: palette.ai
class _Translations$palette$ai$ja extends Translations$palette$ai$en {
  _Translations$palette$ai$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'コミット生成';
  @override
  String get reviewChanges => '変更をレビュー';
  @override
  String get runMuse => 'Muse を実行';
  @override
  String debugRepo({required Object name}) => '${name}をデバッグ';
  @override
  String get describeSymptom => '症状を記述';
  @override
  String viewResult({required Object kind}) => '${kind}を表示';
  @override
  String get unseenResult => '未読の結果';
  @override
  String runningResult({required Object kind}) => 'AI：${kind}…';
  @override
  String get running => '実行中';
  @override
  String get kindCommitMessage => 'コミットメッセージ';
  @override
  String get kindCodeReview => 'コードレビュー';
  @override
  String get kindMuseResult => 'Muse の結果';
  @override
  String get kindPresentation => 'プレゼンテーション';
  @override
  String get kindDebugResult => 'デバッグ結果';
}

// Path: palette.undo
class _Translations$palette$undo$ja extends Translations$palette$undo$en {
  _Translations$palette$undo$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'キャンセル：${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$ja
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get changes => '変更';
  @override
  String get history => '履歴';
  @override
  String get branches => 'ブランチ';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => '設定';
  @override
  String get refresh => '更新';
}

// Path: palette.settings
class _Translations$palette$settings$ja
    extends Translations$palette$settings$en {
  _Translations$palette$settings$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'モーションを減らす';
  @override
  String get animateLogoUnfocused => '非フォーカス時にロゴをアニメーション';
  @override
  String get instantBlameHover => '即時ブレームホバー';
  @override
  String get autoSelectChanges => '変更を自動選択';
  @override
  String get fetchOnlineIssues => 'オンラインの Issue を取得';
  @override
  String get rememberWip => '作業中の内容を記憶';
  @override
  String get hideAiFeatures => 'AI 機能を非表示';
  @override
  String get crashReporting => 'クラッシュレポート';
  @override
  String get aiReadOnly => 'AI 読み取り専用';
  @override
  String get stashCabinetExpanded => 'スタッシュ棚を展開';
  @override
  String get fileSortInverted => 'ファイルの並び順を反転';
}

// Path: palette.info
class _Translations$palette$info$ja extends Translations$palette$info$en {
  _Translations$palette$info$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$ja extends Translations$palette$debug$en {
  _Translations$palette$debug$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'エンジンの状態';
  @override
  String get engineStatusSubtitle => 'LogosGit スペクトルエンジンの診断';
  @override
  String get fileCoupling => 'ファイル結合';
  @override
  String get fileCouplingSubtitle => 'ステージ済みファイルの最近傍の共変更';
  @override
  String get themeSpecimen => 'テーマ見本';
  @override
  String get themeSpecimenSubtitle => 'すべての色、アイコン、テキスト階層、ジオメトリ';
}

// Path: palette.dev
class _Translations$palette$dev$ja extends Translations$palette$dev$en {
  _Translations$palette$dev$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'マージエディターをテスト';
  @override
  String get testHistorySurgery => '履歴手術をテスト';
  @override
  String get back => '戻る';
  @override
  String get cancel => 'キャンセル';
  @override
  String get buildingConflicts => '履歴からテスト用コンフリクトを構築中…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$ja
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get label => '履歴手術';
  @override
  String get subtitle => '履歴を書き換えてファイルを永久に削除';
}

// Path: palette.orrery
class _Translations$palette$orrery$ja extends Translations$palette$orrery$en {
  _Translations$palette$orrery$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle => 'リポジトリの構造的履歴をmanifoldでスクラブ';
}

// Path: palette.command
class _Translations$palette$command$ja extends Translations$palette$command$en {
  _Translations$palette$command$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label}が完了しました';
  @override
  String failed({required Object label, required Object message}) =>
      '${label}に失敗しました：${message}';
  @override
  String get copy => 'コピー';
}

// Path: palette.search
class _Translations$palette$search$ja extends Translations$palette$search$en {
  _Translations$palette$search$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'すべてを検索…';
  @override
  String get hintElevated => '昇格 — 全アクション';
  @override
  String get emptyTypeToSearch => '入力して検索';
  @override
  String get emptyNoResults => '結果なし';
}

// Path: palette.wick
class _Translations$palette$wick$ja extends Translations$palette$wick$en {
  _Translations$palette$wick$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => '結合';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$ja
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get current => '現在';
  @override
  String get staged => 'ステージ済み';
  @override
  String get modified => '変更済み';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$ja
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$ja whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$ja._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$ja spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$ja._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$ja whereGoing =
      _Translations$releaseNotes$about$whereGoing$ja._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$ja
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license => 'GPL-3.0-or-later · WLCSL コミュニティソース研究コア · 無保証';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$ja
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 行',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$ja
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイル。',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 行（${bytes}）。',
      );
  @override
  String roles({required Object parts}) => '役割 — ${parts}。';
  @override
  String showingNofM({required Object total, required Object active}) =>
      '${total} ファイル中 ${active} を、構造的な中心性順で表示中。';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$ja
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'ひと目で';
  @override
  String get core => 'コア';
  @override
  String get gettingStarted => 'はじめに';
  @override
  String get regions => '領域';
  @override
  String get shape => '形状';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$ja
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) => '読み取り可能なテキストファイルのないリポジトリ${detail}。';
  @override
  String emptyBinary({required Object n}) => 'バイナリ ${n} 件';
  @override
  String emptyUnreadable({required Object n}) => '読み取り不可 ${n} 件';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'アクティブなファイル ${n} 件のリポジトリ。',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'アクティブなファイル ${n} 件のリポジトリ — ${regions}。',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$ja
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'すべて `${dir}` 配下。';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: 'コア ${n} 件',
      );
  @override
  String get bodyCoreSeparator => '、';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} ファイル',
      );
  @override
  String connectsTo({required Object linked}) => '接続先：${linked}。';
  @override
  String get filesLabel => 'ファイル：';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$ja
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get bulk => '密に相互接続したコードベース：ほとんどのファイルが、共有された変更の一つの大きな近傍に参加しています。';
  @override
  String get crystalline => '格子状のコードベース：ファイル間の結合が均一で規則的、局所構造も予測しやすい。';
  @override
  String get goe => '豊かに相互接続したコードベース：支配的な背骨を持たず、結合がファイル全体に広がっています。';
  @override
  String get modular =>
      'モジュール型のコードベース：交差結合の少ない、いくつかの凝集した領域。ある領域での作業が別の領域を乱すことはめったにありません。';
  @override
  String get poisson => '疎に結合したコードベース：ファイルはおおむね独立して進化し、ときおり共有された変更が起こります。';
  @override
  String get tree => '木構造のコードベース：一つの支配的な背骨と、それに依存する枝。変更は通常コアから外へと伝播します。';
}

// Path: settings.language
class _Translations$settings$language$ja
    extends Translations$settings$language$en {
  _Translations$settings$language$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '言語';
  @override
  String get summary => 'このアプリの UI 言語。Git の出力、ログ、診断は英語のままなので、バグ報告は検索しやすいままです。';
  @override
  String get label => '表示言語';
  @override
  String get systemDefault => 'システムの既定';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'OS の言語に従います（${resolved}）';
  @override
  String get disclosureSource => 'ソース言語。開発者によって書かれています。';
  @override
  String disclosureAi({required Object model}) =>
      '${model}による機械翻訳。まだ人手によるレビューはされていません。修正を歓迎します。';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => '${model}による機械翻訳。${percent}% を人手でレビュー済み。';
  @override
  String get disclosureHuman => '人手による翻訳、コミュニティが維持しています。';
  @override
  String reviewedBy({required Object names}) => '${names}がレビューしました。';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$ja
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => '環境設定';
  @override
  String get shortcuts => 'ショートカット';
  @override
  String get behaviour => '挙動';
  @override
  String get aiProviders => 'AI プロバイダー';
  @override
  String get modelSlots => 'モデルスロット';
  @override
  String get tools => 'ツール';
  @override
  String get diagnostics => '診断';
  @override
  String get offenders => '問題要因';
  @override
  String get release => 'リリース';
}

// Path: settings.errors
class _Translations$settings$errors$ja extends Translations$settings$errors$en {
  _Translations$settings$errors$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => 'ガードレールプロファイルの保存に失敗しました。';
  @override
  String get saveRetentionPolicy => '保持ポリシーの保存に失敗しました。';
  @override
  String get saveUpdateChannel => '更新チャンネルの保存に失敗しました。';
  @override
  String get saveModelSelection => 'AI モデルの選択の保存に失敗しました。';
  @override
  String get saveModelAlias => 'モデルのエイリアスの保存に失敗しました。';
  @override
  String get saveCommitMessageModelSlot => 'コミットメッセージのモデルスロットの保存に失敗しました。';
  @override
  String get saveReviewModelSlot => 'レビューのモデルスロットの保存に失敗しました。';
  @override
  String get saveCommitMessageCustomPrompt => 'コミットメッセージのカスタムプロンプトの保存に失敗しました。';
  @override
  String get saveReviewGuide => 'レビューガイドの保存に失敗しました。';
  @override
  String get saveMuseNotes => 'Muse のノートの保存に失敗しました。';
  @override
  String get saveReviewDoubleCheck => 'レビューのダブルチェックモードの保存に失敗しました。';
  @override
  String get saveApiPiggybackCli => 'API ピギーバック CLI の保存に失敗しました。';
  @override
  String get saveCliTimeout => 'CLI タイムアウトの保存に失敗しました。';
  @override
  String get stopAllCli => '実行中の CLI セッションを停止できませんでした。';
  @override
  String clearLocalData({required Object error}) =>
      'ローカルデータを消去できませんでした：${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$ja
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get editing => '編集中';
  @override
  String get saving => '保存中';
  @override
  String get saveFailed => '保存に失敗しました';
}

// Path: settings.clearData
class _Translations$settings$clearData$ja
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'ローカルデータを消去';
  @override
  String get clear => '消去';
  @override
  String get confirmDiagnostics => 'ローカルの診断サンプルとパフォーマンス計測を消去しますか？';
  @override
  String get confirmAudit => 'ローカルの AI 監査メタデータ記録を消去しますか？';
  @override
  String get confirmAll => 'ローカルの診断サンプルと AI 監査メタデータ記録をすべて消去しますか？';
  @override
  String get confirmWipeAll =>
      '最近のリポジトリ一覧を含む、すべてのローカルアプリデータを消去して終了しますか？ ディスク上の実際の git リポジトリには手を触れません。';
  @override
  String get confirmReset =>
      'ローカルのアプリデータをリセットして終了しますか？\n\n設定、テーマ、オンボーディング、AI の設定、テレメトリ、エングラムキャッシュが消去されます。最近のリポジトリ一覧は残ります。';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$ja
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '緩め';
  @override
  String get balanced => 'バランス';
  @override
  String get strict => '厳格';
  @override
  String get paranoid => '偏執';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$ja
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'ガードレール';
  @override
  String get summary => '体験全体を通して、自動化がどれだけ注意深いか。';
}

// Path: settings.appearance
class _Translations$settings$appearance$ja
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '外観';
  @override
  String get summary => '全体的なインターフェースのムードと雰囲気。';
}

// Path: settings.retention
class _Translations$settings$retention$ja
    extends Translations$settings$retention$en {
  _Translations$settings$retention$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'ローカルデータの保持';
  @override
  String get summaryDiagnostics => '診断の保持ポリシー。';
  @override
  String get summaryWithAudit => '診断と AI 監査の保持ポリシー。';
  @override
  String get unitDays => '日';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote => '診断、パフォーマンス計測、メタデータを含みます。';
}

// Path: settings.navigation
class _Translations$settings$navigation$ja
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'ナビゲーションとダイナミクス';
  @override
  String get summaryShortcuts => 'ショートカットとインターフェースの挙動。';
  @override
  String get summaryWithAi => 'ショートカット、インターフェースの挙動、AI のルーティング。';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$ja
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '挙動のダイナミクス';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$ja
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get diag => '診断';
  @override
  String get audit => '監査';
  @override
  String get all => 'すべて';
  @override
  String get clearsHint => '<-- 消去';
}

// Path: settings.channels
class _Translations$settings$channels$ja
    extends Translations$settings$channels$en {
  _Translations$settings$channels$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get stable => '安定版';
  @override
  String get beta => 'ベータ';
  @override
  String get dev => '開発';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$ja
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => '最新';
  @override
  String updateAvailable({required Object version}) => '${version}が利用可能';
  @override
  String get notConfigured => '更新サーバーなし';
  @override
  String notFound({required Object channel}) => '${channel}のリリースなし';
  @override
  String get unreachable => '到達不可';
  @override
  String get badManifest => '不正なマニフェスト';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$ja
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'キーバインドプロファイル';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'ニューメリック';
  @override
  String get porcelainDescription => 'コードショートカット（G のあと C、H、B…）。';
  @override
  String get numericDescription => '数字キー単押しのショートカット（1、2、3…）。';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$ja
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'API キー';
  @override
  String get endpointHint => 'エンドポイント';
  @override
  String get test => 'テスト';
  @override
  String get hide => '隠す';
  @override
  String get show => '表示';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$ja
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => '移動';
  @override
  String get staging => 'ステージング';
  @override
  String get branchesPrs => 'ブランチ＆PR';
  @override
  String get modifiers => '修飾キー';
  @override
  String get changes => '変更';
  @override
  String get history => '履歴';
  @override
  String get branches => 'ブランチ';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => '切り替え（常時）';
  @override
  String get search => '検索';
  @override
  String get dismiss => '閉じる';
  @override
  String get refresh => '更新';
  @override
  String get shortcuts => 'ショートカット';
  @override
  String get nextChange => '次の変更';
  @override
  String get prevChange => '前の変更';
  @override
  String get toggleLine => '行を切り替え';
  @override
  String get toggleHunk => 'ハンクを切り替え';
  @override
  String get toggleFile => 'ファイルを切り替え';
  @override
  String get pinContext => '文脈をピン留め';
  @override
  String get commit => 'コミット';
  @override
  String get acceptHint => 'ヒントを採用';
  @override
  String get undo => '取り消し';
  @override
  String get navigateRow => '移動';
  @override
  String get expand => '展開';
  @override
  String get checkout => 'チェックアウト';
  @override
  String get approve => '承認';
  @override
  String get requestChanges => '変更を要求';
  @override
  String get selectRange => '範囲を選択';
  @override
  String get extendedMenu => '拡張メニュー';
}

// Path: settings.toggles
class _Translations$settings$toggles$ja
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'AI 読み取り専用モード';
  @override
  String get aiReadOnlyDescription => 'AI が自動で変更を書き込んだりステージしたりするのを防ぎます。';
  @override
  String get logoMotionLabel => 'タブアウト時にロゴがアニメーション';
  @override
  String get logoMotionDescriptionEnabled => '効率的に作られています。気持ちを傷つけないで';
  @override
  String get logoMotionDescriptionDisabled => '：（';
  @override
  String get rememberWipLabel => '作業中の内容を記憶';
  @override
  String get rememberWipDescription => 'コミットの下書きとファイルの選択をセッション間で保持します。';
  @override
  String get stashCabinetLabel => 'スタッシュ棚を展開した状態で開始';
  @override
  String get stashCabinetDescription => 'リポジトリに棚があるとき、書類棚の引き出しを既定で開いた状態で表示します。';
  @override
  String get instantBlameLabel => '即時ブレームホバー';
  @override
  String get instantBlameDescription =>
      '差分の行でブレーム情報が表示されるまでの 180ms の遅延をスキップします。';
  @override
  String get autoSelectLabel => '新しい変更を自動選択';
  @override
  String get autoSelectDescription => '新しく追跡・変更されたファイルを、自動でコミットの選択に追加します。';
  @override
  String get changeIdLabel => 'change-id ヘッダーを書き込む';
  @override
  String get changeIdDescription =>
      '新しいコミットに change-id 識別ヘッダーを付与します（Jujutsu・GitButler・Gerrit の規約）。各コミットは作成直後に一度書き換えられます。';
  @override
  String get fetchIssuesLabel => 'ブランチ読み込み時にオンラインの Issue を取得';
  @override
  String get fetchIssuesDescription =>
      'ブランチページを開いたとき、バックグラウンドで git プロバイダーから PR と Issue の詳細を取得します。';
  @override
  String get hateAiLabel => 'AI が嫌い';
  @override
  String get hateAiDescription =>
      'LLM ベースの機能をすべて追放します。Logos はただのスペクトル数学なので動き続けます。';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$ja
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '差分の差分しやすさ';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$ja
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'プロバイダーを読み込み中…';
  @override
  String get refreshingProviders => 'プロバイダーの診断を更新中…';
  @override
  String get routeDescription => '設定に名前を付け、検出された任意のプロバイダーモデルへ振り分けます。';
  @override
  String get loadingCategories => 'モデルカテゴリを読み込み中…';
  @override
  String get noOptions => '利用可能なモデルの選択肢がまだありません。まず互換性のあるローカル AI CLI を検出してください。';
  @override
  String get slotsAppearWhenAvailable =>
      'プロバイダーモデルが利用可能になると、モデルスロットの設定がここに表示されます。';
  @override
  String get effortDefault => '既定';
  @override
  String get noModelsForSlot => 'このスロットのモデルは検出されませんでした。';
  @override
  String viaProvider({required Object provider}) => '${provider}経由';
  @override
  String get customModelId => 'カスタムモデル ID';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$ja
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) => '「${query}」に一致するモデルはありません';
  @override
  String get noModels => '利用可能なモデルがありません';
  @override
  String get filterHint => 'モデルを絞り込み…';
  @override
  String get warming => '準備中…';
  @override
  String get detailsUnavailable => '詳細を取得できません';
  @override
  String get free => '無料';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$ja
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'あなたの構造、声、カバレッジの好みを使って、ステージ済みの変更からコミットメッセージを作成します。';
  @override
  String get reviewDescription => 'コミットする前に、現在のコミット範囲をレビューします。';
  @override
  String get museDescription => 'ブレインストームののち、差分の前進方向を統合する三段階の神託。';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$ja
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'スタイルガイド';
  @override
  String get styleGuideHint => '任意。声／トーン／禁止事項。骨組みは上のフォーマットが扱います。';
}

// Path: settings.review
class _Translations$settings$review$ja extends Translations$settings$review$en {
  _Translations$settings$review$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'レビュー時に添える追加のノート';
  @override
  String get doubleCheckLabel => 'レビューをダブルチェック';
  @override
  String get doubleCheckDescription => '最終レポートを表示する前に、二度目の検証パスを実行します。';
}

// Path: settings.museHint
class _Translations$settings$museHint$ja
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'そっと導きたい方向は？ 今日のムードは優しめ。';
  @override
  String get balanced => '何にこだわり、何を飛ばすか。正直に、でも厳しすぎず。';
  @override
  String get strict => '基準。禁止事項。Muse が見逃さないこと。';
  @override
  String get paranoid => 'レンズを調整。manifoldはどの周波数で響くべき？';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$ja
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Muse への追加のノート';
}

// Path: settings.museStage
class _Translations$settings$museStage$ja
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'ブレインストーム';
  @override
  String get synthesize => '統合';
  @override
  String get slot => 'スロット';
  @override
  String get ideaCountLoose => '約 12 個のアイデア';
  @override
  String get ideaCountBalanced => '約 16 個のアイデア';
  @override
  String get ideaCountStrict => '約 20 個のアイデア';
  @override
  String get ideaCountParanoid => '約 24 個のアイデア';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  ガードレール：${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$ja
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'フォルダー';
  @override
  String get history => '履歴';
  @override
  String get far => '遠';
  @override
  String get near => '近';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$ja
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'モジュールマップ';
  @override
  String get repoCenters => 'リポジトリの中心';
  @override
  String get neighbors => '隣接';
  @override
  String get toTouch => '次に触れるべきもの';
  @override
  String get relevanceEngine => '関連性エンジン';
  @override
  String get description =>
      'ファイルが構造、履歴、リズムをまたいでどう共に動くかを読み取り、Manifold が単に何が変わったかではなく、何が重要かを知れるようにします。';
  @override
  String get withinReach => '手の届く範囲';
  @override
  String get gate => 'ゲート';
  @override
  String get nearest => '最も近い';
  @override
  String get warming => '準備中';
  @override
  String get emptyOpenRepo => 'リポジトリを開くと\nレンズがライブで見えます';
  @override
  String get emptyNoFiles => '手の届く範囲に\nファイルがありません — \n履歴の方へドラッグ';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$ja
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '変更の並び順ガイド';
  @override
  String get related => '共に変わるファイルは共にまとまります。関心事が先、文脈があとに続きます。';
  @override
  String get relatedInverted => '孤立した変更が先に来ます。密に結合したクラスターは下に沈みます。';
  @override
  String get alphabetical => 'パスで A → Z のシンプルな順。大文字小文字を区別せず、数値は自然な順序。';
  @override
  String get alphabeticalInverted => 'パスで Z → A のシンプルな順。大文字小文字を区別せず、数値は自然な順序。';
  @override
  String get impact => '最も重い変更が先に浮上します。チャーンに重みが付き、バイナリと新規ファイルは押し上げられます。';
  @override
  String get impactInverted => '最も軽い変更が先に浮上します。手早い成果が上に、重い作業はあとに。';
  @override
  String get nearRelated => '近い関連';
  @override
  String get alphabeticalShort => 'アルファベット順';
  @override
  String get byImpact => '影響度順';
  @override
  String get flipped => '反転';
  @override
  String get peek => '覗く';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$ja
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API モデルの使用';
  @override
  String get codexNotDetected => 'codex が検出されません';
  @override
  String get dormant => '休止中';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$ja
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'ビューアー';
  @override
  String get media => 'メディア';
  @override
  String get binary => 'バイナリ';
  @override
  String get hidden => '非表示';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$ja
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => '破壊的なアクション';
  @override
  String get discards => '破棄';
  @override
  String get commits => 'コミット';
  @override
  String get commitPush => 'コミット＋プッシュ';
  @override
  String get all => 'すべて';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$ja
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get label => '取り消しウィンドウ';
  @override
  String get off => 'オフ';
  @override
  String descriptionInstant({required Object scope}) => '${scope}は即座に確定します。';
  @override
  String descriptionDelayed({required Object scope, required Object seconds}) =>
      '${scope}が確定するまで ${seconds} 秒。';
  @override
  String get cycleScopeTooltip => 'クリックで範囲を切り替え · スライダーを上下にドラッグしても可';
  @override
  String get resetTooltip => 'すべてのアクションを既定のウィンドウに戻す';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$ja
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'たぶん大丈夫、なら大丈夫';
  @override
  String get proper => 'きちんと読む、ロジック、統合、パターン';
  @override
  String get lookAgain => 'もう一度見て。何か隠れているかも';
  @override
  String get assumeWrong => '何かが間違っていると考えて。それを見つけて';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$ja
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh => '例：高レベルのロジックと主要なバグに集中。簡潔に、そして寛容に。';
  @override
  String get surfaceBugs => '例：潜在的なバグ、アーキテクチャの不整合、エッジケースの失敗を洗い出す。';
  @override
  String get scrutinize => '例：最適化、セキュリティ、パターン準拠のため、すべての行を精査する。';
  @override
  String get trustNothing => '例：何も信じない。あらゆる副作用を疑う。すべての行を潜在的な失敗として扱う。';
  @override
  String get optional => 'レビューが何を重視すべきかについての任意の指針。';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$ja
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'フォーマット';
  @override
  String get peek => '覗く';
  @override
  String get structure => '構造';
  @override
  String get voice => '声';
  @override
  String get coverage => 'カバレッジ';
  @override
  String get structureTitleBody => 'タイトル＋本文';
  @override
  String get structureTitleOnly => 'タイトルのみ';
  @override
  String get structureFreeform => '自由形式';
  @override
  String get voiceVerbLed => '行動志向';
  @override
  String get voiceDescriptive => '説明的';
  @override
  String get voiceNarrative => '物語的';
  @override
  String get coverageEssentials => '要点';
  @override
  String get coverageBalanced => 'バランス';
  @override
  String get coverageEverything => 'すべて';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$ja
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$ja title =
      _Translations$settings$commitPreview$title$ja._(_root);
  @override
  late final _Translations$settings$commitPreview$base$ja base =
      _Translations$settings$commitPreview$base$ja._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$ja
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$ja._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$ja
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$ja._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$ja
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '外部ツール';
  @override
  String get summary =>
      'サイドバーでプロジェクトを右クリックすると、これらのいずれかで開けます。引数はプロジェクトフォルダーに {path} を使います。';
  @override
  String get detecting => 'インストール済みのツールを検出中…';
  @override
  String get allPresetsAdded =>
      '既知のプリセットはすべて追加済みです。さらに追加するには「+ Custom」を使ってください。';
  @override
  String get noToolsConfigured => 'まだツールが設定されていません。上から追加してください。';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'エディター';
  @override
  String get categoryExplore => '探索';
  @override
  String get categoryOps => '運用';
  @override
  String get categoryGitOps => 'git 運用';
  @override
  String get nameHint => '名前';
  @override
  String get commandHint => 'コマンド';
  @override
  String get test => 'テスト';
  @override
  String get removeTool => 'ツールを削除';
  @override
  String get modeTerminal => 'ターミナル';
  @override
  String get modeDetached => 'デタッチ';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$ja
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '今月 ${used}${limit}';
}

// Path: settings.gitea
class _Translations$settings$gitea$ja extends Translations$settings$gitea$en {
  _Translations$settings$gitea$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gitea トークン';
  @override
  String get hostHint => 'ホスト';
  @override
  String get tokenHint => 'トークン';
  @override
  String get save => '保存';
}

// Path: settings.wick
class _Translations$settings$wick$ja extends Translations$settings$wick$en {
  _Translations$settings$wick$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'wick の実行ファイルを選択';
  @override
  String get connected => 'wick · 接続済み';
  @override
  String get pathToExecutable => 'wick · 実行ファイルへのパス';
  @override
  String get off => 'オフ';
  @override
  String get disableHint => 'wick 連携をオフにする';
  @override
  String get enableHint => 'wick 連携をオンにする';
}

// Path: settings.integrations
class _Translations$settings$integrations$ja
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '＆連携';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => '予定';
  @override
  String get lspComingSoon => 'lsp · 近日公開';
  @override
  String get alphaMathConnected => 'alpha-math · 接続済み';
  @override
  String get alphaMathComingSoon => 'alpha-math · 近日公開';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$ja
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'モーションを減らす';
  @override
  String get subtitleStill => '氷のように…静か？';
  @override
  String get subtitleFlow => '水のように流れる。';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$ja
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'リセットして終了';
  @override
  String get keepRepos => 'リポジトリを保持';
  @override
  String get wipeAll => 'すべて消去';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$ja
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'コマンド診断';
  @override
  String get networkFlowTelemetry => 'ネットワークフローのテレメトリ';
  @override
  String get clearSamples => 'サンプルを消去';
  @override
  String get clearMetrics => 'メトリクスを消去';
  @override
  String get clearTimings => '計測を消去';
  @override
  String get recalibrate => '再較正';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings => 'まだコマンドの計測がありません。通常のアクションを実行して診断を蓄積してください。';
  @override
  String get noBackendSamples =>
      'まだバックエンドコマンドのサンプルがありません。git や設定の操作を実行してこのログを蓄積してください。';
  @override
  String get noDiffSessions =>
      'まだ差分レンダーのセッションがありません。ファイル差分を開いてスクロールし、このパネルを蓄積してください。';
  @override
  String get noUiSessions =>
      'まだ UI 計測のセッションがありません。パネルを開いてルートを行き来し、このパネルを蓄積してください。';
  @override
  String get recentOperations => '最近の操作';
  @override
  String get recentBackendOperations => '最近のバックエンド操作';
  @override
  String get recentDiffSessions => '最近の差分セッション';
  @override
  String get recentUiTimings => '最近の UI 計測';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 個の固有コマンド',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 個のスコープ付きコマンド',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 個の計測イベント',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | ジャンク ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => ['コマンド', 'p50', '信頼性', '範囲'];
  @override
  List<String> get headersBackend => ['スコープ', 'p50', 'p95', '失敗'];
  @override
  List<String> get headersDiff => [
    'レンダラー',
    '初回描画',
    'フレーム p95',
    'ラスター p95',
    'ジャンク',
  ];
  @override
  List<String> get headersUi => ['イベント', 'p50', '失敗', '範囲'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$ja
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} サンプル',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} コマンド',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} セッション',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} イベント',
      );
  @override
  String stability({required Object pct}) => '${pct}% 安定性';
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
class _Translations$settings$flowEngine$ja
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => '実行フロー';
  @override
  String get description => 'コード上でオシレーターをシミュレートし、脆い実行パスがバグとして結晶化する前に洗い出します。';
  @override
  String get idle => 'アイドル';
  @override
  String get emptyOpenRepo => 'リポジトリを開くと\nフロー解析が見えます';
  @override
  String get scanning => 'スキャン中';
  @override
  String get analysing => 'レンズ内のファイルを\n解析中…';
  @override
  String get fragility => '脆さ';
  @override
  String get findings => '指摘';
  @override
  String get gap => '空白';
  @override
  String get clean => 'クリーン';
  @override
  String get severity => '深刻度';
  @override
  String get critical => '重大';
  @override
  String get warn => '警告';
  @override
  String get info => '情報';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$ja
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'ひらめきの火花 · すぐ次の一歩';
  @override
  String get current => '水中の流れ · 現在形の拡張';
  @override
  String get horizon => '地平線の向こうを見る · 手を伸ばす方向';
  @override
  String get fever => '熱にうかされた夢からの目覚め · 挑発';
  @override
  String get echo => '峡谷を渡るこだま · 他の場所の類例';
  @override
  String get vertigo => '崖の縁でのめまい · 隣接するリスク';
  @override
  String get ghost => 'かつてあったものの亡霊 · 歴史的な文脈';
  @override
  String get mirror => '静かな水面の鏡 · 反転';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$ja
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'CLI ピギーバック';
  @override
  String get clearCacheLabel => 'キャッシュを消去';
  @override
  String get clearCacheTooltip => 'キャッシュされたモデルを消去して再探査します。プロバイダーが外したものを一掃します。';
  @override
  String get refreshLabel => 'プロバイダーを更新';
  @override
  String get refreshTooltip => '今すぐすべてのプロバイダーを再探査します。';
  @override
  String get body => 'インターフェースのメッセージをローカルのプロバイダーバイナリへ直接パイプします。';
  @override
  String get cliTimeoutLabel => '実行ごとのタイムアウト';
  @override
  String get cliTimeoutUnitMinutes => '分';
  @override
  String get cliTimeoutUnitMinute => '分';
  @override
  String get forceStopLabel => 'すべてのセッションを停止';
  @override
  String get forceStopTooltip => '実行中の CLI をすべて強制終了します。';
  @override
  String get forceStopConfirmTitle => '実行中の CLI セッションを停止しますか？';
  @override
  String forceStopConfirmBody({required Object count}) =>
      '実行中の CLI ${count} 件を強制終了します。出力は失われます。';
  @override
  String get forceStopConfirmAction => 'すべて停止';
  @override
  String get forceStopNoneRunning => '実行中の CLI セッションはありません';
  @override
  String get forceStopRecordError => '停止： CLI セッションを強制終了しました。';
}

// Path: settings.header
class _Translations$settings$header$ja extends Translations$settings$header$en {
  _Translations$settings$header$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'ワークスペースの設定';
  @override
  String get subtitle =>
      'ワークスペース全体の、全体的な美観、インターフェースのダイナミクス、中核となる運用上の安全策を構成します。';
  @override
  String get releaseNotesTooltip => 'リリースノート';
  @override
  String get replayOnboardingTooltip => 'オンボーディングを再生';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$ja
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'パフォーマンス診断';
  @override
  String get copyTrace => 'トレースをコピー';
  @override
  String get offenderRanking => '問題要因ランキング';
  @override
  String get offenderRankingSubtitle => '各ストリームにおける遅延の要因。';
  @override
  String get noOffenders => 'まだ問題要因ランキングがありません。診断アクティビティを取得してこのリストを蓄積してください。';
}

// Path: settings.release
class _Translations$settings$release$ja
    extends Translations$settings$release$en {
  _Translations$settings$release$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'リリース配信';
  @override
  String get summary => '更新に関する設定。';
  @override
  String get deploymentChannel => '配信チャンネル';
  @override
  String get captureCrashDiagnostics => 'クラッシュ診断を取得';
  @override
  String get comingSoon => '近日公開。';
  @override
  String get checking => '確認中…';
  @override
  String get pollForUpdates => '更新を確認';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$ja
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => '検出中…';
  @override
  String get ready => '準備完了';
  @override
  String get notDetected => '未検出';
  @override
  String configured({required Object count}) => '${count} 件設定済み';
  @override
  String get notConfigured => '未設定';
  @override
  String get cliManaged => 'CLI 管理';
  @override
  String get connected => '接続済み';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} モデル',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} プロバイダー',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$ja
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get am => '午前';
  @override
  String get pm => '午後';
}

// Path: settings.offenders
class _Translations$settings$offenders$ja
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'コマンド';
  @override
  String get diffStream => '差分レンダー';
  @override
  String get uiStream => 'UI 計測';
  @override
  String rendererName({required Object mode}) => '${mode} レンダラー';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      'p95 ${p95}ms | 失敗 ${fail}%';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      'ジャンク ${jank}% | フレーム p95 ${frame}ms';
  @override
  String inStream({required Object stream}) => '${stream}内';
}

// Path: sync.actions
class _Translations$sync$actions$ja extends Translations$sync$actions$en {
  _Translations$sync$actions$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => '同期';
  @override
  String get syncOpenRepoDetail => 'リポジトリを開いてプッシュ・プル操作を管理します。';
  @override
  String get detachedHeadLabel => '分離 HEAD';
  @override
  String get detachedHeadDetail => 'プッシュ・プルの前にブランチをチェックアウトしてください。';
  @override
  String get publishBranchLabel => 'ブランチを公開';
  @override
  String publishBranchDetail({required Object branch}) =>
      '${branch}をプッシュして上流の追跡ブランチを設定します。';
  @override
  String get publishButtonLabel => '公開';
  @override
  String get syncBranchLabel => 'ブランチを同期';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => '${behindCount}をリベースでプルしてから${aheadCount}をプッシュします。';
  @override
  String get syncBranchButtonLabel => 'プル（リベース）してプッシュ';
  @override
  String get pushBranchLabel => 'ブランチをプッシュ';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      '${count}を${upstream}へプッシュします。';
  @override
  String get pushBranchButtonLabel => 'コミットをプッシュ';
  @override
  String get pullUpdatesLabel => '更新をプル';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      '${count}を${upstream}からプルします。';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      '${upstream}からフェッチして上流の状態を更新します。';
}

// Path: sync.panel
class _Translations$sync$panel$ja extends Translations$sync$panel$en {
  _Translations$sync$panel$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'リモートの状態を読み込み中';
  @override
  String get loadingMessage => 'ブランチの追跡情報を確認しています。';
  @override
  String get remoteStatusUnavailable => 'リモートの状態を取得できません';
  @override
  String get noUpstream => '上流なし';
  @override
  String get aheadLabel => '先行';
  @override
  String get behindLabel => '遅延';
  @override
  String get treeLabel => 'ツリー';
  @override
  String get runningSync => '同期を実行中…';
  @override
  String get fetching => 'フェッチ中…';
  @override
  String get fetchOnly => 'フェッチのみ';
  @override
  String get syncFailed => '同期に失敗しました';
  @override
  String get forcePushRecoveryLabel => '強制プッシュ（リース付き）';
  @override
  String get conflictsToResolveTitle => '解決が必要なコンフリクト';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} 件の解決が必要です：${list}';
  @override
  String get resolveConflicts => 'コンフリクトを解決';
  @override
  String get workingEllipsis => '処理中…';
  @override
  String lastActivity({required Object operation}) => '最終アクティビティ：${operation}';
  @override
  String get noOutput => '出力なし。';
  @override
  String resolvedConflicts({required Object count}) => '${count} 件解決しました。';
  @override
  String get cancelledUnchanged => 'キャンセルしました。作業ツリーは変更されていません。';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) => '${count} 件に未コミットの編集があります。リベース同期するには先にコミットしてください（${list}）。';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      '強制プッシュできません：「${branch}」に上流が設定されていません。';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$ja extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => '強制プッシュ（リース付き）しますか？';
  @override
  String target({required Object remote, required Object branch}) =>
      '対象：${remote}/${branch}';
  @override
  String get warning =>
      'リモートブランチをローカルの履歴で書き換えます。リース付きなので、前回のフェッチ以降に誰かがリモートへプッシュしていれば中止されますが、すでにフェッチ済みの変更は上書きされます。ブランチが分岐するリベースやアメンドを意図したときにのみ使用してください。';
  @override
  String get confirmButton => '強制プッシュ';
}

// Path: xray.board
class _Translations$xray$board$ja extends Translations$xray$board$en {
  _Translations$xray$board$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => '別のモジュールと共に動く';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 名のレビュアー',
      );
  @override
  String get territory => 'テリトリー';
  @override
  String get unreviewed => '未レビュー';
}

// Path: xray.cadence
class _Translations$xray$cadence$ja extends Translations$xray$cadence$en {
  _Translations$xray$cadence$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} コミット · ${days} 日\n${lines}';
  @override
  String burstTooltipSingle({required Object label, required Object n}) =>
      '${label}に ${n} コミット';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      '${n} 日の空白 · ${label}';
  @override
  String reflogTooltip({required Object label, required Object n}) =>
      '${label}に ${n} 件の reflog イベント';
}

// Path: xray.cards
class _Translations$xray$cards$ja extends Translations$xray$cards$en {
  _Translations$xray$cards$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$ja branchModel =
      _Translations$xray$cards$branchModel$ja._(_root);
  @override
  late final _Translations$xray$cards$bursty$ja bursty =
      _Translations$xray$cards$bursty$ja._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$ja hiddenRefs =
      _Translations$xray$cards$hiddenRefs$ja._(_root);
  @override
  late final _Translations$xray$cards$keystone$ja keystone =
      _Translations$xray$cards$keystone$ja._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$ja machineHistory =
      _Translations$xray$cards$machineHistory$ja._(_root);
  @override
  late final _Translations$xray$cards$migration$ja migration =
      _Translations$xray$cards$migration$ja._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$ja narrowHotspot =
      _Translations$xray$cards$narrowHotspot$ja._(_root);
  @override
  late final _Translations$xray$cards$noTags$ja noTags =
      _Translations$xray$cards$noTags$ja._(_root);
  @override
  late final _Translations$xray$cards$reflog$ja reflog =
      _Translations$xray$cards$reflog$ja._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$ja singleOwner =
      _Translations$xray$cards$singleOwner$ja._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$ja extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'ブランチ';
  @override
  String get bursty => 'バースト型';
  @override
  String get hiddenRefs => '隠れた ref';
  @override
  String get machineHeavy => 'マシン主体';
  @override
  String get migration => '移行';
  @override
  String get narrowHotspot => '狭いホットスポット';
  @override
  String get noTags => 'タグなし';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => '単独所有者';
}

// Path: xray.grain
class _Translations$xray$grain$ja extends Translations$xray$grain$en {
  _Translations$xray$grain$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => '最も粗い — トップレベルのモジュール';
  @override
  String get finest => '最も細かい粒度';
  @override
  String get mid => '中間の粒度';
  @override
  String get oneCharacteristic => '一つの特徴的なスケール';
}

// Path: xray.header
class _Translations$xray$header$ja extends Translations$xray$header$en {
  _Translations$xray$header$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'ダーティ';
  @override
  String get machineChip => 'マシン';
  @override
  String get refresh => '更新';
  @override
  String get refreshing => '更新中…';
  @override
  String get title => 'リポジトリ X-Ray';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$ja extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'クラスターの仲間';
  @override
  String get coChangers => '共変更するもの';
  @override
  String get keystone => 'キーストーン';
  @override
  String keystoneScore({required Object score}) => 'キーストーン  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$ja extends Translations$xray$inspector$en {
  _Translations$xray$inspector$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'ブランチ';
  @override
  String commitsHumanMachine({required Object n}) => '人間 · マシン ${n}';
  @override
  String get commitsLabel => 'コミット';
  @override
  String get confidenceLabel => '確信度';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'エンジン';
  @override
  String get gradientLabel => '勾配';
  @override
  String get harmonicLabel => '調和';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => '隠れた ref';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} マージ',
      );
  @override
  String get noTags => 'タグなし';
  @override
  String get notesLabel => 'ノート';
  @override
  String get openCommit => 'コミットを開く';
  @override
  String get pathLabel => 'パス';
  @override
  String remoteCount({required Object n}) => '${n} リモート';
  @override
  String get renamesLabel => 'リネーム';
  @override
  String scannedAt({required Object time}) => '${time}にスキャン';
  @override
  String selectedCount({required Object n}) => '${n} 件選択';
  @override
  String get shapeLinear => '線形';
  @override
  String get shapeMergeHeavy => 'マージ主体';
  @override
  String get shapeMostlyLinear => 'ほぼ線形';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} スタッシュ',
      );
  @override
  String get stressLabel => 'ストレス';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} タグ',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 作業ツリー',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$ja
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage => 'Git 履歴、ref、ペース、ホットスポットを調査中。';
  @override
  String get buildingTitle => 'リポジトリ X-Ray を構築中';
  @override
  String get idleMessage => 'パネルを再度開くと現在のリポジトリを調査します。';
  @override
  String get idleTitle => 'リポジトリ X-Ray';
  @override
  String get unavailableTitle => 'リポジトリ X-Ray を取得できません';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$ja extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => '半減期 ${n} 日';
}

// Path: xray.multi
class _Translations$xray$multi$ja extends Translations$xray$multi$en {
  _Translations$xray$multi$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} クラスター',
      );
  @override
  String clusterSingle({required Object id}) => 'クラスター ${id}';
  @override
  String couplingSuffix({required Object parts}) => '${parts} の結合';
  @override
  String externalCount({required Object n}) => '${n} 外部';
  @override
  String mutualCount({required Object n}) => '${n} 相互';
}

// Path: xray.recency
class _Translations$xray$recency$ja extends Translations$xray$recency$en {
  _Translations$xray$recency$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}日';
  @override
  String months({required Object n}) => '${n}か月';
  @override
  String get today => '今日';
  @override
  String weeks({required Object n}) => '${n}週';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        one: '${n}年',
        other: '${n}年',
      );
}

// Path: xray.rings
class _Translations$xray$rings$ja extends Translations$xray$rings$en {
  _Translations$xray$rings$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => '一つに溶け合った構造';
  @override
  String get hintSelfSimilar => '自己相似';
  @override
  String get oneBlendedBody => '一つに溶け合った構造 — まだ分離できるモジュールのスケールが解像されていません。';
  @override
  String get overHistory => '履歴を通して';
  @override
  String get parts => 'パーツ';
  @override
  String get readingHint => '構造を読み込み中…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} スケール',
      );
  @override
  String get scaleDissolved => '構造スケールが一つ消滅';
  @override
  String get scaleEmerged => '構造スケールが一つ出現';
  @override
  String get scaleSpectrum => 'スケールスペクトル';
  @override
  String get selfSimilarBody => '自己相似 — 構造がスケールをまたいで繰り返し、単一の特徴的なレベルがありません。';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '履歴上 ${n} 回のシフト',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 回の構造的シフト',
      );
  @override
  String get title => '成長リング';
  @override
  String get unavailable => '利用不可';
}

// Path: xray.stats
class _Translations$xray$stats$ja extends Translations$xray$stats$en {
  _Translations$xray$stats$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get alive => '生存';
  @override
  String get files => 'ファイル';
  @override
  String get lastTouched => '最終タッチ';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '所有者',
      );
  @override
  String get touches => 'タッチ';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$ja
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get current => '現在';
  @override
  String get legacy => 'レガシー';
  @override
  String get zone => 'リポジトリゾーン';
}

// Path: xray.summary
class _Translations$xray$summary$ja extends Translations$xray$summary$en {
  _Translations$xray$summary$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) => '解析に失敗しました：${error}';
  @override
  String get analyze => '解析';
  @override
  String get copied => 'サマリーをクリップボードにコピーしました。';
  @override
  String get directionHint => '方向';
  @override
  String get download => 'ダウンロード';
  @override
  String get emptyState =>
      'Logos 解析を実行して、このリポジトリの構造と領域をマッピングします。\n(tw: slop rn)';
  @override
  String get exit => '終了';
  @override
  String get generating => 'リポジトリを読み込み、特徴をクラスタリング中…';
  @override
  String get noModel => 'AI モデルが設定されていません。';
  @override
  String get noModelConfigured => 'AI モデルが設定されていません';
  @override
  String presentWith({required Object label}) => '${label}でプレゼント';
  @override
  String presentingWith({required Object label}) => '${label}でプレゼント中…';
  @override
  String get reanalyze => '再解析';
  @override
  String get saveDialogTitle => 'リポジトリサマリーを保存';
  @override
  String saveFailed({required Object error}) => '保存に失敗しました：${error}';
  @override
  String get savePresentationDialogTitle => 'プレゼンテーションを保存';
  @override
  String savedTo({required Object path}) => '${path}に保存しました';
}

// Path: xray.tabs
class _Translations$xray$tabs$ja extends Translations$xray$tabs$en {
  _Translations$xray$tabs$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'マップ';
  @override
  String get signals => 'シグナル';
  @override
  String get summary => 'サマリー';
  @override
  String get time => '時間';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$ja extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => '連結性';
  @override
  String events({required Object n}) => '${n} イベント';
  @override
  String get openInOrrery => 'Orrery で開く';
  @override
  String get readingHint => '履歴を読み込み中…';
  @override
  String snapshots({required Object n}) => '${n} スナップショット';
  @override
  String get steady => '安定 — このウィンドウに構造的イベントはありません。';
  @override
  String get title => '構造の軌道';
}

// Path: xray.verdict
class _Translations$xray$verdict$ja extends Translations$xray$verdict$en {
  _Translations$xray$verdict$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% 正準';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% 正準 · ${decisive}% 決定的';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$ja
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get manual => '手動';
  @override
  String get safe => '安全';
  @override
  String get guided => 'ガイド付き';
  @override
  String get assisted => '補助付き';
  @override
  String get full => '全面';
  @override
  String label({required Object label}) => '信頼：${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$ja
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get accept => '採用';
  @override
  String get other => '相手';
  @override
  String get both => '両方';
  @override
  String get navigate => '移動';
  @override
  String get jumpNext => '次へジャンプ';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$ja
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'マージ';
  @override
  String get cherryPick => 'チェリーピック';
  @override
  String get revert => 'リバート';
  @override
  String get resolve => '解決';
  @override
  String get switchOp => '切り替え';
  @override
  String get pull => 'プル';
  @override
  String get rebase => 'リベース';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      '${branch}を${base}にリベース';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$ja
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane => '近くに強い所有者が一人いる、最近の動き。';
  @override
  String get activeSeam => '近くの複数の手による、最近の動き。';
  @override
  String get stableOwnerLane => '支配的な所有者が一人いる、長寿命のレーン。';
  @override
  String get sharedLongLivedSeam => '時間をかけて積み重なった、共有の継ぎ目。';
  @override
  String get sharedLane => '単独の支配的な所有者がいない、共有レーン。';
  @override
  String get resolving => 'この行の周辺で履歴がまだ確定していません。';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$ja
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get hot => '活発';
  @override
  String get novel => '新規';
  @override
  String get contested => '競合';
  @override
  String get spreading => '拡散';
  @override
  String get stable => '安定';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$ja
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => '${concept}に属します';
  @override
  String get sitsInLocalSeam => 'ローカルの継ぎ目に位置します';
  @override
  String workedMostlyBy({required Object owner}) => '近くで主に ${owner} が手がけています';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '他 ${n} 箇所にエコーします',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      '次に ${path} を検査${detail}';
  @override
  String inspectDetail({required Object reason}) => '（${reason}）';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$ja
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get tight => '密着';
  @override
  String get close => '近接';
  @override
  String get loose => '緩やか';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$ja
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => '近傍の裏付け · ${label}';
  @override
  String localizedMove({required Object label}) => '局所的な動き · ${label}';
  @override
  String surprisingMove({required Object label}) => '意外な動き · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$ja
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => '安定した構造';
  @override
  String get conflictingSignals => '相反するシグナル';
  @override
  String get novelShape => '新規の形状';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$ja
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'テストの鏡像';
  @override
  String get semanticHistorySibling => '意味＋履歴の兄弟';
  @override
  String get recentCoChange => '最近の共変更';
  @override
  String get semanticSibling => '意味的な兄弟';
  @override
  String get relatedStructure => '関連する構造';
  @override
  String get tightlyBound => '密に結合';
  @override
  String get orbiting => '周回中';
  @override
  String get weaklyCoupled => '弱く結合';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$ja
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => '履歴トレイル';
  @override
  String get testMirrorLane => 'テスト鏡像レーン';
  @override
  String get structuralLane => '構造レーン';
  @override
  String get semanticNeighbourhood => '意味的近傍';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$ja
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => '重要度：高';
  @override
  String get importanceModerate => '重要度：中';
  @override
  String get mostlyAdditions => 'ほぼ追加';
  @override
  String get mostlyDeletions => 'ほぼ削除';
  @override
  String get tightlyCoupled => '密に結合したファイル';
  @override
  String get overlapsWorkingTree => '作業ツリーと重複';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$ja
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$ja open =
      _Translations$onboarding$repo$doors$open$ja._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$ja clone =
      _Translations$onboarding$repo$doors$clone$ja._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$ja create =
      _Translations$onboarding$repo$doors$create$ja._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$ja
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'URL からクローン';
  @override
  String get urlLabel => 'リポジトリ URL';
  @override
  String get targetLabel => '保存先フォルダー';
  @override
  String get browse => '参照…';
  @override
  String get clone => 'クローン';
  @override
  String get cloning => 'クローン中…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$ja
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'リポジトリを開く';
  @override
  String get createRepository => 'リポジトリを作成';
  @override
  String get cloneTarget => 'クローン先';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$ja
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL と保存先パスが必要です。';
  @override
  String get createFailed => 'リポジトリの作成に失敗しました。';
  @override
  String get cloneFailed => 'リポジトリのクローンに失敗しました。';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$ja
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'リポジトリ X-Ray';
  @override
  String get settings => '設定';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$ja
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'プロジェクト';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$ja
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} / ${total} ファイル';
  @override
  String stagedCount({required Object n}) => '${n} ステージ済み';
  @override
  String get commitMessageHint => 'コミットメッセージ…';
  @override
  String get commitAndPush => 'コミット＆プッシュ';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$ja
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get header => '履歴';
  @override
  String get viewingLast => '直近 20 コミットを表示中';
  @override
  String get inFlight => '進行中';
  @override
  String get you => 'あなた';
  @override
  String get commit1 => '飲み込む前に嗅ぐようキツネに教える';
  @override
  String get commit2 => 'アンバー：香りを一晩保つ';
  @override
  String get commit3 => 'キャベツを引退させアンバー＋ソーンに置き換える';
  @override
  String get commit4 => 'ソーンが門を守る';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$ja
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'ブランチ';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => '吸収済み';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ 追跡：${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$ja
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'あなた専用の Git クライアント。';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$ja
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'なぜ Flutter なのか？';
  @override
  String get body =>
      'これの最初のバージョンは Tauri 製（Rust + TypeScript）でした。もう動作が重いと感じていました。そんなとき、普段見ないストリームであるストリーマーが同じことを言っているのを耳にして、それがついに乗り換える後押しになりました。彼が Flutter を勧めたわけではなく、むしろ真逆でした。私は自分で Dart を見つけてプロトタイプを組み、起動時間が約 15 秒から 1 秒未満になりました。まさに雲泥の差です。Tauri 時代よ、さようなら。\n\nFlutter のレンダリングパイプラインは DOM よりもゲームエンジンに近く、UI そのものが製品であるデスクトップアプリにとっては、それがすべてです。Dart も本当に良い言語だとわかりました。スペクトルエンジンの背後にある数学はまず Rust でプロトタイプしていたので、その成果はそのまま引き継げました。\n\nFlutter は既定でクロスプラットフォームなのが素晴らしいですが、Google 的なところがあるので、いくつかの癖はあります。';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$ja
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'スペクトルエンジンとは？';
  @override
  String get body =>
      'コミットするたびに、一緒に変更したファイルが時間をかけてパターンを形づくります。スペクトルエンジンはあなたのコミットグラフを読み取り、その共変更パターンを信号へと分解します。どのファイルがどれだけ密に結合しているか、そしてリポジトリの中でどんな構造的役割を果たしているかを。要は開発履歴に対するスペクトル解析です。Git クライアントの中で。あえて。\n\nこの数学は新しいので、私はゲームの手触りのように扱っています。調整し、試し、直し、信号が正しく感じられるまで続けるのです。\n\nそれらの信号がすべてに供給されます。履歴の地震計、コミット件名の下に描かれるバー、レビューシステム、Muse、ファイルの星座。アプリ全体がこの層から上へと推論します。逆ではありません。';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$ja
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'これはどこへ向かうのか？';
  @override
  String get body =>
      '最初のマイルストーンは、GitHub Desktop、SourceTree、GitKraken との完全な同等性です。高速に感じられ、基本を何よりもうまくこなすクロスプラットフォームの Git クライアント。それはほぼ実現しています。スペクトルエンジンは、他のクライアントでは手動で考えさせられる操作において、すでに優位性をもたらしています。\n\nその先の目標は、速度、アクセシビリティ、知性、そして全体的な UX において、他のあらゆる Git クライアントを凌駕することです。ここで発表されている以上のものが、まだパイプラインに控えています。';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$ja
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$ja verbLed =
      _Translations$settings$commitPreview$title$verbLed$ja._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$ja
  descriptive = _Translations$settings$commitPreview$title$descriptive$ja._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$ja narrative =
      _Translations$settings$commitPreview$title$narrative$ja._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$ja
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$ja verbLed =
      _Translations$settings$commitPreview$base$verbLed$ja._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$ja
  descriptive = _Translations$settings$commitPreview$base$descriptive$ja._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$ja narrative =
      _Translations$settings$commitPreview$base$narrative$ja._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$ja
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$ja
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$ja._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$ja
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$ja._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$ja
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$ja._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$ja
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$ja
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$ja._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$ja
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$ja._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$ja
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$ja._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$ja
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim => 'このリポジトリには、ブランチを意識したナビゲーションが報われるだけのブランチの広がりがあります。';
  @override
  String get broadTitle => 'ブランチモデルに広がりがある';
  @override
  String localBranchesDetail({required Object count}) => 'ローカルブランチ ${count} 件。';
  @override
  String get localBranchesLabel => 'ローカルブランチ';
  @override
  String remoteBranchesDetail({required Object count}) =>
      'リモートブランチ ${count} 件。';
  @override
  String get remoteBranchesLabel => 'リモートブランチ';
  @override
  String get simpleClaim => '見えているブランチモデルは狭いです。';
  @override
  String get simpleTitle => 'シンプルなブランチモデル';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$ja
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '作業は平坦な日々のリズムではなく、集中したバーストで着地しています。';
  @override
  String get title => 'バースト型の開発ペース';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$ja
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} 件の ref が通常のブランチ／タグ空間の外に存在します。';
  @override
  String evidenceDetail({required Object count}) =>
      'heads/remotes/tags の外に ${count} 件の ref。';
  @override
  String get evidenceLabel => '隠れた ref';
  @override
  String get namespacesLabel => '名前空間';
  @override
  String get title => '隠れた Git 名前空間';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$ja
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String claim({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '少数のファイルが、タッチ回数に比べて不釣り合いな共変更の重みを担っています。',
      );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 回タッチ · pull φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ja'))(
        n,
        other: '${n} 件のキーストーン橋ファイル',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$ja
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'チェックポイント型のコミットが、素朴な履歴指標を大きく歪めています。';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} コミットがマシン／セッションのパターンに一致しました。';
  @override
  String get machineCommitsLabel => 'マシンコミット';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '生 ${raw} コミット 対 フィルター済み ${filtered} コミット。';
  @override
  String get rawVsFilteredLabel => '生 対 フィルター済み';
  @override
  String get title => 'マシン履歴が生の指標を支配';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$ja
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      '履歴が `${older}` から `${newer}` へ移行しており、スタックや表層の移行を示唆しています。';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} 回タッチ、最終アクティブ ${lastActive}。';
  @override
  String get title => 'アーキテクチャの移行が見える';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$ja
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '少数のファイルとディレクトリが、不釣り合いな割合の変更を吸収しています。';
  @override
  String get title => 'ホットスポットの集中が狭い';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path}は、見えているホットスポット集合の ${pct}% を占めます。';
  @override
  String get topHotspotLabel => 'トップホットスポット';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      'この履歴スライスに ${count} 名の作者。';
  @override
  String get visibleAuthorsLabel => '見えている作者';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$ja
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'Git タグが、可視のリリースやマイルストーンの層として使われていません。';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} 件のリモートエンドポイントが設定されています。';
  @override
  String get remoteEndpointsLabel => 'リモートエンドポイント';
  @override
  String get tagCountDetail => 'タグは 0 件です。';
  @override
  String get tagCountLabel => 'タグ数';
  @override
  String get title => '正式なリリース／タグの跡がない';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$ja
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'reflog の量は、公開されたコミット以上に局所的な反復が集中していることを示唆しています。';
  @override
  String get peakReflogDayLabel => 'reflog のピーク日';
  @override
  String get title => '激しいローカル編集セッション';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$ja
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` は、明確に見える作者が一人だけの、頻繁にタッチされる${kind}です。';
  @override
  String ownerCountDetail({required Object count}) => '${count} 名の異なる作者。';
  @override
  String get ownerCountLabel => '所有者数';
  @override
  String get title => '単独所有者のホットスポット';
  @override
  String get touchCountLabel => 'タッチ回数';
  @override
  String touchDetailFiltered({required Object count}) =>
      'フィルター済み履歴で ${count} 回タッチ。';
  @override
  String touchDetailRaw({required Object count}) => '生履歴で ${count} 回タッチ。';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$ja
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '開く';
  @override
  String get subtitle => '既存';
  @override
  String get hint => 'すでにあるもの';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$ja
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'クローン';
  @override
  String get subtitle => 'URL から';
  @override
  String get hint => 'リモート URL を貼り付け';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$ja
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get title => '作成';
  @override
  String get subtitle => '新規';
  @override
  String get hint => '新しく始める';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$ja
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'キツネに、匂いのおかしいクッキーは飛ばさせる';
  @override
  String get s2 => '飲み込む前に、細工されたクッキーを拒むようキツネを鍛える';
  @override
  String get s3 => '門で一つ残らず精密に検分するようキツネに強いる';
  @override
  String get def => '悪いクッキーを拒むようキツネに教える';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$ja
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'キツネが今クッキーを選ぶようになった';
  @override
  String get s2 => 'クッキー検分の手順、キツネに叩き込み済み';
  @override
  String get s3 => 'クッキー精査の鑑識、反復でキツネに埋め込み済み';
  @override
  String get def => 'クッキー嗅ぎ分けの手順、キツネに導入済み';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$ja
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'キツネは匂いのおかしいクッキーを飛ばし始めた';
  @override
  String get s2 => 'キツネと腰を据えて、どのクッキーを拒むか一つずつ整理した';
  @override
  String get s3 => '午後の大半を費やして、差し出されるクッキーがすべて善意のクッキーとは限らないとキツネを説き伏せた';
  @override
  String get def => '食べる前にクッキーを嗅ぐようキツネに頼んだ';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$ja
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'キツネがちらり。おかしいものは残す。';
  @override
  String get s2 => 'キツネが各トークンを検分し、匂いのおかしいものを断り、その拒否をポーチに記す。';
  @override
  String get s3 => 'キツネが各トークンを回り込み、三つの角度から空気を確かめ、おかしいと読めたものを断り、拒否が定着するよう一拍待つ。';
  @override
  String get def => 'キツネは今、各トークンを嗅いで、怪しいものを丁重に断る。';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$ja
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '変なやつには、だいたい甘めの通し。';
  @override
  String get s2 => '匂いのおかしい各トークンへの、ポーチから発せられ記録された、文書化された拒否。';
  @override
  String get s3 => '匂いのおかしいトークンごとの、片足を上げもう片足は据えたまま、ポーチから発せられた公証済みの拒否。';
  @override
  String get def => '怪しいトークンへの、ポーチから発せられる丁重な拒否。';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$ja
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$ja._(TranslationsJa root)
    : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'キツネはなんとなく変なやつを食べるのをやめた。簡単。';
  @override
  String get s2 => '以前はどのトークンもろくに考えず飲み込まれていたが、今は一拍おき、きちんと見て、しっくりこないものは断る。';
  @override
  String get s3 =>
      '以前はどのトークンも考えずに飲み込まれていた。今は、一拍。空気を吸い込む。空気を、留める。キツネはポーチの板が、何かおかしいときに時折見せる小さな震えを見つめ、そのときだけ判断が下される。';
  @override
  String get def => '以前はどのトークンも儀式なく飲み込まれていたが、今はまず一嗅ぎ。';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$ja
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' ポーチは問題なし。裏庭はどうでもいい。';
  @override
  String get s2 => ' 拒否のたびにポーチを掃く。裏庭の泥は定められた時間内なら許可。';
  @override
  String get s3 => ' ポーチは掃いて掃き直す。裏庭の泥は足跡と天気で分類され、キツネは以前より長く敷居にとどまる。';
  @override
  String get def => ' ポーチはきれいに保たれ、裏庭は泥の権利を保つ。';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$ja
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' ポーチはオーケー。裏庭は裏庭のことをする。';
  @override
  String get s2 => ' ポーチは証拠クリーンゾーンとして、裏庭は指定の泥ゾーンとして、時間は掲示済み。';
  @override
  String get s3 =>
      ' ポーチは証拠級のクリーンルームとして、裏庭は分類済みの泥のアーカイブとして、敷居はキツネが立ち止まり考えすぎる場所として。';
  @override
  String get def => ' きれいなポーチ、裏庭には保たれた泥の権利。';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$ja
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' ポーチは問題なかった。裏庭は、さあどうだか。';
  @override
  String get s2 => ' あとでポーチはきれいに保たれ、キツネは裏庭へ退いた。そこが考えごとの場所だ。';
  @override
  String get s3 =>
      ' その晩ポーチは二度こすられた。キツネは裏庭をゆっくり歩き、いつもと同じ柵の杭で立ち止まり、ポーチが何か借りでもあるかのように振り返った。';
  @override
  String get def => ' ポーチはきれいなままだが、威厳では裏庭がなお勝つ。';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$ja
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' アンバーはそこにいる。ドリフトは漂う。ソーンは必要なら刺す。だいたい何もない。';
  @override
  String get s2 =>
      ' アンバーが各匂いを検分のため保持。ドリフトがその日の空気を門のソーンへ運び、ソーンが夕方の集計のため各拒否に印を付ける。';
  @override
  String get s3 =>
      ' アンバーが各匂いを保持し、時刻によって異なる重みを与える。ドリフトが、どうでもいいはずなのに効いてくる角度でポーチを抜ける。門のソーンは拒否に一度、キツネがあやうく見逃したものに二度刺し、他の誰も分からなくてもキツネはその違いが分かる。';
  @override
  String get def => ' アンバーが匂いを保持。ドリフトがそれを運ぶ。門のソーンが通してはならないものを捕らえる。';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$ja
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 杭にアンバー。空気にドリフト。門にソーン。問題なし。';
  @override
  String get s2 =>
      ' アンバーは指定の匂いの証人として、ドリフトは記録された環境として、ソーンの印はその日の拒否記録として、夕暮れに突き合わせ。';
  @override
  String get s3 =>
      ' アンバーは、その沈黙自体が一つの読み取りとなる匂いの証人として、ドリフトは、何かおかしい日にはおかしく動くパターン化された環境として、ソーンは、キツネが寝る前と夜明け前に確かめる印を刻む門の集計係として。';
  @override
  String get def => ' アンバーは匂いの証人として、ドリフトは環境の文脈として、ソーンは門の静かな拒否の印として。';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$ja
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$ja._(
    TranslationsJa root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsJa _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' アンバーはそのへんにいた。ドリフトは来ては去った。ソーンは静かに仕事をした。まあ、のんびりしたものだ。';
  @override
  String get s2 => ' アンバーがその日の匂いの記録をつけ、ドリフトは方向と時刻で記され、ソーンの印は集計されポーチに副署された。';
  @override
  String get s3 =>
      ' アンバーが匂いの記録をつけたが、キツネは特定の朝にはそれが重く感じると言い張る。ドリフトはいつものようにポーチを抜けた、つまり肝心な日にはおかしく。門のソーンは各拒否に印を付け、キツネは夜明けに出てそれを数えた、すでに数えた階段をもう一度数えるように。';
  @override
  String get def => ' アンバーが匂いの記録を保ち、ドリフトが空気を運び、門のソーンが捕らえるべきものを捕らえた。';
}
