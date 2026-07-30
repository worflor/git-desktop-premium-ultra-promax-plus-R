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
class TranslationsKo extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsKo({
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
             locale: AppLocale.ko,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <ko>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsKo _root = this; // ignore: unused_field

  @override
  TranslationsKo $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsKo(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$ko app = _Translations$app$ko._(_root);
  @override
  late final _Translations$backend$ko backend = _Translations$backend$ko._(
    _root,
  );
  @override
  late final _Translations$branches$ko branches = _Translations$branches$ko._(
    _root,
  );
  @override
  late final _Translations$changes$ko changes = _Translations$changes$ko._(
    _root,
  );
  @override
  late final _Translations$common$ko common = _Translations$common$ko._(_root);
  @override
  late final _Translations$diff$ko diff = _Translations$diff$ko._(_root);
  @override
  late final _Translations$filament$ko filament = _Translations$filament$ko._(
    _root,
  );
  @override
  late final _Translations$history$ko history = _Translations$history$ko._(
    _root,
  );
  @override
  late final _Translations$historySurgery$ko historySurgery =
      _Translations$historySurgery$ko._(_root);
  @override
  late final _Translations$onboarding$ko onboarding =
      _Translations$onboarding$ko._(_root);
  @override
  late final _Translations$orrery$ko orrery = _Translations$orrery$ko._(_root);
  @override
  late final _Translations$palette$ko palette = _Translations$palette$ko._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$ko releaseNotes =
      _Translations$releaseNotes$ko._(_root);
  @override
  late final _Translations$repoSummary$ko repoSummary =
      _Translations$repoSummary$ko._(_root);
  @override
  late final _Translations$review$ko review = _Translations$review$ko._(_root);
  @override
  late final _Translations$settings$ko settings = _Translations$settings$ko._(
    _root,
  );
  @override
  late final _Translations$sync$ko sync = _Translations$sync$ko._(_root);
  @override
  late final _Translations$xray$ko xray = _Translations$xray$ko._(_root);
}

// Path: app
class _Translations$app$ko extends Translations$app$en {
  _Translations$app$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => '설정';
  @override
  String get panelReleaseNotes => '릴리스 노트';
  @override
  String get panelFilamentFindings => 'Filament 발견';
  @override
  String get filamentFindingsUpper => 'FILAMENT 발견';
  @override
  late final _Translations$app$cheatsheet$ko cheatsheet =
      _Translations$app$cheatsheet$ko._(_root);
  @override
  String get commandPaletteTooltip => '명령 팔레트   /';
  @override
  String get newDeskFallback => '새 Desk';
  @override
  String get deskFallback => 'Desk';
  @override
  String get currentDeskFallback => '현재';
  @override
  String get noRepositoryOpen => '열린 저장소 없음';
  @override
  String couldntOpenAsDesk({required Object error}) => 'Desk로 열 수 없음: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      '포지를 감지할 수 없음: ${error}';
  @override
  String get cannotFetchPrNoForge => 'PR을 가져올 수 없음: 이 저장소에서 포지가 감지되지 않았습니다.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '원격의 최신 내용으로 ${ref} 덮어쓰기?';
  @override
  String get overwrite => '덮어쓰기';
  @override
  String couldntFetchPr({required Object error}) => 'PR을 가져올 수 없음: ${error}';
  @override
  String get promoteDeskToPr => 'Desk를 PR로 승격';
  @override
  String get applyToMain => 'main에 적용';
  @override
  String updateDeskFrom({required Object source, required Object target}) =>
      '${source}에서 ${target} 업데이트';
  @override
  String bringChangesFromHere({required Object source}) =>
      '${source}에서 변경을 여기로 가져오기';
  @override
  String get editLocalPr => '로컬 PR 편집';
  @override
  String get discardLocalPr => '로컬 PR 버리기';
  @override
  String get closeDesk => 'Desk 닫기';
  @override
  String couldntPromote({required Object error}) => '승격할 수 없음: ${error}';
  @override
  String get commitOrShelveBeforeApplying => '적용 전에 Desk의 변경을 커밋하거나 보류하십시오.';
  @override
  String get couldNotResolveMainWorktree => '메인 작업 트리 경로를 확인할 수 없습니다.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Desk를 승격할 수 없음: ${error}';
  @override
  String get couldntDetermineBaseBranch => '이 Desk의 기준 브랜치를 결정할 수 없습니다.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'PR base와 head가 같은 브랜치(${branch})입니다 — 적용할 것이 없습니다.';
  @override
  String appliedBranchToBase({required Object base, required Object branch}) =>
      '${base}에 ${branch} 적용됨';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object source,
    required Object target,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
    n,
    other: '${source} 기준으로 ${target} 업데이트 (커밋 ${n}개).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-forward가 깔끔하게 처리되지 않았습니다 — 대신 패치 미리보기를 표시합니다.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object source,
    required Object target,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
    n,
    other: '${source} 대비 ${target} 커밋 ${n}개 앞섬.',
  );
  @override
  String deskUpToDate({required Object source, required Object target}) =>
      '${source} 기준 ${target} 이미 최신입니다.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      '${target}에 커밋되지 않은 변경 — 대신 패치로 미리봅니다.';
  @override
  String updateDeskFromLower({
    required Object source,
    required Object target,
  }) => '${source}에서 ${target} 업데이트';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      '${source}에서 가져올 업데이트가 없습니다.';
  @override
  String get updatePrepFailed => '업데이트 준비 실패';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => '${source}의 변경을 ${target}에 가져오기';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      '${source}에서 ${target}에 가져올 패치 가능한 변경이 없습니다.';
  @override
  String get patchPrepFailed => '패치 준비 실패';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => '제목';
  @override
  String get bodyHint => '본문';
  @override
  String get bodyOptionalHint => '본문 (선택)';
  @override
  String get draftLower => '초안';
  @override
  String get cancelLower => '취소';
  @override
  String get saveLower => '저장';
  @override
  String couldntSave({required Object error}) => '저장할 수 없음: ${error}';
  @override
  String get stashedNoOtherDesk =>
      '변경을 스태시했습니다 — 적용할 다른 Desk가 없습니다. git stash pop으로 복구하십시오.';
  @override
  String get suggestedSource => '추천 소스';
  @override
  String tooltipModifiedCount({required Object n}) => '${n}개 수정됨';
  @override
  String tooltipAheadCount({required Object n}) => '${n}개 앞섬';
  @override
  String tooltipBehindCount({required Object n}) => '${n}개 뒤처짐';
  @override
  String get focusedEdits => '집중된 편집';
  @override
  String get editsSpreadAcrossSubsystems => '여러 서브시스템에 퍼진 편집';
  @override
  String get editsTouchingManySubsystems => '많은 서브시스템을 건드리는 편집';
  @override
  String get focusedBranch => '집중된 브랜치';
  @override
  String get branchSpansMultipleSubsystems => '여러 서브시스템에 걸친 브랜치';
  @override
  String get structurallyDivergentFromMainline => '메인라인과 구조적으로 갈라짐';
  @override
  String get localPr => '로컬 PR';
  @override
  String lastTouched({required Object time}) => '마지막 터치 ${time}';
  @override
  String driftGroupCount({required Object dir, required Object n}) =>
      '${dir}에 ${n}개';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => '커밋되지 않은 변경';
  @override
  String get closeDeskQuestion => 'Desk를 닫으시겠습니까?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '커밋되지 않은 파일 ${n}개.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: 'main보다 커밋 ${n}개 앞섬.',
      );
  @override
  String get willRemoveWorktreeDirectory => '작업 트리 디렉터리가 제거됩니다.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개 변경됨',
      );
  @override
  String get shelveHere => '여기에 보류';
  @override
  String get discardAndClose => '버리고 닫기';
  @override
  String get noRepository => '저장소 없음';
  @override
  String get issuePromotedToRemote => '이슈가 원격으로 승격됐습니다.';
  @override
  String get pushedToRemote => '원격에 푸시했습니다.';
  @override
  String get pulledFromRemote => '원격에서 풀했습니다.';
  @override
  String get remoteIssueNotFound => '원격 이슈를 찾을 수 없음';
  @override
  String importedIssueLocally({required Object id}) => '#${id} 로컬로 가져옴.';
  @override
  String get issueAbandoned => '이슈를 포기했습니다.';
  @override
  String get abandonIssue => '이슈 포기';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      '로컬 이슈 #${id}을(를) 영구 제거하시겠습니까? ref가 삭제되며 되돌릴 수 없습니다.';
  @override
  String get abandon => '포기';
  @override
  String publishedBranch({required Object branch}) => '${branch} 게시됨.';
  @override
  String get publishingEllipsis => '게시 중…';
  @override
  String get publish => '게시';
  @override
  String get noRemoteConfigured => '이 저장소에 구성된 원격이 없습니다.';
  @override
  String get jumpToDesk => 'Desk로 이동';
  @override
  String get arrowOpen => '→ 열기';
  @override
  String get openOnANewDesk => '새 Desk에서 열기';
  @override
  String get plusDesk => '+ Desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'new-branch-name';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ 새 Desk';
  @override
  String get fromHeadEllipsis => 'HEAD에서…';
  @override
  String get viewAllBranches => '모든 브랜치 보기';
  @override
  String get issuesLower => '이슈';
  @override
  String get newIssueLower => '새 이슈';
  @override
  String get noneLinked => '연결 없음';
  @override
  String get noOpenIssues => '열린 이슈 없음';
  @override
  String get createAndPushLower => '생성 + 푸시';
  @override
  String get createLower => '생성';
  @override
  String get remoteLower => '원격';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => '원격으로 승격';
  @override
  String get pushToRemote => '원격에 푸시';
  @override
  String get pullFromRemote => '원격에서 풀';
  @override
  String get importLabel => '가져오기';
  @override
  String get failedToCreateRepository => '저장소 생성에 실패했습니다.';
  @override
  String get openRepositoryLower => '저장소 열기';
  @override
  String get newRepositoryLower => '새 저장소';
  @override
  String get back => '뒤로';
  @override
  String get openRepositoryDialogTitle => '저장소 열기';
  @override
  String get createRepositoryDialogTitle => '저장소 생성';
  @override
  String get cloneTargetDialogTitle => '클론 대상';
  @override
  String get cloneToDialogTitle => '클론 위치';
  @override
  String get exportToDialogTitle => '내보내기 위치';
  @override
  String get createFromTemplateInDialogTitle => '템플릿에서 생성 위치';
  @override
  String get notAGitRepoInitConfirm => 'git 저장소가 아닙니다. 여기에 초기화하시겠습니까?';
  @override
  String get repositoryUrlRequired => '저장소 URL이 필요합니다.';
  @override
  String get failedToCloneRepository => '저장소 클론에 실패했습니다.';
  @override
  String cloningEllipsis({required Object name}) => '${name} 클론 중…';
  @override
  String get cloneCancelled => '클론이 취소됐습니다.';
  @override
  String get noProjectsYet => '아직 프로젝트가 없습니다';
  @override
  String get dissolveGroup => '그룹 해체';
  @override
  String get projectsHeader => '프로젝트';
  @override
  String get cloneLabel => '클론';
  @override
  String get createLabel => '생성';
  @override
  String get openLabel => '열기';
  @override
  String get repositoryUrlPlaceholder => '저장소 URL';
  @override
  String get projectNameOrFullPathPlaceholder => 'project-name 또는 전체 경로';
  @override
  String get pathToProjectPlaceholder => '/path/to/project';
  @override
  String get cloneToFolderPathPlaceholder => '클론할 폴더 경로';
  @override
  String get switchToCreateRepo => '저장소 생성으로 전환';
  @override
  String get explorer => '탐색기';
  @override
  String get terminal => '터미널';
  @override
  String get cloneUrl => '클론 URL';
  @override
  String get copyPath => '경로 복사';
  @override
  String get export => '내보내기';
  @override
  String get readme => 'README';
  @override
  String get duplicate => '복제';
  @override
  String get template => '템플릿';
  @override
  String get forgetThisProject => '이 프로젝트 지우기';
  @override
  String get aiKindCommitMessage => '커밋 메시지';
  @override
  String get aiKindReview => '리뷰';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => '발표';
  @override
  String get aiKindDebug => '디버그';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} 실행 중';
  @override
  String aiStatusFailedUnread({required Object kind}) => '${kind} 실패 (안 읽음)';
  @override
  String aiStatusReadyUnread({required Object kind}) => '${kind} 준비됨 (안 읽음)';
  @override
  String get filesLower => '파일';
  @override
  String get commitsLower => '커밋';
  @override
  String get undoLabel => '실행 취소';
  @override
  String get goLabel => '실행';
  @override
  String countdownSeconds({required Object n}) => '${n}초';
  @override
  String get collapseGlyph => '▲ 접기';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n}줄 더';
}

// Path: backend
class _Translations$backend$ko extends Translations$backend$en {
  _Translations$backend$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$ko ops = _Translations$backend$ops$ko._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$ko mergeOutcome =
      _Translations$backend$mergeOutcome$ko._(_root);
}

// Path: branches
class _Translations$branches$ko extends Translations$branches$en {
  _Translations$branches$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'AI 리뷰 실행 중…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => '발견';
  @override
  String get observations => '관찰';
  @override
  String get renameEllipsis => '이름 변경…';
  @override
  String get publish => '게시';
  @override
  String publishFailed({required Object error}) => '게시 실패: ${error}';
  @override
  String couldntOpenDesk({required Object error}) => 'Desk를 열 수 없음: ${error}';
  @override
  String syncFailed({required Object error}) => '동기화 실패: ${error}';
  @override
  String get renameBranchTitle => '브랜치 이름 변경';
  @override
  String get newNameHint => '새 이름';
  @override
  String get rename => '이름 변경';
  @override
  String invalidBranchName({required Object name}) =>
      '유효하지 않은 브랜치 이름: \'${name}\'.';
  @override
  String renameFailed({required Object error}) => '이름 변경 실패: ${error}';
  @override
  String deletingBranch({required Object name}) => '${name} 삭제 중';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' 브랜치가 Desk \'${desk}\'에서 열려 있습니다.';
  @override
  String get openDesk => 'Desk 열기';
  @override
  String openInDeskShort({required Object desk}) => 'Desk \'${desk}\'에서 열기';
  @override
  String get couldNotPinBranch => '브랜치 팁을 고정할 수 없음, 삭제 건너뜀';
  @override
  String get couldNotPinTag => '태그를 고정할 수 없음, 삭제 건너뜀';
  @override
  String deletingTag({required Object name}) => '태그 ${name} 삭제 중';
  @override
  String get applyToActiveChanges => '활성 변경에 적용…';
  @override
  String get couldNotLoadPrDiff => 'PR diff를 불러올 수 없습니다.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => '${branch}에 머지…';
  @override
  String get checkoutThisPr => '이 PR 체크아웃';
  @override
  String get mergeIntoNewDesk => '새 Desk에 머지…';
  @override
  String get pushToForge => '포지에 푸시';
  @override
  String get linkToIssue => '이슈에 연결…';
  @override
  String get gitPatch => '↓ git 패치';
  @override
  String get copyBranchName => '브랜치 이름 복사';
  @override
  String copiedRef({required Object ref}) => '"${ref}" 복사됨';
  @override
  String get reviewPr => 'PR 리뷰';
  @override
  String get openInBrowser => '브라우저에서 열기';
  @override
  String get markAsRead => '읽음으로 표시';
  @override
  String get markAsUnread => '안 읽음으로 표시';
  @override
  String get replaceLocalCommitsTitle => '로컬 커밋을 교체하시겠습니까?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref}에 원격 PR head에 없는 로컬 커밋이 있습니다. 업데이트하면 원격의 최신 내용으로 교체됩니다.';
  @override
  String get update => '업데이트';
  @override
  String couldntFetchPr({required Object error}) => 'PR을 가져올 수 없음: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) => 'Desk로 열 수 없음: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      '브라우저에서 열 수 없음: ${error}';
  @override
  String get noIssuesYetLocal =>
      '아직 이슈가 없습니다. 업스트림에서 하나 열거나, 이슈 렌즈에서 "+ new local issue"를 사용하십시오.';
  @override
  String get remotePrsLinkLocalOnly =>
      '원격 PR은 로컬 이슈에만 연결할 수 있습니다. "+ new local issue"로 하나 생성하십시오.';
  @override
  String linkPrToIssues({required Object number}) => 'PR #${number} 이슈에 연결';
  @override
  String get noPrsYetLocal => '아직 PR이 없습니다. 업스트림에서 하나 열거나, Desk를 PR로 승격하십시오.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      '원격 이슈는 로컬 PR에만 연결할 수 있습니다. 먼저 Desk를 PR로 승격하십시오.';
  @override
  String linkIssueToPrs({required Object number}) => '이슈 #${number} PR에 연결';
  @override
  String couldntToggleLink({required Object error}) => '연결을 토글할 수 없음: ${error}';
  @override
  String get openPatchDialogTitle => '패치 열기 (.patch / .diff)';
  @override
  String get clipboardNoText => '클립보드에 텍스트가 없습니다.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) => '패치 열기 실패: ${error}';
  @override
  String get patchEmptyOrUnparseable => '패치가 비어 있거나 파싱할 수 없습니다.';
  @override
  String get prPushedToForge => 'PR을 포지에 푸시했습니다.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '원격의 최신 내용으로 ${ref} 덮어쓰기?';
  @override
  String get overwrite => '덮어쓰기';
  @override
  String get loadingBranchesTitle => '브랜치 불러오는 중';
  @override
  String get loadingBranchesMessage => '로컬 브랜치와 태그를 읽는 중.';
  @override
  String get branchesUnavailableTitle => '브랜치를 사용할 수 없음';
  @override
  String get filterPullRequestsHint => '풀 리퀘스트 필터…';
  @override
  String get filterIssuesHint => '이슈 필터…';
  @override
  String get branchNameHint => '브랜치 이름';
  @override
  String get tagsNewestFirst => '태그, 최신순';
  @override
  String get tagsOldestFirst => '태그, 오래된순';
  @override
  String get flipSortDirection => '정렬 방향 뒤집기';
  @override
  String get readingPullRequests => '풀 리퀘스트 읽는 중…';
  @override
  String get noOpenPullRequests => '열린 풀 리퀘스트 없음';
  @override
  String get noPullRequestsHint => '브랜치에서 하나 열거나, Desk를 승격하십시오.';
  @override
  String get noPrsMatchFilters => '이 필터에 맞는 PR이 없습니다';
  @override
  String get toggleFiltersRowAbove => '위 행에서 필터를 끄십시오.';
  @override
  String get issuesNewestFirst => '이슈, 최신순';
  @override
  String get issuesOldestFirst => '이슈, 오래된순';
  @override
  String get issuesHeading => '이슈';
  @override
  String get readingIssuesLower => '이슈 읽는 중…';
  @override
  String get noOpenIssues => '열린 이슈 없음';
  @override
  String get noIssuesHint => '작업과 버그 추적을 위해 + new.';
  @override
  String get nothingMatches => '일치하는 항목 없음';
  @override
  String get toggleFiltersAbove => '위에서 필터를 끄십시오.';
  @override
  String get bucketFresh => '신선함';
  @override
  String get bucketThisWeek => '이번 주';
  @override
  String get bucketStalled => '정체됨';
  @override
  String get bucketOlder => '더 오래됨';
  @override
  String get couldNotResolveMainWorktree => '메인 작업 트리 경로를 확인할 수 없습니다.';
  @override
  String couldntSubmitReview({required Object error}) =>
      '리뷰를 제출할 수 없음: ${error}';
  @override
  String get reviewAiNotAvailable => '리뷰 AI를 아직 사용할 수 없습니다.';
  @override
  String get noReviewModelConfigured => '구성된 리뷰 모델이 없습니다.';
  @override
  String get deskFallback => 'Desk';
  @override
  String deskUncommittedChanges({required num n, required Object branch}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${branch}에 커밋되지 않은 변경 ${n}개 — 먼저 커밋하거나 스태시하십시오.',
      );
  @override
  String get targetDeskNoBranch => '대상 Desk에 브랜치가 없습니다.';
  @override
  String mergePrIntoDesk({required Object branch, required Object number}) =>
      '${branch}에 PR #${number} 머지';
  @override
  String get conflictCheckUnavailableVersion =>
      '충돌 검사를 사용할 수 없음 — git 2.38+ 필요';
  @override
  String get conflictCheckUnavailable => '충돌 검사를 사용할 수 없음';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '충돌 예상 · 파일 ${n}개',
      );
  @override
  String plusMore({required Object n}) => '+${n}개 더';
  @override
  String get rebase => '리베이스';
  @override
  String get squash => '스쿼시';
  @override
  String get mergeCommit => '머지 커밋';
  @override
  String noDeskForBranch({required Object branch}) =>
      '브랜치 ${branch}에 대한 Desk를 찾을 수 없습니다';
  @override
  String get mergeAnyway => '그래도 머지';
  @override
  String get readingIssues => '이슈 읽는 중…';
  @override
  String get openUpstreamOrLocal => '업스트림에서 하나 열거나, 로컬에서 여십시오.';
  @override
  String get noIssuesMatchFilters => '이 필터에 맞는 이슈가 없습니다';
  @override
  String couldntCreateIssue({required Object error}) =>
      '이슈를 생성할 수 없음: ${error}';
  @override
  String get promoteToRemote => '원격으로 승격';
  @override
  String get pushToRemote => '원격에 푸시';
  @override
  String get pullFromRemote => '원격에서 풀';
  @override
  String get import => '가져오기';
  @override
  String get linkToPr => 'PR에 연결…';
  @override
  String get abandon => '포기';
  @override
  String get issuePromotedToRemote => '이슈가 원격으로 승격됐습니다.';
  @override
  String get issuePushedToRemote => '원격에 푸시했습니다.';
  @override
  String get issuePulledFromRemote => '원격에서 풀했습니다.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} 로컬로 가져옴.';
  @override
  String get abandonIssueTitle => '이슈 포기';
  @override
  String abandonIssueMessage({required Object id}) =>
      '로컬 이슈 #${id}을(를) 영구 제거하시겠습니까? ref가 삭제되며 되돌릴 수 없습니다.';
  @override
  String couldntAbandon({required Object error}) => '포기할 수 없음: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      '댓글을 게시할 수 없음: ${error}';
  @override
  String couldntCloseIssue({required Object error}) => '이슈를 닫을 수 없음: ${error}';
  @override
  String couldntAddLabel({required Object error}) => '레이블을 추가할 수 없음: ${error}';
  @override
  String get lensBranches => '브랜치';
  @override
  String get lensPrs => 'PR';
  @override
  String get patchUp => '↑ 패치';
  @override
  String get syncRibbon => '⇅ 동기화';
  @override
  String get kbHeading => '키보드';
  @override
  String get kbNavigateRows => '행 이동';
  @override
  String get kbExpandCollapse => '포커스된 행 펼치기 / 접기';
  @override
  String get kbCheckoutPr => '포커스된 PR 로컬 체크아웃';
  @override
  String get kbApproveReview => '승인 · 리뷰';
  @override
  String get kbRequestChanges => '변경 요청';
  @override
  String get kbFocusSearch => '검색 포커스';
  @override
  String get kbSwitchLens => '렌즈 전환 (브랜치 · PR)';
  @override
  String get kbToggleOverlay => '이 오버레이 토글';
  @override
  String get kbPressToDismiss => '아무 곳이나 눌러 닫기';
  @override
  String get overrideScarTooltip =>
      '실패한 검사와 함께 또는 승인 리뷰 없이 머지됨 — 급할 때 먼저 조사하십시오';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개가 커밋되지 않은 작업과 겹칩니다',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '#${pr}  (파일 ${n}개)',
      );
  @override
  String get prStateDraft => '초안';
  @override
  String get localBadge => '로컬';
  @override
  String get myReviewPending => '내 리뷰 대기 중';
  @override
  String get myReviewApproved => '나 ✓';
  @override
  String get myReviewChangesRequested => '나 ✗ 변경 요청함';
  @override
  String get myReviewCommented => '내가 댓글 달음';
  @override
  String get myReviewDefault => '나';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '댓글 ${count}개 · 마지막 작성자 표시';
  @override
  String get tailLastComment => '마지막 댓글';
  @override
  String tailLastReviewState({required Object state}) => '마지막 리뷰 · ${state}';
  @override
  String get tailLastReview => '마지막 리뷰';
  @override
  String tailLastCheckState({required Object state}) => '마지막 검사 · ${state}';
  @override
  String get tailLastCommit => '마지막 커밋';
  @override
  String get tailLastActivity => '마지막 활동';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '이슈 ${n}개 닫음 — 클릭하여 이동',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: 'PR ${n}개가 처리 — 클릭하여 이동',
      );
  @override
  String get checksLabel => '검사';
  @override
  String get reviewersLabel => '리뷰어';
  @override
  String get conflictsLabel => '충돌';
  @override
  String exportFailed({required Object error}) => '내보내기 실패: ${error}';
  @override
  String get readingFiles => '파일 읽는 중…';
  @override
  String get noDetailAvailable => '세부 정보 없음';
  @override
  String get noFilesReported => '보고된 파일 없음';
  @override
  String get readingGitHistory => 'git 히스토리 읽는 중…';
  @override
  String get knowsThisCode => '이 코드를 잘 앎';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '지난 1년간 이 파일들에 커밋 ${n}개',
      );
  @override
  String get willFight => '충돌 예상';
  @override
  String orbitalPartnerCos({required Object cos}) => '궤도 파트너 — cos ${cos}';
  @override
  String get orbitLabel => '궤도';
  @override
  String get touchesYourLocalWork => '로컬 작업을 건드림';
  @override
  String get mergingWillConflict => '머지 시 커밋되지 않은 변경과 충돌할 가능성이 높습니다';
  @override
  String get closesHeading => '닫음';
  @override
  String get filesHeading => '파일';
  @override
  String get orientAligned => '정렬됨';
  @override
  String get orientAdjacent => '인접';
  @override
  String get orientOrthogonal => '직교';
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
  String resonanceReadout({required Object v}) => '공명 ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      '보통 이 PR의 파일들과 함께 움직임\n(${path})';
  @override
  String get prStateDraftLower => '초안';
  @override
  String get keystoneTooltip => '키스톤 — 저장소 전역 브리지 파일';
  @override
  String get reviewNoteHint => '메모 남기기 (선택)…';
  @override
  String get reviewComment => '댓글';
  @override
  String get reviewRequestChanges => '변경 요청';
  @override
  String get reviewApprove => '✓ 승인';
  @override
  String get actionPatchDown => '↓ 패치';
  @override
  String get actionPrReview => '✦ PR 리뷰';
  @override
  String get actionOpenAsDesk => '⊞ Desk로 열기';
  @override
  String get actionCheckout => '[c] 체크아웃';
  @override
  String get actionMerge => '[m] 머지 ▾';
  @override
  String get mergeMenuMergeCommit => '머지 커밋';
  @override
  String get mergeMenuSquash => '스쿼시 & 머지';
  @override
  String get mergeMenuRebase => '리베이스 & 머지';
  @override
  String get deleteBranchAfter => '이후 브랜치 삭제';
  @override
  String checkDurationSec({required Object n}) => '${n}초';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}분 ${s}초';
  @override
  String assignedTo({required Object names}) => '담당: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '대화 ${n}개 · ${time}';
  @override
  String get readingThread => '스레드 읽는 중…';
  @override
  String get addressedByHeading => '처리 주체';
  @override
  String get descriptionHeading => '설명';
  @override
  String get threadHeading => '스레드';
  @override
  String get replyHint => '답글…';
  @override
  String get assignMe => '나에게 할당';
  @override
  String get closeLower => '닫기';
  @override
  String get postReply => '↩ 게시';
  @override
  String get remoteProviderUnavailable => '원격 제공자를 사용할 수 없음';
  @override
  String get noRecognisedRemoteHost => '이 저장소에 인식된 원격 호스트가 없습니다.';
  @override
  String get corpseGone => '사라짐';
  @override
  String get corpseAbsorbed => '흡수됨';
  @override
  String get corpseSquashed => '스쿼시됨';
  @override
  String absorbedDeliveredIn({required Object hash}) => '${hash}에서 전달됨';
  @override
  String get absorbedNoChanges => '머지해도 변경이 추가되지 않음';
  @override
  String get corpseTagUpstreamGone => '업스트림 사라짐';
  @override
  String corpseTagAbsorbed({required Object receipt}) => '흡수됨, ${receipt}';
  @override
  String get corpseTagSquashed => '스쿼시 후 머지됨';
  @override
  String semanticsCurrentBranch({required Object name}) => '${name}, 현재 브랜치';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, ${upstream} 추적 중';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) => '${label}, 작업 트리 열림';
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
  String get crossLinkPrDraft => 'PR · 초안';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '이슈 ${n}개',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ 추적: ${upstream}';
  @override
  String get checkoutButton => '체크아웃';
  @override
  String get createBranch => '브랜치 생성';
  @override
  String get newBranchName => '새 브랜치 이름';
  @override
  String newBranchNameError({required Object error}) => '새 브랜치 이름 — ${error}';
  @override
  String get forceDelete => '강제?';
  @override
  String get annotated => '주석 태그';
  @override
  String get applyCheckFailed => 'apply --check 실패';
  @override
  String get openPatchFrom => '패치 열기 원본';
  @override
  String get patchFromFile => '파일에서…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => '클립보드에서';
  @override
  String get patchFromClipboardHint => '텍스트 붙여넣기';
  @override
  String get patchPreviewHeading => '패치 미리보기';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => '스테이징됨.';
  @override
  String get appliedDone => '적용됨.';
  @override
  String get opening => '여는 중…';
  @override
  String get mergeEditor => '⇋ 머지 편집기';
  @override
  String get staging => '스테이징 중…';
  @override
  String get applying => '적용 중…';
  @override
  String get stage => '스테이징';
  @override
  String get apply => '적용';
  @override
  String get refineHint => '다듬기… (예: "로거 변경도 제외해줘")';
  @override
  String get reverseArmedTooltip => '장전됨 — 다음 적용은 패치를 되돌립니다 (-R)';
  @override
  String get reverseDisarmedTooltip => '역방향 장전 (-R) — 적용 대신 되돌리기';
  @override
  String get reverseArmedLabel => '⟲ 역방향 ✓';
  @override
  String get reverseLabel => '⟲ 역방향';
  @override
  String get untouchedHeading => '⚠ 손대지 않음';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${n}개 중 ${count}개 파일이 패치에 없음',
      );
  @override
  String get staysConflicted => '이 파일들은 충돌 상태로 남습니다 — 적용해도 스테이징되지 않습니다';
  @override
  String get orWith => '또는';
  @override
  String get noAiModelConfigured => '구성된 AI 모델 없음';
  @override
  String applyWithPatchFrom({required Object label}) => '${label}의 패치로 적용';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => '${label}의 패치로 적용  ·  ${model}';
  @override
  String get patching => '패치 중…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  ${label}의 패치로 적용';
  @override
  String get orWithAnotherModel => '또는 다른 모델로';
  @override
  String get applyCheckPassed => 'git apply --check 통과 — 패치가 깔끔하게 적용됩니다';
  @override
  String get gitApplyCheckFailed => 'git apply --check 실패';
  @override
  String get appliesClean => '깔끔하게 적용됨';
  @override
  String get willNotApply => '적용되지 않음';
  @override
  String get newLocalIssue => '새 로컬 이슈';
  @override
  String get filterHint => '필터…';
  @override
  String get nothingToLink => '아직 연결할 것이 없습니다.';
  @override
  String get nothingMatchesDot => '일치하는 항목이 없습니다.';
  @override
  String get relevantHeading => '관련';
  @override
  String get allHeading => '전체';
  @override
  String get doneLower => '완료';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => '새 로컬 이슈';
  @override
  String get titleHint => '제목';
  @override
  String get bodyHint => '본문 (마크다운)';
  @override
  String get cancelLower => '취소';
  @override
  String get createLower => '생성';
  @override
  String get deleteFailed => '삭제 실패';
  @override
  String reviewFailed({required Object error}) => '리뷰 실패: ${error}';
  @override
  String get resolutionFailed => '해결 실패';
  @override
  String get patchBlocksNoCover => '모델이 실패한 파일을 다루지 않는 패치 블록을 반환했습니다';
  @override
  String get applyFailed => '적용 실패';
  @override
  String get emptyOrUnparseablePatch => '모델이 비어 있거나 파싱할 수 없는 패치를 반환했습니다';
  @override
  String noModelConfiguredFor({required Object label}) =>
      '"${label}"에 구성된 모델 없음';
  @override
  String get checksHeading => '검사';
  @override
  String get peopleHeading => '사람';
  @override
  String get conversationHeading => '대화';
}

// Path: changes
class _Translations$changes$ko extends Translations$changes$en {
  _Translations$changes$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$ko usage =
      _Translations$changes$usage$ko._(_root);
  @override
  late final _Translations$changes$tabs$ko tabs =
      _Translations$changes$tabs$ko._(_root);
  @override
  late final _Translations$changes$tabStrip$ko tabStrip =
      _Translations$changes$tabStrip$ko._(_root);
  @override
  late final _Translations$changes$select$ko select =
      _Translations$changes$select$ko._(_root);
  @override
  late final _Translations$changes$constellationToggle$ko constellationToggle =
      _Translations$changes$constellationToggle$ko._(_root);
  @override
  late final _Translations$changes$nudgeChip$ko nudgeChip =
      _Translations$changes$nudgeChip$ko._(_root);
  @override
  late final _Translations$changes$minimap$ko minimap =
      _Translations$changes$minimap$ko._(_root);
  @override
  late final _Translations$changes$tagInput$ko tagInput =
      _Translations$changes$tagInput$ko._(_root);
  @override
  late final _Translations$changes$composer$ko composer =
      _Translations$changes$composer$ko._(_root);
  @override
  late final _Translations$changes$commit$ko commit =
      _Translations$changes$commit$ko._(_root);
  @override
  late final _Translations$changes$rebase$ko rebase =
      _Translations$changes$rebase$ko._(_root);
  @override
  late final _Translations$changes$editor$ko editor =
      _Translations$changes$editor$ko._(_root);
  @override
  late final _Translations$changes$editorTitles$ko editorTitles =
      _Translations$changes$editorTitles$ko._(_root);
  @override
  late final _Translations$changes$askHint$ko askHint =
      _Translations$changes$askHint$ko._(_root);
  @override
  late final _Translations$changes$fileMenu$ko fileMenu =
      _Translations$changes$fileMenu$ko._(_root);
  @override
  late final _Translations$changes$multiFileMenu$ko multiFileMenu =
      _Translations$changes$multiFileMenu$ko._(_root);
  @override
  late final _Translations$changes$ignoreMenu$ko ignoreMenu =
      _Translations$changes$ignoreMenu$ko._(_root);
  @override
  late final _Translations$changes$discard$ko discard =
      _Translations$changes$discard$ko._(_root);
  @override
  late final _Translations$changes$snack$ko snack =
      _Translations$changes$snack$ko._(_root);
  @override
  late final _Translations$changes$trace$ko trace =
      _Translations$changes$trace$ko._(_root);
  @override
  late final _Translations$changes$cleanTree$ko cleanTree =
      _Translations$changes$cleanTree$ko._(_root);
  @override
  late final _Translations$changes$guardrail$ko guardrail =
      _Translations$changes$guardrail$ko._(_root);
  @override
  late final _Translations$changes$dropHint$ko dropHint =
      _Translations$changes$dropHint$ko._(_root);
  @override
  late final _Translations$changes$diffEmpty$ko diffEmpty =
      _Translations$changes$diffEmpty$ko._(_root);
  @override
  late final _Translations$changes$shelvePill$ko shelvePill =
      _Translations$changes$shelvePill$ko._(_root);
  @override
  late final _Translations$changes$stashAction$ko stashAction =
      _Translations$changes$stashAction$ko._(_root);
  @override
  late final _Translations$changes$stashContents$ko stashContents =
      _Translations$changes$stashContents$ko._(_root);
  @override
  late final _Translations$changes$stashFile$ko stashFile =
      _Translations$changes$stashFile$ko._(_root);
  @override
  late final _Translations$changes$fileRow$ko fileRow =
      _Translations$changes$fileRow$ko._(_root);
  @override
  late final _Translations$changes$resolveStrip$ko resolveStrip =
      _Translations$changes$resolveStrip$ko._(_root);
  @override
  late final _Translations$changes$badge$ko badge =
      _Translations$changes$badge$ko._(_root);
  @override
  late final _Translations$changes$review$ko review =
      _Translations$changes$review$ko._(_root);
  @override
  late final _Translations$changes$commitBtn$ko commitBtn =
      _Translations$changes$commitBtn$ko._(_root);
  @override
  late final _Translations$changes$shapeBtn$ko shapeBtn =
      _Translations$changes$shapeBtn$ko._(_root);
  @override
  late final _Translations$changes$dejaVu$ko dejaVu =
      _Translations$changes$dejaVu$ko._(_root);
  @override
  late final _Translations$changes$identity$ko identity =
      _Translations$changes$identity$ko._(_root);
  @override
  late final _Translations$changes$staleScope$ko staleScope =
      _Translations$changes$staleScope$ko._(_root);
  @override
  late final _Translations$changes$finding$ko finding =
      _Translations$changes$finding$ko._(_root);
  @override
  late final _Translations$changes$muse$ko muse =
      _Translations$changes$muse$ko._(_root);
  @override
  late final _Translations$changes$debug$ko debug =
      _Translations$changes$debug$ko._(_root);
  @override
  late final _Translations$changes$includeSummary$ko includeSummary =
      _Translations$changes$includeSummary$ko._(_root);
  @override
  late final _Translations$changes$status$ko status =
      _Translations$changes$status$ko._(_root);
  @override
  late final _Translations$changes$stash$ko stash =
      _Translations$changes$stash$ko._(_root);
  @override
  late final _Translations$changes$tooltips$ko tooltips =
      _Translations$changes$tooltips$ko._(_root);
  @override
  late final _Translations$changes$mergeEditor$ko mergeEditor =
      _Translations$changes$mergeEditor$ko._(_root);
  @override
  late final _Translations$changes$conflictResolution$ko conflictResolution =
      _Translations$changes$conflictResolution$ko._(_root);
  @override
  late final _Translations$changes$mergeFlow$ko mergeFlow =
      _Translations$changes$mergeFlow$ko._(_root);
  @override
  late final _Translations$changes$constellation$ko constellation =
      _Translations$changes$constellation$ko._(_root);
}

// Path: common
class _Translations$common$ko extends Translations$common$en {
  _Translations$common$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => '취소';
  @override
  String get close => '닫기';
  @override
  String get save => '저장';
  @override
  String get delete => '삭제';
  @override
  String get retry => '다시 시도';
  @override
  String get copy => '복사';
  @override
  String get copied => '복사됨';
  @override
  String get done => '완료';
  @override
  String get loading => '불러오는 중…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '커밋 ${n}개',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '브랜치 ${n}개',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '로컬 커밋 ${n}개',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '원격 커밋 ${n}개',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '충돌 파일 ${n}개',
      );
  @override
  late final _Translations$common$time$ko time = _Translations$common$time$ko._(
    _root,
  );
  @override
  late final _Translations$common$size$ko size = _Translations$common$size$ko._(
    _root,
  );
}

// Path: diff
class _Translations$diff$ko extends Translations$diff$en {
  _Translations$diff$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$ko status =
      _Translations$diff$status$ko._(_root);
  @override
  late final _Translations$diff$toolbar$ko toolbar =
      _Translations$diff$toolbar$ko._(_root);
  @override
  late final _Translations$diff$hunkDropdown$ko hunkDropdown =
      _Translations$diff$hunkDropdown$ko._(_root);
  @override
  String stagingFailed({required Object error}) => '부분 스테이징 실패: ${error}';
  @override
  late final _Translations$diff$trail$ko trail = _Translations$diff$trail$ko._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$ko pinned =
      _Translations$diff$pinned$ko._(_root);
  @override
  late final _Translations$diff$hunkHint$ko hunkHint =
      _Translations$diff$hunkHint$ko._(_root);
  @override
  late final _Translations$diff$binary$ko binary =
      _Translations$diff$binary$ko._(_root);
  @override
  late final _Translations$diff$media$ko media = _Translations$diff$media$ko._(
    _root,
  );
}

// Path: filament
class _Translations$filament$ko extends Translations$filament$en {
  _Translations$filament$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => '열린 저장소가 없습니다.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      '파일 스캔 중 ${scanned} / ${total}…';
  @override
  String findingsAcrossFiles({required Object files, required Object count}) =>
      '파일 ${files}개에서 발견 ${count}건';
  @override
  String copiedFindings({required Object count}) => '발견 ${count}건 복사됨';
  @override
  String get copy => '복사';
  @override
  String get noFindings => '실행 흐름 관련 발견 없음.';
  @override
  late final _Translations$filament$severity$ko severity =
      _Translations$filament$severity$ko._(_root);
  @override
  late final _Translations$filament$kind$ko kind =
      _Translations$filament$kind$ko._(_root);
  @override
  String lineLabel({required Object line}) => 'L${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$ko extends Translations$history$en {
  _Translations$history$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$ko commitLede =
      _Translations$history$commitLede$ko._(_root);
  @override
  late final _Translations$history$seismograph$ko seismograph =
      _Translations$history$seismograph$ko._(_root);
  @override
  late final _Translations$history$worldline$ko worldline =
      _Translations$history$worldline$ko._(_root);
  @override
  late final _Translations$history$contextMenu$ko contextMenu =
      _Translations$history$contextMenu$ko._(_root);
  @override
  late final _Translations$history$cherryPick$ko cherryPick =
      _Translations$history$cherryPick$ko._(_root);
  @override
  late final _Translations$history$revert$ko revert =
      _Translations$history$revert$ko._(_root);
  @override
  late final _Translations$history$reflog$ko reflog =
      _Translations$history$reflog$ko._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '그 커밋은 불러온 커밋 ${n}개보다 더 깊습니다.',
      );
  @override
  String deleteTagFailed({required Object error}) => '태그 삭제 실패: ${error}';
  @override
  String get loadingTitle => '히스토리 불러오는 중';
  @override
  String get loadingMessage => '최근 커밋을 읽는 중.';
  @override
  String get unavailableTitle => '히스토리를 사용할 수 없음';
  @override
  String get toggleWorldline => '월드라인 토글';
  @override
  String get pageTitle => '히스토리';
  @override
  String get viewingLast => '최근 보기';
  @override
  String get commitsUnit => '커밋';
  @override
  String get noCommitSelectedTitle => '선택된 커밋 없음';
  @override
  String get noCommitSelectedMessage => '변경 내용을 살펴보려면 커밋을 선택하십시오.';
  @override
  String get loadingCommitTitle => '커밋 불러오는 중';
  @override
  String get loadingCommitMessage => '커밋 세부 정보를 읽는 중.';
  @override
  String get commitUnavailableTitle => '커밋을 사용할 수 없음';
  @override
  String get couldNotLoadCommit => '커밋을 불러올 수 없습니다.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'reflog 불러오기';
  @override
  String get createTag => '태그 생성';
  @override
  String get newTagName => '새 태그 이름';
  @override
  String newTagNameError({required Object error}) => '새 태그 이름 — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개 · 모든 변경',
      );
  @override
  String get allChangesLabel => '모든 변경';
  @override
  late final _Translations$history$rebase$ko rebase =
      _Translations$history$rebase$ko._(_root);
  @override
  late final _Translations$history$inFlight$ko inFlight =
      _Translations$history$inFlight$ko._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$ko extends Translations$historySurgery$en {
  _Translations$historySurgery$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$ko chrome =
      _Translations$historySurgery$chrome$ko._(_root);
  @override
  late final _Translations$historySurgery$select$ko select =
      _Translations$historySurgery$select$ko._(_root);
  @override
  late final _Translations$historySurgery$understand$ko understand =
      _Translations$historySurgery$understand$ko._(_root);
  @override
  late final _Translations$historySurgery$confirm$ko confirm =
      _Translations$historySurgery$confirm$ko._(_root);
  @override
  late final _Translations$historySurgery$execute$ko execute =
      _Translations$historySurgery$execute$ko._(_root);
  @override
  late final _Translations$historySurgery$verify$ko verify =
      _Translations$historySurgery$verify$ko._(_root);
  @override
  late final _Translations$historySurgery$forcePush$ko forcePush =
      _Translations$historySurgery$forcePush$ko._(_root);
}

// Path: onboarding
class _Translations$onboarding$ko extends Translations$onboarding$en {
  _Translations$onboarding$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$ko nav =
      _Translations$onboarding$nav$ko._(_root);
  @override
  late final _Translations$onboarding$naming$ko naming =
      _Translations$onboarding$naming$ko._(_root);
  @override
  late final _Translations$onboarding$theme$ko theme =
      _Translations$onboarding$theme$ko._(_root);
  @override
  late final _Translations$onboarding$repo$ko repo =
      _Translations$onboarding$repo$ko._(_root);
  @override
  late final _Translations$onboarding$preview$ko preview =
      _Translations$onboarding$preview$ko._(_root);
}

// Path: orrery
class _Translations$orrery$ko extends Translations$orrery$en {
  _Translations$orrery$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$ko header =
      _Translations$orrery$header$ko._(_root);
  @override
  late final _Translations$orrery$status$ko status =
      _Translations$orrery$status$ko._(_root);
  @override
  late final _Translations$orrery$legend$ko legend =
      _Translations$orrery$legend$ko._(_root);
  @override
  late final _Translations$orrery$node$ko node = _Translations$orrery$node$ko._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$ko milestone =
      _Translations$orrery$milestone$ko._(_root);
  @override
  late final _Translations$orrery$structure$ko structure =
      _Translations$orrery$structure$ko._(_root);
  @override
  late final _Translations$orrery$rail$ko rail = _Translations$orrery$rail$ko._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$ko selection =
      _Translations$orrery$selection$ko._(_root);
  @override
  late final _Translations$orrery$findingKind$ko findingKind =
      _Translations$orrery$findingKind$ko._(_root);
  @override
  late final _Translations$orrery$findings$ko findings =
      _Translations$orrery$findings$ko._(_root);
  @override
  late final _Translations$orrery$anchor$ko anchor =
      _Translations$orrery$anchor$ko._(_root);
  @override
  late final _Translations$orrery$compare$ko compare =
      _Translations$orrery$compare$ko._(_root);
}

// Path: palette
class _Translations$palette$ko extends Translations$palette$en {
  _Translations$palette$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get active => '활성';
  @override
  late final _Translations$palette$prefixes$ko prefixes =
      _Translations$palette$prefixes$ko._(_root);
  @override
  late final _Translations$palette$chips$ko chips =
      _Translations$palette$chips$ko._(_root);
  @override
  late final _Translations$palette$predictive$ko predictive =
      _Translations$palette$predictive$ko._(_root);
  @override
  late final _Translations$palette$topTouched$ko topTouched =
      _Translations$palette$topTouched$ko._(_root);
  @override
  late final _Translations$palette$coherence$ko coherence =
      _Translations$palette$coherence$ko._(_root);
  @override
  late final _Translations$palette$keystone$ko keystone =
      _Translations$palette$keystone$ko._(_root);
  @override
  late final _Translations$palette$repoSub$ko repoSub =
      _Translations$palette$repoSub$ko._(_root);
  @override
  late final _Translations$palette$desks$ko desks =
      _Translations$palette$desks$ko._(_root);
  @override
  late final _Translations$palette$actions$ko actions =
      _Translations$palette$actions$ko._(_root);
  @override
  late final _Translations$palette$tools$ko tools =
      _Translations$palette$tools$ko._(_root);
  @override
  late final _Translations$palette$gitCommands$ko gitCommands =
      _Translations$palette$gitCommands$ko._(_root);
  @override
  late final _Translations$palette$pr$ko pr = _Translations$palette$pr$ko._(
    _root,
  );
  @override
  late final _Translations$palette$ai$ko ai = _Translations$palette$ai$ko._(
    _root,
  );
  @override
  late final _Translations$palette$undo$ko undo =
      _Translations$palette$undo$ko._(_root);
  @override
  late final _Translations$palette$navigation$ko navigation =
      _Translations$palette$navigation$ko._(_root);
  @override
  late final _Translations$palette$settings$ko settings =
      _Translations$palette$settings$ko._(_root);
  @override
  late final _Translations$palette$info$ko info =
      _Translations$palette$info$ko._(_root);
  @override
  late final _Translations$palette$debug$ko debug =
      _Translations$palette$debug$ko._(_root);
  @override
  late final _Translations$palette$dev$ko dev = _Translations$palette$dev$ko._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$ko historySurgery =
      _Translations$palette$historySurgery$ko._(_root);
  @override
  late final _Translations$palette$orrery$ko orrery =
      _Translations$palette$orrery$ko._(_root);
  @override
  late final _Translations$palette$command$ko command =
      _Translations$palette$command$ko._(_root);
  @override
  late final _Translations$palette$search$ko search =
      _Translations$palette$search$ko._(_root);
  @override
  late final _Translations$palette$wick$ko wick =
      _Translations$palette$wick$ko._(_root);
  @override
  late final _Translations$palette$gitCache$ko gitCache =
      _Translations$palette$gitCache$ko._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$ko extends Translations$releaseNotes$en {
  _Translations$releaseNotes$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$ko about =
      _Translations$releaseNotes$about$ko._(_root);
  @override
  late final _Translations$releaseNotes$legal$ko legal =
      _Translations$releaseNotes$legal$ko._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$ko extends Translations$repoSummary$en {
  _Translations$repoSummary$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$ko backbone =
      _Translations$repoSummary$backbone$ko._(_root);
  @override
  late final _Translations$repoSummary$glance$ko glance =
      _Translations$repoSummary$glance$ko._(_root);
  @override
  late final _Translations$repoSummary$heading$ko heading =
      _Translations$repoSummary$heading$ko._(_root);
  @override
  String get historyStarvedCaveat =>
      '순위가 제한적입니다: 결합 그래프에 간선이 없습니다(갓 클론했거나 커밋이 너무 적음). 파일 순서는 구조적 중심성이 아니라 크기를 반영합니다.';
  @override
  late final _Translations$repoSummary$pitch$ko pitch =
      _Translations$repoSummary$pitch$ko._(_root);
  @override
  late final _Translations$repoSummary$region$ko region =
      _Translations$repoSummary$region$ko._(_root);
  @override
  late final _Translations$repoSummary$shape$ko shape =
      _Translations$repoSummary$shape$ko._(_root);
}

// Path: review
class _Translations$review$ko extends Translations$review$en {
  _Translations$review$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => '미해결';
  @override
  String get done => '완료';
  @override
  String get ack => '확인';
  @override
  String get reply => '답글';
  @override
  String get pleaseFix => '수정 필요';
  @override
  String get draft => '초안';
  @override
  String get engine => '엔진';
  @override
  String get moved => '이동됨';
  @override
  String get yourTurn => '당신 차례';
  @override
  String get drafts => '초안';
  @override
  String get publish => '게시';
  @override
  String get discard => '버리기';
  @override
  String get saveDraft => '초안 저장';
  @override
  String get cancel => '취소';
  @override
  String get verdictApprove => '승인';
  @override
  String get verdictRequestChanges => '변경 요청';
  @override
  String get verdictComment => '댓글';
  @override
  String get caughtUp => '최신';
  @override
  String get sinceLastLook => '마지막으로 본 이후';
  @override
  String get fullDiff => '전체 diff';
  @override
  String get commentHint => '댓글 작성';
  @override
  String outdatedLastSeen({required Object round}) => '오래됨 · 마지막 확인 R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => '${who} 대기 중';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        one: '마지막으로 본 이후 파일 ${n}개',
        other: '마지막으로 본 이후 파일 ${n}개',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '미해결 ${n}개';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        one: '초안 ${n}개',
        other: '초안 ${n}개',
      );
  @override
  String startReviewFailed({required Object error}) =>
      '리뷰를 시작할 수 없습니다: ${error}';
  @override
  String get anchorUnavailable => '해당 줄을 고정할 수 없습니다 — 파일이 너무 크거나 사용할 수 없습니다.';
  @override
  String reviewActionFailed({required Object error}) =>
      '리뷰 작업에 실패했습니다: ${error}';
  @override
  String get lensTooLarge => '이 비교는 너무 커서 여기에 표시할 수 없습니다 — 전체 diff를 유지합니다.';
  @override
  String get lensEmpty => '이 스냅샷들 사이에 바뀐 것이 없습니다.';
  @override
  String get reopen => '다시 열기';
  @override
  String get notBlocking => '내 대기 해제';
  @override
  String get markReviewed => '읽음';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        one: '새 댓글 ${n}개',
        other: '새 댓글 ${n}개',
      );
  @override
  String get handTo => '넘기기';
  @override
  String get heading => '리뷰';
  @override
  String get identityNeeded => '리뷰하려면 git 신원을 설정하세요';
  @override
  String get fileUnreadable => '이 파일은 여기서 읽을 수 없습니다. 너무 크거나 이번 라운드에 없습니다.';
  @override
  String get timeNow => '방금';
  @override
  String timeMinutesFmt({required Object n}) => '${n}분 전';
  @override
  String timeHoursFmt({required Object n}) => '${n}시간 전';
  @override
  String timeDaysFmt({required Object n}) => '${n}일 전';
  @override
  String get standingApproved => '승인됨';
  @override
  String get standingChangesRequested => '변경 요청됨';
  @override
  String get commentOnChange => '이 변경에 댓글';
  @override
  String get commentOnFile => '이 파일에 댓글';
  @override
  String get imageNotLoaded => '이미지를 불러오지 않음';
  @override
  String get nothingBlocking => '대기 중인 항목 없음';
}

// Path: settings
class _Translations$settings$ko extends Translations$settings$en {
  _Translations$settings$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$ko language =
      _Translations$settings$language$ko._(_root);
  @override
  late final _Translations$settings$sectionLabels$ko sectionLabels =
      _Translations$settings$sectionLabels$ko._(_root);
  @override
  late final _Translations$settings$errors$ko errors =
      _Translations$settings$errors$ko._(_root);
  @override
  late final _Translations$settings$promptStatus$ko promptStatus =
      _Translations$settings$promptStatus$ko._(_root);
  @override
  late final _Translations$settings$clearData$ko clearData =
      _Translations$settings$clearData$ko._(_root);
  @override
  List<String> get guardrailStageLabels => ['느슨', '균형', '엄격', '편집증'];
  @override
  late final _Translations$settings$guardrailMacro$ko guardrailMacro =
      _Translations$settings$guardrailMacro$ko._(_root);
  @override
  late final _Translations$settings$guardrails$ko guardrails =
      _Translations$settings$guardrails$ko._(_root);
  @override
  late final _Translations$settings$appearance$ko appearance =
      _Translations$settings$appearance$ko._(_root);
  @override
  late final _Translations$settings$retention$ko retention =
      _Translations$settings$retention$ko._(_root);
  @override
  late final _Translations$settings$navigation$ko navigation =
      _Translations$settings$navigation$ko._(_root);
  @override
  late final _Translations$settings$behaviour$ko behaviour =
      _Translations$settings$behaviour$ko._(_root);
  @override
  late final _Translations$settings$retentionClear$ko retentionClear =
      _Translations$settings$retentionClear$ko._(_root);
  @override
  late final _Translations$settings$channels$ko channels =
      _Translations$settings$channels$ko._(_root);
  @override
  late final _Translations$settings$pollResult$ko pollResult =
      _Translations$settings$pollResult$ko._(_root);
  @override
  late final _Translations$settings$keybindingProfile$ko keybindingProfile =
      _Translations$settings$keybindingProfile$ko._(_root);
  @override
  late final _Translations$settings$apiKeys$ko apiKeys =
      _Translations$settings$apiKeys$ko._(_root);
  @override
  late final _Translations$settings$shortcuts$ko shortcuts =
      _Translations$settings$shortcuts$ko._(_root);
  @override
  late final _Translations$settings$toggles$ko toggles =
      _Translations$settings$toggles$ko._(_root);
  @override
  late final _Translations$settings$diffDiffability$ko diffDiffability =
      _Translations$settings$diffDiffability$ko._(_root);
  @override
  late final _Translations$settings$modelSlots$ko modelSlots =
      _Translations$settings$modelSlots$ko._(_root);
  @override
  late final _Translations$settings$modelPicker$ko modelPicker =
      _Translations$settings$modelPicker$ko._(_root);
  @override
  late final _Translations$settings$aiFeatures$ko aiFeatures =
      _Translations$settings$aiFeatures$ko._(_root);
  @override
  late final _Translations$settings$commitEditor$ko commitEditor =
      _Translations$settings$commitEditor$ko._(_root);
  @override
  late final _Translations$settings$review$ko review =
      _Translations$settings$review$ko._(_root);
  @override
  late final _Translations$settings$museHint$ko museHint =
      _Translations$settings$museHint$ko._(_root);
  @override
  late final _Translations$settings$museEditor$ko museEditor =
      _Translations$settings$museEditor$ko._(_root);
  @override
  late final _Translations$settings$museStage$ko museStage =
      _Translations$settings$museStage$ko._(_root);
  @override
  late final _Translations$settings$lensAxis$ko lensAxis =
      _Translations$settings$lensAxis$ko._(_root);
  @override
  late final _Translations$settings$logosLens$ko logosLens =
      _Translations$settings$logosLens$ko._(_root);
  @override
  late final _Translations$settings$sortGuide$ko sortGuide =
      _Translations$settings$sortGuide$ko._(_root);
  @override
  late final _Translations$settings$piggyback$ko piggyback =
      _Translations$settings$piggyback$ko._(_root);
  @override
  late final _Translations$settings$diffStage$ko diffStage =
      _Translations$settings$diffStage$ko._(_root);
  @override
  late final _Translations$settings$undoScope$ko undoScope =
      _Translations$settings$undoScope$ko._(_root);
  @override
  late final _Translations$settings$undoWindow$ko undoWindow =
      _Translations$settings$undoWindow$ko._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$ko guardrailPhrase =
      _Translations$settings$guardrailPhrase$ko._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$ko reviewGuideHint =
      _Translations$settings$reviewGuideHint$ko._(_root);
  @override
  late final _Translations$settings$commitFormat$ko commitFormat =
      _Translations$settings$commitFormat$ko._(_root);
  @override
  late final _Translations$settings$commitPreview$ko commitPreview =
      _Translations$settings$commitPreview$ko._(_root);
  @override
  late final _Translations$settings$externalTools$ko externalTools =
      _Translations$settings$externalTools$ko._(_root);
  @override
  late final _Translations$settings$apiUsage$ko apiUsage =
      _Translations$settings$apiUsage$ko._(_root);
  @override
  late final _Translations$settings$gitea$ko gitea =
      _Translations$settings$gitea$ko._(_root);
  @override
  late final _Translations$settings$wick$ko wick =
      _Translations$settings$wick$ko._(_root);
  @override
  late final _Translations$settings$integrations$ko integrations =
      _Translations$settings$integrations$ko._(_root);
  @override
  late final _Translations$settings$reduceMotion$ko reduceMotion =
      _Translations$settings$reduceMotion$ko._(_root);
  @override
  late final _Translations$settings$resetQuit$ko resetQuit =
      _Translations$settings$resetQuit$ko._(_root);
  @override
  late final _Translations$settings$diagnostics$ko diagnostics =
      _Translations$settings$diagnostics$ko._(_root);
  @override
  late final _Translations$settings$telemetry$ko telemetry =
      _Translations$settings$telemetry$ko._(_root);
  @override
  late final _Translations$settings$flowEngine$ko flowEngine =
      _Translations$settings$flowEngine$ko._(_root);
  @override
  late final _Translations$settings$museStrands$ko museStrands =
      _Translations$settings$museStrands$ko._(_root);
  @override
  late final _Translations$settings$cliPiggyback$ko cliPiggyback =
      _Translations$settings$cliPiggyback$ko._(_root);
  @override
  late final _Translations$settings$header$ko header =
      _Translations$settings$header$ko._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$ko diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$ko._(_root);
  @override
  late final _Translations$settings$release$ko release =
      _Translations$settings$release$ko._(_root);
  @override
  late final _Translations$settings$providerStatus$ko providerStatus =
      _Translations$settings$providerStatus$ko._(_root);
  @override
  late final _Translations$settings$meridiem$ko meridiem =
      _Translations$settings$meridiem$ko._(_root);
  @override
  late final _Translations$settings$offenders$ko offenders =
      _Translations$settings$offenders$ko._(_root);
}

// Path: sync
class _Translations$sync$ko extends Translations$sync$en {
  _Translations$sync$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$ko actions =
      _Translations$sync$actions$ko._(_root);
  @override
  late final _Translations$sync$panel$ko panel = _Translations$sync$panel$ko._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$ko forcePush =
      _Translations$sync$forcePush$ko._(_root);
}

// Path: xray
class _Translations$xray$ko extends Translations$xray$en {
  _Translations$xray$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$ko board = _Translations$xray$board$ko._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$ko cadence =
      _Translations$xray$cadence$ko._(_root);
  @override
  late final _Translations$xray$cards$ko cards = _Translations$xray$cards$ko._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$ko cardTitle =
      _Translations$xray$cardTitle$ko._(_root);
  @override
  late final _Translations$xray$grain$ko grain = _Translations$xray$grain$ko._(
    _root,
  );
  @override
  late final _Translations$xray$header$ko header =
      _Translations$xray$header$ko._(_root);
  @override
  late final _Translations$xray$hotspot$ko hotspot =
      _Translations$xray$hotspot$ko._(_root);
  @override
  late final _Translations$xray$inspector$ko inspector =
      _Translations$xray$inspector$ko._(_root);
  @override
  late final _Translations$xray$loadingCard$ko loadingCard =
      _Translations$xray$loadingCard$ko._(_root);
  @override
  late final _Translations$xray$metabolism$ko metabolism =
      _Translations$xray$metabolism$ko._(_root);
  @override
  late final _Translations$xray$multi$ko multi = _Translations$xray$multi$ko._(
    _root,
  );
  @override
  late final _Translations$xray$recency$ko recency =
      _Translations$xray$recency$ko._(_root);
  @override
  late final _Translations$xray$rings$ko rings = _Translations$xray$rings$ko._(
    _root,
  );
  @override
  late final _Translations$xray$stats$ko stats = _Translations$xray$stats$ko._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$ko stratumLabel =
      _Translations$xray$stratumLabel$ko._(_root);
  @override
  late final _Translations$xray$summary$ko summary =
      _Translations$xray$summary$ko._(_root);
  @override
  late final _Translations$xray$tabs$ko tabs = _Translations$xray$tabs$ko._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$ko trajectory =
      _Translations$xray$trajectory$ko._(_root);
  @override
  late final _Translations$xray$verdict$ko verdict =
      _Translations$xray$verdict$ko._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$ko extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '키보드';
  @override
  String get sectionNavigate => '이동';
  @override
  String get sectionStaging => '스테이징';
  @override
  String get sectionBranchesPrs => '브랜치 & PR';
  @override
  String get changes => '변경사항';
  @override
  String get history => '히스토리';
  @override
  String get branches => '브랜치';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => '전환 (항상)';
  @override
  String get commandPalette => '명령 팔레트';
  @override
  String get elevatedPalette => '확장 팔레트';
  @override
  String get dismiss => '닫기';
  @override
  String get refresh => '새로고침';
  @override
  String get nextPrevChange => '다음 / 이전 변경';
  @override
  String get toggleLine => '줄 토글';
  @override
  String get toggleHunk => '헝크 토글';
  @override
  String get toggleFile => '파일 토글';
  @override
  String get pinContext => '컨텍스트 고정';
  @override
  String get commit => '커밋';
  @override
  String get acceptAiHint => 'AI 힌트 수락';
  @override
  String get undo => '실행 취소';
  @override
  String get navigate => '이동';
  @override
  String get expand => '펼치기';
  @override
  String get checkoutPr => 'PR 체크아웃';
  @override
  String get approve => '승인';
  @override
  String get requestChanges => '변경 요청';
  @override
  String profileSwitchHint({required Object profile}) =>
      '${profile} 프로필 · 설정에서 전환';
}

// Path: backend.ops
class _Translations$backend$ops$ko extends Translations$backend$ops$en {
  _Translations$backend$ops$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get merge => '머지';
  @override
  String get pull => '풀';
  @override
  String get apply => '적용';
  @override
  String get switchOp => '전환';
  @override
  String get sync => '동기화';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$ko
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} 취소됨.';
  @override
  String complete({required Object op}) => '${op} 완료.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '충돌 ${n}개 남음 — 변경사항 페이지에서 해결하십시오.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '충돌 ${n}개 해결됨.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개에 커밋되지 않은 변경이 있습니다 — 먼저 커밋하십시오.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$ko extends Translations$changes$usage$en {
  _Translations$changes$usage$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} 입력 · ${output} 출력';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} 입력 · ${cached} 캐시 · ${out} 출력';
  @override
  String get inWord => '입력';
  @override
  String get cachedWord => '캐시';
  @override
  String get outWord => '출력';
  @override
  String tipIn({required Object value}) => '${value}  입력';
  @override
  String tipCacheRead({required Object value}) => '${value}  캐시 읽기';
  @override
  String tipCacheWrite({required Object value}) => '${value}  캐시 쓰기';
  @override
  String tipOut({required Object value}) => '${value}  출력';
  @override
  String tipReasoning({required Object value}) => '${value}  추론';
  @override
  String tipWallClock({required Object value}) => '${value}s  실측 시간';
}

// Path: changes.tabs
class _Translations$changes$tabs$ko extends Translations$changes$tabs$en {
  _Translations$changes$tabs$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => '변경사항';
  @override
  String get empty => '비어 있음';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$ko
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => '새 Diff 탭';
}

// Path: changes.select
class _Translations$changes$select$ko extends Translations$changes$select$en {
  _Translations$changes$select$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => '모두 선택';
  @override
  String get deselectAll => '모두 선택 해제';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$ko
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => '목록으로 돌아가기';
  @override
  String get atlas => '아틀라스, 커밋 후보 보기';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$ko
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\n결합 대상: ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$ko extends Translations$changes$minimap$en {
  _Translations$changes$minimap$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => '새로움';
  @override
  String get roleBridge => '브리지';
  @override
  String get roleHub => '허브';
  @override
  String get roleLeaf => '리프';
  @override
  String get roleConnected => '연결됨';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => '함께 변경: ${name}';
  @override
  String get newFile => '새 파일';
  @override
  String nearOtherChanges({required Object dir, required Object count}) =>
      '${dir}의 다른 변경 ${count}개 근처';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '보통 이 파일과 함께 변경됨: ${name}';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$ko
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hint => '태그…';
}

// Path: changes.composer
class _Translations$changes$composer$ko
    extends Translations$changes$composer$en {
  _Translations$changes$composer$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => '커밋 메시지…';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$ko extends Translations$changes$commit$en {
  _Translations$changes$commit$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => '변경 커밋';
  @override
  String get primaryCommitChangesDetail => '분리된 HEAD: 동기화 없이 로컬로 커밋합니다.';
  @override
  String get primaryPublish => '커밋 & 게시';
  @override
  String get primaryPublishDetail => '커밋을 생성하고 이 브랜치를 한 번에 게시합니다.';
  @override
  String get primarySync => '커밋 & 동기화';
  @override
  String get primarySyncDetail => '커밋을 생성한 뒤, 브랜치를 조정하고 내보냅니다.';
  @override
  String get primaryPush => '커밋 & 푸시';
  @override
  String get primaryPushDetail => '커밋을 생성하고 즉시 푸시합니다.';
  @override
  String get amendLast => '마지막 커밋 수정';
  @override
  String amendAnd({required Object action}) => '수정 & ${action}';
  @override
  String get chooseFile => '다음 커밋을 위해 최소 한 개 파일을 선택하십시오.';
  @override
  String get writeMessage => '먼저 커밋 메시지를 작성하십시오.';
  @override
  String get committing => '커밋 중';
  @override
  String get committingSync => '커밋 및 동기화 중';
  @override
  String get committed => '커밋됨.';
  @override
  String get undoFailed => '실행 취소 실패.';
  @override
  String get working => '작업 중…';
  @override
  String get commitOnly => '커밋만';
  @override
  String get noRuntimeModels => '커밋 메시지에 사용할 수 있는 런타임 발견 모델이 없습니다.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\n제외된 파일의 스테이징을 복원할 수 없습니다. 다시 시도하기 전에 인덱스를 확인하십시오.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      '${summary} 커밋됨 (${hash}).';
  @override
  String get restoreFailedSync =>
      '제외된 파일의 선택을 다시 스테이징할 수 없습니다. 동기화를 건너뜁니다. 동기화 전에 인덱스를 확인하십시오.';
  @override
  String get noModelLabel => '모델 없음';
  @override
  String get chooseBeforeGenerate => '생성 전에 최소 한 개 파일을 선택하십시오.';
  @override
  String get aiUnavailable => '커밋 메시지 AI를 아직 사용할 수 없습니다.';
  @override
  String get generateFailed => '생성 실패.';
  @override
  String get stageFailed => '파일 스테이징에 실패했습니다.';
  @override
  String get commitFailed => '커밋 실패.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => '${summary} 커밋됨 (${hash}), ${operation} 실행함.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
    n,
    other: '${summary} 커밋됨 (${hash}); 충돌 ${n}개 해결.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '해결할 충돌 ${n}개 남음.',
      );
  @override
  String syncBlocked({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '커밋은 성공했지만, 커밋되지 않은 파일 ${n}개로 동기화가 차단됐습니다.',
      );
  @override
  String syncStalled({required Object message}) =>
      '커밋은 성공했지만, 동기화가 정체됐습니다: ${message}';
  @override
  String syncFailed({required Object message}) =>
      '커밋은 성공했지만, 동기화에 실패했습니다: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$ko extends Translations$changes$rebase$en {
  _Translations$changes$rebase$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => '리베이스를 계속할 수 없습니다.';
}

// Path: changes.editor
class _Translations$changes$editor$ko extends Translations$changes$editor$en {
  _Translations$changes$editor$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => '편집기 닫기';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$ko
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    '친애하는 git log에게',
    'git이시여, 저를 용서하소서, 제가 지은 죄가…',
    '이 순간에 이름을',
    '떠들어 봐',
    '말하라!',
    '네 어미는 dangling reference였고 네 아비에게선 세미콜론 냄새가 났다',
  ];
  @override
  List<String> get short => [
    '오?',
    '안녕하세요:)',
    '그나저나:',
    '몇 마디',
    '정중한 버전',
    '메모 남기기',
    '무슨 말이었죠..?',
    '그래, 다 털어놔',
  ];
  @override
  List<String> get mid => [
    '기록을 위해',
    '미래의 너에게 전해',
    '그전에?',
    '어떻게 됐는지',
    '네 말로',
    '너 방금 뭘 했다고?',
    '잘 접수했음',
    '귀 기울이고 있어',
  ];
  @override
  List<String> get long => [
    '당신의 꿈을, 부디',
    '좋은 말 좀 해봐',
    '… 그러고 나서 내가 말했지:',
    '후세가 기다린다',
    '더 많이 쓰면 버그가 사라진다',
    '우와',
    '성스러운 경전',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$ko extends Translations$changes$askHint$en {
  _Translations$changes$askHint$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) => '라운드 ${n} — 다듬거나 맥락을 추가하십시오.';
  @override
  String get symptom => '증상을 설명하십시오.';
  @override
  String get broken => '무엇이 고장 났습니까?';
  @override
  String get bug => '버그를 설명하십시오.';
  @override
  String get error => '오류를 붙여넣으십시오.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$ko
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => '물결';
  @override
  String get includeCoChanges => '공동 변경 포함';
  @override
  String deleteFile({required Object name}) => '${name} 삭제…';
  @override
  String discardChangesTo({required Object name}) => '${name}의 변경 버리기…';
  @override
  String get ignore => '무시';
  @override
  String get diffTabFromSelection => '선택 항목으로 Diff 탭';
  @override
  String addSelectedToTab({required Object name}) => '선택 항목을 ${name}에 추가';
  @override
  String diffTabFromFile({required Object name}) => '${name}에서 Diff 탭';
  @override
  String addFileToTab({required Object tab, required Object file}) =>
      '${tab}에 ${file} 추가';
  @override
  String get copyFilePath => '파일 경로 복사';
  @override
  String get showInExplorer => '탐색기에서 보기';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$ko
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => '단단히 결합됨';
  @override
  String get cohesionLoose => '느슨하게 관련됨';
  @override
  String get cohesionScattered => '구조적으로 흩어짐';
  @override
  String get clusterOne => '모두 한 클러스터에';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      '클러스터 ${count}개에 걸침 (파일 ${parts}개)';
  @override
  String clusterSpans({required Object count}) => '클러스터 ${count}개에 걸침';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '파일 ${count}개 · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '보통 이 그룹과 함께 변경됨: ${file}';
  @override
  String get splitToNewTab => '새 탭으로 분리';
  @override
  String copyPaths({required Object count}) => '경로 ${count}개 복사';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$ko
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => '.${ext} 확장자';
  @override
  String allSelected({required Object count}) => '선택된 ${count}개 전체';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '포함된 파일 ${n}개와 결합',
      );
  @override
  String get updateFailed => '.gitignore 업데이트에 실패했습니다.';
}

// Path: changes.discard
class _Translations$changes$discard$ko extends Translations$changes$discard$en {
  _Translations$changes$discard$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '${name} 삭제하시겠습니까?';
  @override
  String discardTitle({required Object name}) => '${name}의 변경을 버리시겠습니까?';
  @override
  String deleteBody({required Object path}) =>
      '${path} — 디스크에서 제거됩니다. 앱 내부에서는 되돌릴 수 없습니다.';
  @override
  String discardBody({required Object path}) =>
      '${path}의 모든 변경이 HEAD 상태로 되돌아갑니다. 되돌릴 수 없습니다.';
  @override
  String get discard => '버리기';
  @override
  String deletingFile({required Object name}) => '${name} 삭제 중';
  @override
  String discardingFile({required Object name}) => '${name} 버리는 중';
  @override
  String get discardFailed => '변경 버리기에 실패했습니다.';
  @override
  String discardManyTitle({required Object count}) =>
      '파일 ${count}개의 변경을 버리시겠습니까?';
  @override
  String get discardManyBody =>
      '추적된 파일은 HEAD 상태로 되돌아가고, 추적되지 않은 파일은 디스크에서 제거됩니다. 되돌릴 수 없습니다.';
  @override
  String discardManyConfirm({required Object count}) => '${count}개 버리기';
  @override
  String discardingManyFiles({required Object count}) => '파일 ${count}개 버리는 중';
  @override
  String failedOpenExplorer({required Object error}) =>
      '파일 탐색기 열기 실패: ${error}';
  @override
  String get someFailed => '일부 버리기에 실패했습니다.';
}

// Path: changes.snack
class _Translations$changes$snack$ko extends Translations$changes$snack$en {
  _Translations$changes$snack$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => '같은 작업 트리 — 버릴 것이 없습니다.';
  @override
  String diffFailed({required Object error}) => 'Diff 실패: ${error}';
  @override
  String get deskEmpty => 'Desk에 앞선 것이 없습니다 — 빈 덤프.';
  @override
  String sourceDesk({required Object label}) => 'Desk ${label}';
  @override
  String shelfReadFailed({required Object error}) => '선반 읽기 실패: ${error}';
  @override
  String get shelfEmpty => '빈 선반 — 버릴 것이 없습니다.';
  @override
  String sourceShelf({required Object label}) => '선반 ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      '"${label}"에 구성된 모델이 없습니다.';
  @override
  String fetchFailed({required Object error}) => '페치 실패: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$ko extends Translations$changes$trace$en {
  _Translations$changes$trace$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '검증 추적';
  @override
  String get draftReview => '초안 리뷰';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$ko
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '작업 트리 깨끗함';
  @override
  String get subtitle => '스테이징되거나 스테이징되지 않은 변경이 감지되지 않았습니다.';
  @override
  String get noUpstream => '  ·  업스트림 없음';
  @override
  String get ahead => ' 앞섬';
  @override
  String get behind => ' 뒤처짐';
  @override
  String get refreshing => '새로고침 중…';
  @override
  String get refresh => '새로고침';
  @override
  String get check => '확인';
  @override
  String get checkTooltip => '페치 및 로컬 새로고침.';
  @override
  String get sync => '& 동기화';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$ko
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '느슨';
  @override
  String get balanced => '균형';
  @override
  String get strict => '엄격';
  @override
  String get paranoid => '편집증';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$ko
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf => '이 선반의 변경을 여기로 가져오려면 놓으십시오';
  @override
  String get fromDesk => '이 Desk의 변경을 여기로 가져오려면 놓으십시오';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$ko
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '선택된 파일 없음';
  @override
  String get message => 'diff를 살펴보려면 변경된 파일을 선택하십시오.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$ko
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ ${count}개 보류';
  @override
  String get shelve => '↓ 보류';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count}개 보류됨 ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$ko
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => '가져오기';
  @override
  String get peek => '엿보기';
  @override
  String get toss => '버리기';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$ko
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get reading => '선반 읽는 중…';
  @override
  String get empty => '빈 선반';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$ko
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get binary => '바이너리';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$ko extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => '스테이징된 줄만 커밋';
  @override
  String get doubleClickToggle => '더블클릭: 전체 그룹 토글';
  @override
  String get repoRoot => '저장소 루트';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$ko
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개 읽는 중 · 해결 초안 작성 중…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${files}에 걸쳐 충돌 ${n}개',
      );
  @override
  String get resolve => '해결';
  @override
  String get orWith => '또는';
  @override
  String resolveWith({required Object label}) => '${label} 사용해 해결';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      '${label} 사용해 해결  ·  ${model}';
  @override
  String get resolving => '해결 중…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  ${label} 사용해 해결';
  @override
  String get orWithAnother => '또는 다른 모델로';
}

// Path: changes.badge
class _Translations$changes$badge$ko extends Translations$changes$badge$en {
  _Translations$changes$badge$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => '스테이징된 편집';
  @override
  String get edited => '편집됨';
  @override
  String get stagedAdd => '스테이징된 추가';
  @override
  String get added => '추가됨';
  @override
  String get stagedDelete => '스테이징된 삭제';
  @override
  String get deleted => '삭제됨';
  @override
  String get stagedRename => '스테이징된 이름 변경';
  @override
  String get renamed => '이름 변경됨';
  @override
  String get stagedCopy => '스테이징된 복사';
  @override
  String get copied => '복사됨';
  @override
  String get conflict => '충돌';
  @override
  String get stagedTypeChange => '스테이징된 타입 변경';
  @override
  String get typeChanged => '타입 변경됨';
  @override
  String get untracked => '추적 안 됨';
}

// Path: changes.review
class _Translations$changes$review$ko extends Translations$changes$review$en {
  _Translations$changes$review$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '코드 리뷰';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '포함된 파일 ${n}개',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '헝크 ${n}개',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => '리뷰를 사용할 수 없음';
  @override
  String get backToDiff => 'diff로 돌아가기';
  @override
  String get verified => '검증됨';
  @override
  String get draftOnly => '초안만';
  @override
  String get runAgain => '다시 실행';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} 아래에 초안 리뷰가 표시됩니다.';
  @override
  String get hideTrace => '추적 숨기기';
  @override
  String get showTrace => '추적 보기';
  @override
  String get showVerificationTrace => '검증 추적 보기';
  @override
  String get whyLanded => '이 리뷰가 여기에 이른 이유';
  @override
  String get noFindings => '발견 없음';
  @override
  String get findings => '발견';
  @override
  String get noEvidenceIssues => '이 커밋 범위에서 증거에 기반한 문제가 드러나지 않았습니다.';
  @override
  String get observations => '관찰';
  @override
  String get chooseBeforeReview => '리뷰 전에 최소 한 개 파일을 선택하십시오.';
  @override
  String get aiUnavailable => '리뷰 AI를 아직 사용할 수 없습니다.';
  @override
  String get failed => '리뷰 실패.';
  @override
  String get noRuntimeModels => '커밋 리뷰에 사용할 수 있는 런타임 발견 모델이 없습니다.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$ko
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => '전환: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$ko
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => '${cat} 사용해 묻는 중…';
  @override
  String askWith({required Object cat}) => '${cat} 사용해 묻기';
  @override
  String get noModel => '구성된 AI 모델 없음';
  @override
  String nextTooltip({required Object cat}) => '다음: ${cat}  ·  이전은 shift-클릭';
  @override
  String get onlyOne => '구성된 AI 카테고리가 하나뿐';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$ko extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({required num n, required Object pct}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${pct}% 데자뷰 — 버려진 타임라인의 유령 간선 ${n}개가 이 diff를 건드림',
      );
  @override
  String get label => '데자뷰';
}

// Path: changes.identity
class _Translations$changes$identity$ko
    extends Translations$changes$identity$en {
  _Translations$changes$identity$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get none => '구성된 커밋 신원 없음';
  @override
  String asName({required Object name}) => '${name} 이름으로';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      '${name} <${email}> 이름으로';
  @override
  String asNameSpace({required Object name}) => '${name} 이름으로 ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\n이 저장소의 첫 커밋';
  @override
  String get newToRepo => '\n이 저장소에 처음';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$ko
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get message => '실행 이후 선택이 변경됨';
  @override
  String get rerun => '다시 실행';
}

// Path: changes.finding
class _Translations$changes$finding$ko extends Translations$changes$finding$en {
  _Translations$changes$finding$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'diff 열기';
  @override
  String get recorded => '기록됨';
  @override
  String get dismiss => '닫기';
}

// Path: changes.muse
class _Translations$changes$muse$ko extends Translations$changes$muse$en {
  _Translations$changes$muse$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => '당신이 이걸 끌어냈습니다';
  @override
  String fromIdea({required Object text}) => '아이디어에서: "${text}"';
  @override
  String get foothold => '발판 — ';
  @override
  String get brainstormSpew => '브레인스톰 분출';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => '${count}개 복사';
  @override
  String get clear => '지우기';
  @override
  String get chooseBeforeMuse => 'muse를 호출하기 전에 최소 한 개 파일을 선택하십시오.';
  @override
  String get aiUnavailable => 'Muse AI를 아직 사용할 수 없습니다.';
  @override
  String get failed => 'Muse 실패.';
  @override
  String get noRuntimeModels => 'muse에 사용할 수 있는 런타임 발견 모델이 없습니다.';
  @override
  String get needsModel => 'Muse에는 구성된 모델이 최소 하나 필요합니다.';
  @override
  String get dreaming => 'muse가 꿈꾸는 중…';
}

// Path: changes.debug
class _Translations$changes$debug$ko extends Translations$changes$debug$en {
  _Translations$changes$debug$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '디버그';
  @override
  String round({required Object n}) => '· 라운드 ${n}';
  @override
  String get clear => '지우기';
  @override
  String get close => '닫기';
  @override
  String get analyzing => '증상 분석 중…';
  @override
  String get describeSymptom => '증상을 설명한 뒤 디버그를 누르십시오.';
  @override
  String get evidenceFor => '근거';
  @override
  String get evidenceAgainst => '반증';
  @override
  String get narrowDown => '범위를 좁히는 데 도움이 될 것:';
  @override
  String get failed => '디버그 실패.';
  @override
  String get refinementFailed => '디버그 정제 실패.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$ko
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get none => '없음';
  @override
  String stagedSuffix({required Object count}) => ' · ${count}개 스테이징됨';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '전체 ${n}개 파일${staged}',
      );
  @override
  String partial({
    required Object n,
    required Object count,
    required Object staged,
  }) => '${n}개 중 ${count}개${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      '전체 ${n}개${staged}';
}

// Path: changes.status
class _Translations$changes$status$ko extends Translations$changes$status$en {
  _Translations$changes$status$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => '저장소 상태를 사용할 수 없음';
  @override
  String get loadingTitle => '저장소 상태 불러오는 중';
  @override
  String get loadingMessage => '작업 트리를 읽는 중.';
}

// Path: changes.stash
class _Translations$changes$stash$ko extends Translations$changes$stash$en {
  _Translations$changes$stash$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      '충돌과 함께 스태시가 적용됐습니다 — 변경사항 페이지에서 해결하십시오 (스태시 항목은 유지됨).';
  @override
  String get couldNotPop => '스태시를 팝할 수 없습니다.';
  @override
  String get listChanged => '스태시 목록이 변경됐습니다. 버리기를 건너뜁니다. 다시 시도하십시오.';
  @override
  String get droppingStash => '스태시 버리는 중';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$ko
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => '커밋 메시지 생성 중…';
  @override
  String get commitPreparing => '커밋 메시지 준비 중…';
  @override
  String get commitSelectFile => '커밋 메시지를 생성하려면 최소 한 개 파일을 선택하십시오.';
  @override
  String get commitConfigure => '설정 > 행동 다이내믹스 > 커밋 메시지에서 커밋 메시지를 구성하십시오.';
  @override
  String get fastFallback => '빠름';
  @override
  String commitGenerateWith({required Object label}) =>
      '${label} 모델로 커밋 메시지 생성';
  @override
  String get museConsulting => 'muse에게 자문 중…';
  @override
  String get showMuse => 'muse 보기';
  @override
  String get museSelectFile => 'muse를 위해 최소 한 개 파일을 선택하십시오.';
  @override
  String get showMuseError => 'muse 오류 보기';
  @override
  String get museAsk => 'muse에게 방향을 묻기';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'muse에게 방향을 묻기\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => '품질';
  @override
  String get reviewing => '리뷰 중…';
  @override
  String get showReview => '리뷰 보기';
  @override
  String get reviewPreparing => '커밋 리뷰 준비 중…';
  @override
  String get reviewSelectFile => '리뷰하려면 최소 한 개 파일을 선택하십시오.';
  @override
  String get reviewConfigure => '설정에서 리뷰 AI를 구성하십시오.';
  @override
  String get viewingReview => '리뷰 보는 중';
  @override
  String reviewWith({required Object label, required Object guardrail}) =>
      '${label} 모델로 ${guardrail} 리뷰';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$ko
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => '내 것';
  @override
  String get resolutionTheirs => '상대 것';
  @override
  String get resolutionCustom => '사용자 정의';
  @override
  String get keepBoth => '둘 다 유지';
  @override
  late final _Translations$changes$mergeEditor$trust$ko trust =
      _Translations$changes$mergeEditor$trust$ko._(_root);
  @override
  String get allResolved => '모두 해결됨';
  @override
  String get resolveEasy => '쉬운 충돌 해결';
  @override
  String get base => '기준';
  @override
  String get cancel => '취소';
  @override
  String get save => '저장';
  @override
  String get complete => '완료';
  @override
  String get nextFile => '다음 파일';
  @override
  String get edit => '편집';
  @override
  String get auto => '자동';
  @override
  String get undo => '실행 취소';
  @override
  late final _Translations$changes$mergeEditor$keyHints$ko keyHints =
      _Translations$changes$mergeEditor$keyHints$ko._(_root);
  @override
  String get favoredTooltip => '결합 분석에 의해 구조적으로 선호됨';
  @override
  String get newOnBothSides => '(양쪽 모두 새로움)';
  @override
  String writeFailed({required Object error}) => '해결된 파일 쓰기 실패: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '이웃 ${changed}/${total}개 공동 변경됨';
  @override
  String integrity({required Object pct}) => '무결성 ${pct}%';
  @override
  String reviewer({required Object name}) => '리뷰어: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$ko
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      '"${category}"에 구성된 모델이 없습니다. 설정 → AI에서 설정하십시오.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '민감한 파일 ${n}개 건너뜀 — 직접 해결하십시오.',
      );
  @override
  String get couldNotReadFiles => '충돌 파일을 하나도 읽을 수 없습니다.';
  @override
  String blockedSecret({required Object secret}) =>
      '차단됨 — 충돌 파일에 ${secret} 유형의 비밀이 포함된 것으로 보입니다. 직접 해결하십시오.';
  @override
  String resolutionFailed({required Object error}) => '해결 실패: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ 머지 해결 · 파일 ${resolved}/${total}개 · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object files,
    required Object conflicts,
  }) => '${op} · ${files}에 걸쳐 ${conflicts}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '충돌 ${n}개',
      );
  @override
  String get mergeEditorButton => '⇋ 머지 편집기';
  @override
  String get noAiModel => 'AI 모델 없음';
  @override
  String get later => '나중에';
  @override
  String get discard => '버리기';
  @override
  String get resolveWithAi => '◇ AI로 해결';
  @override
  String get otherModel => '다른 모델';
  @override
  String withModel({required Object model}) => '${model} 사용';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$ko
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$ko op =
      _Translations$changes$mergeFlow$op$ko._(_root);
  @override
  String get pushFailed => '푸시 실패';
  @override
  String get rebasedAndPushed => '리베이스 후 푸시했습니다.';
  @override
  String switchedTo({required Object name}) => '이제 ${name}에 있습니다.';
  @override
  String get switchFailed => '전환 실패.';
  @override
  String switchedToCarried({required Object name}) =>
      '이제 ${name}에 있습니다 (변경 이어짐).';
  @override
  String get alreadyUpToDate => '이미 최신입니다.';
  @override
  String merged({required Object upstream, required Object n}) =>
      '${upstream} 머지됨 (파일 ${n}개).';
  @override
  String get rebaseNotConverge => '리베이스가 수렴하지 않았습니다 — 직접 해결하십시오.';
  @override
  String get rebased => '리베이스됨.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '리베이스됨 (파일 ${n}개 해결).',
      );
  @override
  String get detachedHead => '동기화할 수 없음: 분리된 HEAD 상태입니다. 먼저 브랜치를 체크아웃하십시오.';
  @override
  String get publishFailed => '게시 실패.';
  @override
  String get noRemote => '구성된 원격이 없습니다. 이 브랜치를 게시하려면 하나 추가하십시오.';
  @override
  String get failed => '실패';
}

// Path: changes.constellation
class _Translations$changes$constellation$ko
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => '구조';
  @override
  String get axisCoChange => '공동 변경';
  @override
  String get axisSpectralProfile => '스펙트럴 프로파일';
  @override
  String get axisPathSiblings => '경로 형제';
  @override
  String get axisDiffStructure => 'DIFF 구조';
  @override
  String get axisSpectral => '스펙트럴';
  @override
  String get titleUnsorted => '정렬 안 됨';
  @override
  String get titleSingleton => '싱글턴';
  @override
  String get titleMixed => '혼합';
  @override
  String get untie => '풀기';
  @override
  String get bind => '묶기';
  @override
  String get emptyClusters => '아직 클러스터 없음';
}

// Path: common.time
class _Translations$common$time$ko extends Translations$common$time$en {
  _Translations$common$time$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get now => '지금';
  @override
  String get justNow => '방금';
  @override
  String get today => '오늘';
  @override
  String minutesAgo({required Object n}) => '${n}분 전';
  @override
  String hoursAgo({required Object n}) => '${n}시간 전';
  @override
  String daysAgo({required Object n}) => '${n}일 전';
  @override
  String weeksAgo({required Object n}) => '${n}주 전';
  @override
  String monthsAgo({required Object n}) => '${n}개월 전';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        one: '${n}년 전',
        other: '${n}년 전',
      );
  @override
  String minutesShort({required Object n}) => '${n}분';
  @override
  String hoursShort({required Object n}) => '${n}시간';
  @override
  String daysShort({required Object n}) => '${n}일';
  @override
  String weeksShort({required Object n}) => '${n}주';
  @override
  String monthsShort({required Object n}) => '${n}개월';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        one: '${n}년',
        other: '${n}년',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}개월';
  @override
  String get idle => '유휴';
  @override
  String idleDays({required Object n}) => '유휴 ${n}일';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '유휴 ${n}년',
      );
  @override
  List<String> get monthAbbrevs => [
    '1월',
    '2월',
    '3월',
    '4월',
    '5월',
    '6월',
    '7월',
    '8월',
    '9월',
    '10월',
    '11월',
    '12월',
  ];
}

// Path: common.size
class _Translations$common$size$ko extends Translations$common$size$en {
  _Translations$common$size$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

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
class _Translations$diff$status$ko extends Translations$diff$status$en {
  _Translations$diff$status$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'diff 불러오는 중';
  @override
  String get loadingMessage => '파일 변경 내용을 읽는 중.';
  @override
  String get unavailableTitle => 'diff를 사용할 수 없음';
  @override
  String get noChangesTitle => '변경 없음';
  @override
  String get noChangesMessage => '이 파일에는 표시할 diff 내용이 없습니다.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$ko extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'diff 검색…';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${n}줄',
      );
  @override
  String get blameLoading => 'blame…';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => '마모 · 켜짐';
  @override
  String get wearMapOnHint => '마모 지도 켜짐 — 클릭하여 숨기기';
  @override
  String get wearMapOffHint => '마모 지도 표시(활동 히트맵)';
  @override
  String get trailBadge => '· 자취';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$ko
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => '변경 블록으로 이동. git은 이를 헝크라고 부릅니다.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '변경 ${n}개',
      );
}

// Path: diff.trail
class _Translations$diff$trail$ko extends Translations$diff$trail$en {
  _Translations$diff$trail$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '자취 불러오는 중…';
  @override
  String get noHistory => '히스토리 없음';
  @override
  String get nowWorkingCopy => '지금 · 작업 사본';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$ko extends Translations$diff$pinned$en {
  _Translations$diff$pinned$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => '고정된 컨텍스트 불러오는 중';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => '신호';
  @override
  String get echoesTitle => '메아리';
  @override
  String get technicalLedger => '기술 원장';
  @override
  String get noSecondaryCues => '부차적 단서가 감지되지 않았습니다.';
  @override
  String get linkedPaths => '연결된 경로';
  @override
  String moreCount({required Object n}) => '+${n}개 더';
  @override
  String get localSeam => '로컬 이음새';
  @override
  String get sharedOwnership => '공동 소유';
  @override
  String get historyWarmingUp => '히스토리 예열 중';
  @override
  String echoesTotal({required Object n}) => '총 ${n}개';
  @override
  String get noEchoes => '이 diff에는 메아리가 없습니다.';
  @override
  String openRelatedFile({required Object name}) => '관련 파일 ${name} 열기';
  @override
  String inspectFile({required Object name}) => '${name} 살펴보기';
  @override
  String get jumpEcho => '메아리로 이동';
  @override
  String get copyLine => '줄 복사';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$ko tempo =
      _Translations$diff$pinned$tempo$ko._(_root);
  @override
  late final _Translations$diff$pinned$tone$ko tone =
      _Translations$diff$pinned$tone$ko._(_root);
  @override
  late final _Translations$diff$pinned$summary$ko summary =
      _Translations$diff$pinned$summary$ko._(_root);
  @override
  late final _Translations$diff$pinned$tightness$ko tightness =
      _Translations$diff$pinned$tightness$ko._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => '왜 중요한가';
  @override
  String get storyConfidence => '신뢰도';
  @override
  String get storySecondarySignal => '부차 신호';
  @override
  String get storyNeighbourhood => '이웃';
  @override
  String neighbourhoodDetail({required Object name}) =>
      '이 줄은 현재 코드베이스 필드에서 ${name} 가까이에 위치합니다.';
  @override
  String get propagationLane => '전파 레인';
  @override
  String propagationLaneNamed({required Object lane}) => '전파 레인: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$ko witness =
      _Translations$diff$pinned$witness$ko._(_root);
  @override
  late final _Translations$diff$pinned$integrity$ko integrity =
      _Translations$diff$pinned$integrity$ko._(_root);
  @override
  late final _Translations$diff$pinned$related$ko related =
      _Translations$diff$pinned$related$ko._(_root);
  @override
  late final _Translations$diff$pinned$axis$ko axis =
      _Translations$diff$pinned$axis$ko._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$ko extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n}개 숨김';
  @override
  String get landing => '착지';
}

// Path: diff.binary
class _Translations$diff$binary$ko extends Translations$diff$binary$en {
  _Translations$diff$binary$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (너무 커서 미리보기 불가)';
  @override
  String get unableToLoadBlob => 'blob을 불러올 수 없음';
  @override
  String get omittedKindMedia => '미디어';
  @override
  String get omittedKindBinary => '바이너리';
  @override
  String omittedStub({required Object kind}) => '${kind} · 숨김';
}

// Path: diff.media
class _Translations$diff$media$ko extends Translations$diff$media$en {
  _Translations$diff$media$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => '이미지를 디코딩할 수 없음';
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
  String get stateAdded => '추가됨';
  @override
  String get stateDeleted => '삭제됨';
  @override
  String get stateModified => '수정됨';
  @override
  String get fallbackFormatName => '바이너리';
}

// Path: filament.severity
class _Translations$filament$severity$ko
    extends Translations$filament$severity$en {
  _Translations$filament$severity$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get critical => '심각';
  @override
  String get warn => '경고';
  @override
  String get info => '정보';
  @override
  String get joint => '결합';
}

// Path: filament.kind
class _Translations$filament$kind$ko extends Translations$filament$kind$en {
  _Translations$filament$kind$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => '오래된 값';
  @override
  String get temporalShift => '시간적 이동';
  @override
  String get contextInversion => '컨텍스트 반전';
  @override
  String get contradictoryFlow => '모순된 흐름';
}

// Path: history.commitLede
class _Translations$history$commitLede$ko
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$ko semantics =
      _Translations$history$commitLede$semantics$ko._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$ko
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(루트)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n}개 더';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${path}/에 파일 ${n}개',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개 더',
      );
  @override
  String get breadcrumbAll => '전체';
  @override
  String breadcrumbCurrentFocus({required Object target}) => '현재 초점: ${target}';
  @override
  String get breadcrumbViewAllChanges => '이 커밋의 모든 변경 보기';
  @override
  String breadcrumbDrillUpTo({required Object target}) => '${target}까지 올라가기';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
    n,
    other: '파일 ${n}개  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '하위 폴더 ${n}개',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds}개 추가, ${dels}개 삭제';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
    n,
    other: '파일 ${n}개, ${adds}개 추가, ${dels}개 삭제',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '헝크 ${n}개',
      );
  @override
  String get largestChangeInView => '이 화면에서 가장 큰 변경';
  @override
  String get conflictedTag => '충돌';
  @override
  String get dirtyTag => '더러움';
  @override
  String get drillInTag => '파고들기';
  @override
  String get changeTypeRenamed => '이름 변경됨';
  @override
  String get changeTypeCopied => '복사됨';
  @override
  String get changeTypeTypechange => '타입 변경';
  @override
  String get changeTypeConflict => '충돌';
  @override
  String get coreFile => '핵심 파일';
  @override
  String get staleFile => '오래됨';
  @override
  String get filterPathHint => '경로 필터';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$ko
    extends Translations$history$worldline$en {
  _Translations$history$worldline$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => '월드라인 닫기';
  @override
  String get dragToOpenWorldline => '드래그하여 월드라인 열기';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$ko
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => '현재 브랜치';
  @override
  String applyCommitOnto({required Object branch}) => '${branch}에 커밋 변경 적용';
  @override
  String revertCommitOn({required Object branch}) => '${branch}에서 커밋 변경 되돌리기';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$ko
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get paused => '체리픽 일시 중지됨. 남은 충돌을 변경사항 페이지에서 마무리하십시오.';
  @override
  String failed({required Object error}) => '체리픽 실패: ${error}';
  @override
  String pickedResolved({required Object short}) => '${short} 체리픽됨 (충돌 해결)';
  @override
  String picked({required Object short}) => '${short} 체리픽됨';
}

// Path: history.revert
class _Translations$history$revert$ko extends Translations$history$revert$en {
  _Translations$history$revert$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get paused => '되돌리기 일시 중지됨. 남은 충돌을 변경사항 페이지에서 마무리하십시오.';
  @override
  String failed({required Object error}) => '되돌리기 실패: ${error}';
  @override
  String revertedResolved({required Object short}) => '${short} 되돌림 (충돌 해결)';
  @override
  String reverted({required Object short}) => '${short} 되돌림';
}

// Path: history.reflog
class _Translations$history$reflog$ko extends Translations$history$reflog$en {
  _Translations$history$reflog$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => '여기서 브랜치 생성…';
  @override
  String get copyCommitHash => '커밋 해시 복사';
  @override
  String get createBranchDialogTitle => 'reflog 항목에서 브랜치 생성';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      '앵커: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => '브랜치 이름';
  @override
  String get createAction => '생성';
  @override
  String createBranchFailed({required Object error}) => '브랜치 생성 실패: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      '"${name}" 브랜치를 ${short}에 생성했습니다.';
}

// Path: history.rebase
class _Translations$history$rebase$ko extends Translations$history$rebase$en {
  _Translations$history$rebase$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      '첫 커밋은 ${action}할 수 없습니다';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '커밋 ${n}개 리베이스',
      );
  @override
  String get resetLabel => '리셋';
  @override
  String get dragToReorderHint => '드래그하여 재정렬, 커밋별 동작 선택';
  @override
  String get newMessageHint => '새 메시지';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => '리베이스 시작';
}

// Path: history.inFlight
class _Translations$history$inFlight$ko
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get header => '진행 중';
  @override
  String get deskFallbackLabel => 'Desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$ko
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '히스토리 수술';
  @override
  String get alphaBadge => '알파';
  @override
  String get dryRunBadge => '드라이 런';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$ko
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => '히스토리에서 제거할 파일 선택';
  @override
  String selectedCount({required Object n}) => '${n}개 선택됨';
  @override
  String get searchHint => '검색…';
  @override
  String get readingTree => '트리 읽는 중…';
  @override
  String get continueDisabled => '계속하려면 파일을 선택하십시오';
  @override
  String get continueEnabled => '계속 →';
  @override
  String toPurgeCount({required Object n}) => '제거 대상 ${n}개';
  @override
  String get analyzing => '분석 중…';
  @override
  String get riskLow => '낮은 위험';
  @override
  String get riskModerate => '보통 위험';
  @override
  String get riskHigh => '높은 위험';
  @override
  String get impactCommitsLabel => '커밋';
  @override
  String get impactBranchesLabel => '브랜치';
  @override
  String get impactWorktreesLabel => '작업 트리';
  @override
  String get impactCouplingLabel => '결합';
  @override
  String get impactCouplingIsland => '고립';
  @override
  String impactCouplingNeighbors({required Object n}) => '이웃 ${n}개';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$ko
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get heading => '작동 방식';
  @override
  String get backupTitle => '백업';
  @override
  String get backupBody =>
      '무엇이든 변경되기 전에 모든 브랜치와 태그 ref가 백업 네임스페이스로 복사됩니다. 문제가 생기면 한 번의 클릭으로 원래 상태를 복원합니다.';
  @override
  String get rewriteTitle => '재작성';
  @override
  String get rewriteBody =>
      '각 커밋을 루트에서 팁까지 순회합니다. 대상 파일을 포함한 모든 커밋에 대해, 트리에서 해당 파일을 제거한 새 커밋을 생성합니다. 위상을 보존하도록 부모 체인을 다시 매핑합니다. ';
  @override
  String rewriteSummary({required Object total, required Object affected}) =>
      '${total}개 커밋 중 ${affected}개가 재작성됩니다.';
  @override
  String get updateRefsTitle => 'ref 업데이트';
  @override
  String get updateRefsBody =>
      '브랜치와 태그 포인터가 새 커밋 SHA로 이동합니다. 이전 객체는 가비지 컬렉션 전까지 남아 있습니다. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      '작업 트리 ${n}개를 다시 체크아웃해야 합니다.';
  @override
  String get noWorktreesAffected => '영향받는 작업 트리가 없습니다.';
  @override
  String get forcePushTitle => '강제 푸시';
  @override
  String get forcePushBody =>
      '제거를 검증한 뒤, 강제 푸시할 브랜치를 선택합니다. --force-with-lease를 사용하므로 그사이 다른 사람이 푸시했다면 안전하게 실패합니다.';
  @override
  String get plumbingNote =>
      'filter-repo나 BFG와 달리, 이 작업은 전적으로 git 플러밍 명령(cat-file, mktree, commit-tree, update-ref)으로 실행됩니다. 외부 의존성이 없습니다. 이름 변경 추적은 파일당 하나의 체인을 따릅니다 — 파일이 복사되고 두 복사본이 각각 이름 변경된 경우, 실행 후 제거 결과를 검증하십시오.';
  @override
  String get back => '← 뒤로';
  @override
  String get continueLabel => '이해했습니다, 계속 →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$ko
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) => '커밋 ${n}개가 재작성됩니다';
  @override
  String get forcePushRequired => '원격 브랜치에는 강제 푸시가 필요합니다';
  @override
  String worktreesRecheckout({required Object n}) =>
      '작업 트리 ${n}개를 다시 체크아웃해야 합니다';
  @override
  String stashesInvalid({required Object n}) => '스태시 ${n}개가 무효가 될 수 있습니다';
  @override
  String get heading => '이 작업은 git 히스토리를 재작성합니다';
  @override
  String get subheading => '강제 푸시 후에는 자동으로 되돌릴 수 없습니다.';
  @override
  String typeHint({required Object word}) => '${word} 입력';
  @override
  String get goBack => '뒤로 가기';
  @override
  String get begin => '수술 시작';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$ko
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => '준비 중…';
  @override
  String get backingUpRefs => 'ref 백업 중…';
  @override
  String get rewritingCommits => '커밋 재작성 중…';
  @override
  String get updatingRefs => 'ref 업데이트 중…';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$ko
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get complete => '수술 완료';
  @override
  String get failed => '수술 실패';
  @override
  String get commitsRewrittenLabel => '재작성된 커밋';
  @override
  String get refsUpdatedLabel => '업데이트된 ref';
  @override
  String get oldHeadLabel => '이전 HEAD';
  @override
  String get newHeadLabel => '새 HEAD';
  @override
  String get purgeVerifiedLabel => '제거 검증됨';
  @override
  String get purgeClean => '깨끗함';
  @override
  String get purgeTracesRemain => '흔적 남음';
  @override
  String get displacedWorktrees => '밀려난 작업 트리';
  @override
  String get undoSurgery => '수술 취소';
  @override
  String get rolledBack => '백업 ref로 롤백했습니다.';
  @override
  String get done => '완료';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$ko
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => '푸시 중…';
  @override
  String get forcePushAll => '전체 강제 푸시';
  @override
  String get confirmPush => '푸시 확인';
  @override
  String get cancel => '취소';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$ko extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get back => '뒤로';
  @override
  String get continueLabel => '계속';
  @override
  String get letsGo => '가보죠';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$ko
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get question => '당신에게 이건 무엇인가요?';
  @override
  String get questionEmphasis => '이건';
  @override
  String get iAmPrefix => '저는 ';
  @override
  String get iAmSuffix => ', 당신의 개인 Git 클라이언트입니다.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$ko
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '${name} 단장하기.';
  @override
  String get themesHeader => '테마';
  @override
  String get keybindingsHeader => '키 바인딩';
  @override
  String get previewBadge => '미리보기';
  @override
  String get useDefaults => '기본값 사용';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$ko extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '${name} 방향 잡기.';
  @override
  String get later => '나중에 할게요';
  @override
  late final _Translations$onboarding$repo$doors$ko doors =
      _Translations$onboarding$repo$doors$ko._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$ko cloneForm =
      _Translations$onboarding$repo$cloneForm$ko._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$ko pickers =
      _Translations$onboarding$repo$pickers$ko._(_root);
  @override
  late final _Translations$onboarding$repo$errors$ko errors =
      _Translations$onboarding$repo$errors$ko._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$ko
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$ko panels =
      _Translations$onboarding$preview$panels$ko._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$ko sidebar =
      _Translations$onboarding$preview$sidebar$ko._(_root);
  @override
  late final _Translations$onboarding$preview$changes$ko changes =
      _Translations$onboarding$preview$changes$ko._(_root);
  @override
  late final _Translations$onboarding$preview$history$ko history =
      _Translations$onboarding$preview$history$ko._(_root);
  @override
  late final _Translations$onboarding$preview$branches$ko branches =
      _Translations$onboarding$preview$branches$ko._(_root);
  @override
  late final _Translations$onboarding$preview$diff$ko diff =
      _Translations$onboarding$preview$diff$ko._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$ko extends Translations$orrery$header$en {
  _Translations$orrery$header$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => '스크럽';
  @override
  String get modeCompare => '비교';
  @override
  String get lodModules => '모듈';
  @override
  String get lodFiles => '파일';
}

// Path: orrery.status
class _Translations$orrery$status$ko extends Translations$orrery$status$en {
  _Translations$orrery$status$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loading => '히스토리를 따라 Manifold를 추적하는 중…';
  @override
  String get loadError => '이 저장소의 히스토리를 읽을 수 없습니다.';
  @override
  String get notEnoughHistory => '궤적을 그리기에 아직 히스토리가 충분하지 않습니다.';
  @override
  String get notEnoughHistoryDetail => 'Orrery가 도표를 그리려면 커밋이 몇 개 필요합니다.';
}

// Path: orrery.legend
class _Translations$orrery$legend$ko extends Translations$orrery$legend$en {
  _Translations$orrery$legend$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get central => '중심';
  @override
  String get peripheral => '주변';
}

// Path: orrery.node
class _Translations$orrery$node$ko extends Translations$orrery$node$en {
  _Translations$orrery$node$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get module => '모듈';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · 파일 ${n}개';
  @override
  String fileFallback({required Object id}) => '파일 #${id}';
  @override
  String nodeFallback({required Object id}) => '노드 #${id}';
  @override
  String get rootModule => '(루트)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$ko
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => '기원';
  @override
  String get now => '지금';
  @override
  String get reorganized => '재편됨';
  @override
  String becameArchetype({required Object archetype}) => '${archetype} 형태로';
  @override
  String get snapshot => '스냅샷';
}

// Path: orrery.structure
class _Translations$orrery$structure$ko
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get forming => '형성 중…';
  @override
  String get canonical => '정준';
  @override
  String get connectivity => '연결성';
  @override
  String get rigidity => '강성';
  @override
  String get entropy => '엔트로피';
}

// Path: orrery.rail
class _Translations$orrery$rail$ko extends Translations$orrery$rail$en {
  _Translations$orrery$rail$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => '구조';
  @override
  String get fieldLabel => '필드';
  @override
  String get findingsLabel => '발견';
  @override
  String get selectedLabel => '선택됨';
  @override
  String get noFindings => '이 히스토리에서 구조적 이벤트가 감지되지 않았습니다.';
}

// Path: orrery.selection
class _Translations$orrery$selection$ko
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => '히스토리의 이 시점에는 존재하지 않습니다.';
  @override
  String get roleCentral => '결합 중심 — 여기서의 변경이 시스템 전반에 파문을 일으킵니다.';
  @override
  String get rolePeripheral => '주변 — 느슨하게 결합되어 대체로 독립적으로 변경됩니다.';
  @override
  String get roleMid => '중간 구조 — 적당히 결합됨.';
  @override
  String get driftOutward => ' 바깥으로 표류 중 — 결합 해제.';
  @override
  String get driftInward => ' 안쪽으로 표류 중 — 통합.';
  @override
  String get driftHolding => ' 위치를 유지 중.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$ko
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hub => '허브';
  @override
  String get driftOut => '바깥 표류';
  @override
  String get driftIn => '안쪽 표류';
  @override
  String get tangle => '얽힘';
  @override
  String get clarify => '명료화';
  @override
  String get regime => '재편';
  @override
  String get thrash => '스래싱';
  @override
  String get reshuffle => '재배치';
  @override
  String get forecast => '예측';
}

// Path: orrery.findings
class _Translations$orrery$findings$ko extends Translations$orrery$findings$en {
  _Translations$orrery$findings$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      '연결성이 계속 떨어져 최저치에 근접했습니다 — 이대로 유지되면 코드베이스는 느슨하게 결합된 두 조각으로 갈라지는 방향으로 향합니다. 그게 의도인지 지금 결정하십시오.';
  @override
  String get forecastConsolidate =>
      '연결성이 정점을 향해 계속 오르고 있습니다 — 이대로 유지되면 코드베이스는 단단히 결합된 하나의 덩어리로 통합됩니다. 모놀리스로 굳어지는지 주시하십시오.';
  @override
  String thrash({required Object name}) =>
      '${name} — 이리저리 계속 재편됩니다. 구조적 변동은 많지만 순 이동은 적습니다. 결합을 안정시키거나 건드리지 마십시오.';
  @override
  String get reshuffle =>
      '이 커밋은 일상적으로 보였지만 어떤 파일이 중심인지를 조용히 바꿔놓았습니다 — 전체 형태는 유지된 채 그 아래에서 구조가 재배치됐습니다. 주의 깊게 검토하십시오.';
  @override
  String hub({required Object name}) =>
      '${name} — 구조적 핵심에 자리합니다. 시스템이 이를 중심으로 재편됩니다. 여기서의 변경은 영향 반경이 크다고 여기십시오.';
  @override
  String driftOut({required Object name}) =>
      '${name} — 핵심에서 가장자리로 표류했습니다. 시스템에서 결합이 풀리고 있습니다. 은퇴 중이거나, 조용히 썩어가는 중입니다.';
  @override
  String driftIn({required Object name}) =>
      '${name} — 핵심 쪽으로 이동했습니다. 하중을 견디는 요소가 되어가고 있습니다. 더 많은 것이 의존하기 전에 충분히 테스트되었는지 확인하십시오.';
  @override
  String get regime =>
      '코드베이스가 여기서 급격히 재편됐습니다 — 연결성이 급증했습니다. 무엇이 갈라졌거나 머지됐는지 검토하십시오.';
  @override
  String get tangleTrend =>
      '히스토리 전반에 걸쳐 코드베이스가 더 얽힌 구조로 향하는 추세입니다 — 연결성이 점점 촘촘해지고 모듈성이 떨어집니다.';
  @override
  String get clarifyTrend =>
      '히스토리 전반에 걸쳐 코드베이스가 더 깔끔한 구조로 향하는 추세입니다 — 더 명확한 모듈로 분리되고 있습니다.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$ko extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get core => '핵심';
  @override
  String get drift => '표류';
  @override
  String get trend => '추세';
  @override
  String get thrash => '스래싱';
}

// Path: orrery.compare
class _Translations$orrery$compare$ko extends Translations$orrery$compare$en {
  _Translations$orrery$compare$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => '변경';
  @override
  String get movers => '이동 요소';
  @override
  String get noMovers => '이 프레임들 사이에서 이동한 파일이 없습니다.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => '파일';
  @override
  String get deltaConnectivity => '연결성';
  @override
  String get deltaRigidity => '강성';
  @override
  String get deltaEntropy => '엔트로피';
  @override
  String get wayOutward => '바깥으로';
  @override
  String get wayInward => '안쪽으로';
  @override
  String get wayShifted => '이동됨';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$ko
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'ask: [질문]';
  @override
  String get nearHint => 'near: [파일]';
  @override
  String get whoHint => 'who: [파일]';
  @override
  String get logHint => 'log: [메시지]';
  @override
  String get runHint => 'run: [도구]';
  @override
  String askLabel({required Object name, required Object body}) =>
      '${name}에게 묻기: ${body}';
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
  }) => '${path} · 리뷰어 ${count}명 · ${touches}회 터치';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches}회 터치';
  @override
  String whoTouchesSubtitle({required Object path}) => '${path} · 기록된 리뷰어 없음';
}

// Path: palette.chips
class _Translations$palette$chips$ko extends Translations$palette$chips$en {
  _Translations$palette$chips$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => '근처';
  @override
  String get who => '누구';
  @override
  String get term => '터미널';
  @override
  String get gui => 'GUI';
  @override
  String get dev => '개발';
  @override
  String get debug => '디버그';
  @override
  String get alpha => '알파';
  @override
  String get hot => '핫';
  @override
  String get key => '키';
  @override
  String get web => '웹';
  @override
  String get sys => '시스템';
  @override
  String get clip => '클립';
  @override
  String get sync => '동기화';
  @override
  String get force => '강제';
  @override
  String get pr => 'PR';
  @override
  String get draft => '초안';
  @override
  String get undo => '실행취소';
  @override
  String get thm => '테마';
  @override
  String get ver => '버전';
  @override
  String get desk => 'Desk';
  @override
  String get det => '분리';
  @override
  String get main => '메인';
  @override
  String get head => 'HEAD';
  @override
  String get gone => '사라짐';
  @override
  String get remote => '원격';
  @override
  String get local => '로컬';
  @override
  String get an => '주석';
  @override
  String get lw => '경량';
}

// Path: palette.predictive
class _Translations$palette$predictive$ko
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% 모멘텀';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$ko
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count}회 터치 · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$ko
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => '스테이징 응집도: ${percent}%';
  @override
  String subtitle({required Object count}) => '파일 ${count}개';
}

// Path: palette.keystone
class _Translations$palette$keystone$ko
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · 키스톤 ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$ko extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => '${name}의 변경사항';
  @override
  String history({required Object name}) => '${name}의 히스토리';
  @override
  String branches({required Object name}) => '${name}의 브랜치';
  @override
  String terminal({required Object name}) => '${name}의 터미널';
  @override
  String generateCommit({required Object name}) => '커밋 생성 · ${name}';
  @override
  String reviewChanges({required Object name}) => '${name}의 변경 검토';
  @override
  String muse({required Object name}) => '${name}의 Muse';
}

// Path: palette.desks
class _Translations$palette$desks$ko extends Translations$palette$desks$en {
  _Translations$palette$desks$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => '메인 작업 트리';
  @override
  String get detached => '분리됨';
  @override
  String dirty({required Object count}) => '${count}개 변경됨';
}

// Path: palette.actions
class _Translations$palette$actions$ko extends Translations$palette$actions$en {
  _Translations$palette$actions$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => '브라우저에서 열기';
  @override
  String get terminal => '터미널';
  @override
  String get revealInFiles => '파일 탐색기에서 보기';
  @override
  String get copyPath => '경로 복사';
  @override
  String get copyBranch => '브랜치 복사';
}

// Path: palette.tools
class _Translations$palette$tools$ko extends Translations$palette$tools$en {
  _Translations$palette$tools$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => '${label} 실행';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$ko
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => '페치';
  @override
  String get pull => '풀';
  @override
  String pullBehind({required Object count}) => '${count} 뒤처짐';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => '푸시';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '커밋 ${n}개',
      );
  @override
  String pushCommitsUpstream({
    required Object upstream,
    required Object commits,
  }) => '${upstream}에 ${commits}';
  @override
  String get forcePush => '강제 푸시';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      '강제 푸시할 수 없음: ${branch}에 업스트림이 설정되지 않았습니다.';
  @override
  String get commit => '커밋';
  @override
  String get stageAll => '전체 스테이징';
  @override
  String get unstageAll => '전체 스테이징 해제';
  @override
  String get discardAll => '전체 버리기';
  @override
  String get createBranch => '브랜치 생성';
  @override
  String get deleteBranch => '브랜치 삭제';
  @override
  String get renameBranch => '브랜치 이름 변경';
  @override
  String get stash => '스태시';
  @override
  String get stashPop => '스태시 팝';
  @override
  String get stashApply => '스태시 적용';
  @override
  String get stashDrop => '스태시 버리기';
  @override
  String get createTag => '태그 생성';
  @override
  String get cherryPick => '체리픽';
  @override
  String get revert => '되돌리기';
  @override
  String get stashConflictMessage => '충돌과 함께 스태시가 적용됐습니다. 변경사항 페이지에서 해결하십시오.';
}

// Path: palette.pr
class _Translations$palette$pr$ko extends Translations$palette$pr$en {
  _Translations$palette$pr$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'PR 생성';
  @override
  String get merge => 'PR 머지';
  @override
  String get markReady => 'PR 준비 완료 표시';
}

// Path: palette.ai
class _Translations$palette$ai$ko extends Translations$palette$ai$en {
  _Translations$palette$ai$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => '커밋 생성';
  @override
  String get reviewChanges => '변경 검토';
  @override
  String get runMuse => 'Muse 실행';
  @override
  String debugRepo({required Object name}) => '${name} 디버그';
  @override
  String get describeSymptom => '증상 설명';
  @override
  String viewResult({required Object kind}) => '${kind} 보기';
  @override
  String get unseenResult => '확인 안 한 결과';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => '실행 중';
  @override
  String get kindCommitMessage => '커밋 메시지';
  @override
  String get kindCodeReview => '코드 리뷰';
  @override
  String get kindMuseResult => 'Muse 결과';
  @override
  String get kindPresentation => '프레젠테이션';
  @override
  String get kindDebugResult => '디버그 결과';
}

// Path: palette.undo
class _Translations$palette$undo$ko extends Translations$palette$undo$en {
  _Translations$palette$undo$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => '취소: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$ko
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get changes => '변경사항';
  @override
  String get history => '히스토리';
  @override
  String get branches => '브랜치';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => '설정';
  @override
  String get refresh => '새로고침';
}

// Path: palette.settings
class _Translations$palette$settings$ko
    extends Translations$palette$settings$en {
  _Translations$palette$settings$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => '모션 줄이기';
  @override
  String get animateLogoUnfocused => '포커스 해제 시 로고 애니메이션';
  @override
  String get instantBlameHover => '즉시 blame 호버';
  @override
  String get autoSelectChanges => '변경 자동 선택';
  @override
  String get fetchOnlineIssues => '온라인 이슈 가져오기';
  @override
  String get rememberWip => '작업 중인 내용 기억';
  @override
  String get hideAiFeatures => 'AI 기능 숨기기';
  @override
  String get crashReporting => '크래시 보고';
  @override
  String get aiReadOnly => 'AI 읽기 전용';
  @override
  String get stashCabinetExpanded => '스태시 캐비닛 펼침';
  @override
  String get fileSortInverted => '파일 정렬 반전';
}

// Path: palette.info
class _Translations$palette$info$ko extends Translations$palette$info$en {
  _Translations$palette$info$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$ko extends Translations$palette$debug$en {
  _Translations$palette$debug$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => '엔진 상태';
  @override
  String get engineStatusSubtitle => 'LogosGit 스펙트럴 엔진 진단';
  @override
  String get fileCoupling => '파일 결합';
  @override
  String get fileCouplingSubtitle => '스테이징된 파일의 가장 가까운 공동 변경 이웃';
  @override
  String get themeSpecimen => '테마 견본';
  @override
  String get themeSpecimenSubtitle => '모든 색상, 아이콘, 텍스트 계층, 지오메트리';
}

// Path: palette.dev
class _Translations$palette$dev$ko extends Translations$palette$dev$en {
  _Translations$palette$dev$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => '머지 편집기 테스트';
  @override
  String get testHistorySurgery => '히스토리 수술 테스트';
  @override
  String get back => '뒤로';
  @override
  String get cancel => '취소';
  @override
  String get buildingConflicts => '히스토리에서 테스트 충돌 생성 중…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$ko
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get label => '히스토리 수술';
  @override
  String get subtitle => '히스토리를 재작성하여 파일을 영구 제거';
}

// Path: palette.orrery
class _Translations$palette$orrery$ko extends Translations$palette$orrery$en {
  _Translations$palette$orrery$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle => 'Manifold를 통해 저장소의 구조적 히스토리를 스크럽';
}

// Path: palette.command
class _Translations$palette$command$ko extends Translations$palette$command$en {
  _Translations$palette$command$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} 완료';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} 실패: ${message}';
  @override
  String get copy => '복사';
}

// Path: palette.search
class _Translations$palette$search$ko extends Translations$palette$search$en {
  _Translations$palette$search$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => '전체 검색…';
  @override
  String get hintElevated => '확장 — 모든 동작';
  @override
  String get emptyTypeToSearch => '검색하려면 입력하십시오';
  @override
  String get emptyNoResults => '결과 없음';
}

// Path: palette.wick
class _Translations$palette$wick$ko extends Translations$palette$wick$en {
  _Translations$palette$wick$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => '결합됨';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$ko
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get current => '현재';
  @override
  String get staged => '스테이징됨';
  @override
  String get modified => '수정됨';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$ko
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$ko whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$ko._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$ko spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$ko._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$ko whereGoing =
      _Translations$releaseNotes$about$whereGoing$ko._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$ko
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license => 'GPL-3.0-or-later · WLCSL 커뮤니티 소스 연구 코어 · 보증 없음';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$ko
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${n}줄',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$ko
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${n}줄 (${bytes}).',
      );
  @override
  String roles({required Object parts}) => '역할 — ${parts}.';
  @override
  String showingNofM({required Object total, required Object active}) =>
      '구조적 중심성 순으로 정렬된 ${total}개 파일 중 ${active}개 표시 중.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$ko
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => '한눈에 보기';
  @override
  String get core => '핵심';
  @override
  String get gettingStarted => '시작하기';
  @override
  String get regions => '영역';
  @override
  String get shape => '형태';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$ko
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      '읽을 수 있는 텍스트 파일이 없는 저장소입니다${detail}.';
  @override
  String emptyBinary({required Object n}) => '바이너리 ${n}개';
  @override
  String emptyUnreadable({required Object n}) => '읽을 수 없는 파일 ${n}개';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '활성 파일 ${n}개로 이루어진 저장소입니다.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '활성 파일 ${n}개로 이루어진 저장소입니다 — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$ko
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => '모두 `${dir}` 아래에 있습니다.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '핵심 ${n}개',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '파일 ${n}개',
      );
  @override
  String connectsTo({required Object linked}) => '연결 대상: ${linked}.';
  @override
  String get filesLabel => '파일:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$ko
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get bulk => '촘촘히 얽힌 코드베이스: 대부분의 파일이 하나의 큰 공동 변경 이웃에 참여합니다.';
  @override
  String get crystalline => '격자 모양 코드베이스: 파일 전반에 균일하고 규칙적인 결합, 예측 가능한 국소 구조.';
  @override
  String get goe => '풍부하게 얽힌 코드베이스: 지배적인 등뼈 없이 결합이 파일 전반에 퍼져 있습니다.';
  @override
  String get modular =>
      '모듈형 코드베이스: 교차 결합이 제한된 여러 응집 영역. 한 영역의 작업이 다른 영역을 건드리는 일은 드뭅니다.';
  @override
  String get poisson => '느슨하게 결합된 코드베이스: 파일들이 대체로 독립적으로 진화하며, 이따금 공동 변경이 있습니다.';
  @override
  String get tree =>
      '나무 모양 코드베이스: 하나의 지배적인 등뼈와 그에 딸린 가지들. 변경은 보통 핵심에서 바깥으로 전파됩니다.';
}

// Path: settings.language
class _Translations$settings$language$ko
    extends Translations$settings$language$en {
  _Translations$settings$language$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '언어';
  @override
  String get summary =>
      '이 앱의 UI 언어입니다. Git 출력, 로그, 진단은 버그 보고서를 검색 가능하게 유지하기 위해 영어로 남습니다.';
  @override
  String get label => '표시 언어';
  @override
  String get systemDefault => '시스템 기본값';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'OS 언어를 따릅니다 (${resolved})';
  @override
  String get disclosureSource => '개발자가 작성한 원본 언어입니다.';
  @override
  String disclosureAi({required Object model}) =>
      '${model} 기계 번역입니다. 아직 사람이 검수하지 않았습니다. 수정 환영합니다.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => '${model} 기계 번역. ${percent}% 사람 검수됨.';
  @override
  String get disclosureHuman => '사람 번역, 커뮤니티가 관리합니다.';
  @override
  String reviewedBy({required Object names}) => '검수: ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$ko
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => '환경설정';
  @override
  String get shortcuts => '단축키';
  @override
  String get behaviour => '동작';
  @override
  String get aiProviders => 'AI 제공자';
  @override
  String get modelSlots => '모델 슬롯';
  @override
  String get tools => '도구';
  @override
  String get diagnostics => '진단';
  @override
  String get offenders => '문제 요소';
  @override
  String get release => '릴리스';
}

// Path: settings.errors
class _Translations$settings$errors$ko extends Translations$settings$errors$en {
  _Translations$settings$errors$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => '가드레일 프로필 저장에 실패했습니다.';
  @override
  String get saveRetentionPolicy => '보존 정책 저장에 실패했습니다.';
  @override
  String get saveUpdateChannel => '업데이트 채널 저장에 실패했습니다.';
  @override
  String get saveModelSelection => 'AI 모델 선택 저장에 실패했습니다.';
  @override
  String get saveModelAlias => '모델 별칭 저장에 실패했습니다.';
  @override
  String get saveCommitMessageModelSlot => '커밋 메시지 모델 슬롯 저장에 실패했습니다.';
  @override
  String get saveReviewModelSlot => '리뷰 모델 슬롯 저장에 실패했습니다.';
  @override
  String get saveCommitMessageCustomPrompt => '커밋 메시지 사용자 프롬프트 저장에 실패했습니다.';
  @override
  String get saveReviewGuide => '리뷰 가이드 저장에 실패했습니다.';
  @override
  String get saveMuseNotes => 'muse 노트 저장에 실패했습니다.';
  @override
  String get saveReviewDoubleCheck => '리뷰 이중 확인 모드 저장에 실패했습니다.';
  @override
  String get saveApiPiggybackCli => 'API 피기백 CLI 저장에 실패했습니다.';
  @override
  String get saveCliTimeout => 'CLI 타임아웃 저장에 실패했습니다.';
  @override
  String get stopAllCli => '실행 중인 CLI 세션을 중지할 수 없습니다.';
  @override
  String clearLocalData({required Object error}) => '로컬 데이터를 지울 수 없음: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$ko
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get editing => '편집 중';
  @override
  String get saving => '저장 중';
  @override
  String get saveFailed => '저장 실패';
}

// Path: settings.clearData
class _Translations$settings$clearData$ko
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => '로컬 데이터 지우기';
  @override
  String get clear => '지우기';
  @override
  String get confirmDiagnostics => '로컬 진단 샘플과 성능 측정값을 지우시겠습니까?';
  @override
  String get confirmAudit => '로컬 AI 감사 메타데이터 기록을 지우시겠습니까?';
  @override
  String get confirmAll => '모든 로컬 진단 샘플과 AI 감사 메타데이터 기록을 지우시겠습니까?';
  @override
  String get confirmWipeAll =>
      '최근 저장소 목록을 포함한 모든 로컬 앱 데이터를 지우고 종료하시겠습니까? 디스크의 실제 git 저장소는 건드리지 않습니다.';
  @override
  String get confirmReset =>
      '로컬 앱 데이터를 초기화하고 종료하시겠습니까?\n\n설정, 테마, 온보딩, AI 환경설정, 텔레메트리, engram 캐시가 지워집니다. 최근 저장소 목록은 유지됩니다.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$ko
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '느슨';
  @override
  String get balanced => '균형';
  @override
  String get strict => '엄격';
  @override
  String get paranoid => '편집증';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$ko
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '가드레일';
  @override
  String get summary => '전체 경험에 걸쳐 자동화가 얼마나 세심한지.';
}

// Path: settings.appearance
class _Translations$settings$appearance$ko
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '모양';
  @override
  String get summary => '전역 인터페이스 분위기와 무드.';
}

// Path: settings.retention
class _Translations$settings$retention$ko
    extends Translations$settings$retention$en {
  _Translations$settings$retention$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '로컬 데이터 보존';
  @override
  String get summaryDiagnostics => '진단 보존 정책.';
  @override
  String get summaryWithAudit => '진단 및 AI 감사 보존 정책.';
  @override
  String get unitDays => '일';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote => '진단, 성능 측정값, 메타데이터를 포함합니다.';
}

// Path: settings.navigation
class _Translations$settings$navigation$ko
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '탐색 및 다이내믹스';
  @override
  String get summaryShortcuts => '단축키와 인터페이스 동작.';
  @override
  String get summaryWithAi => '단축키, 인터페이스 동작, AI 라우팅.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$ko
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '행동 다이내믹스';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$ko
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get diag => '진단';
  @override
  String get audit => '감사';
  @override
  String get all => '전체';
  @override
  String get clearsHint => '<-- 지움';
}

// Path: settings.channels
class _Translations$settings$channels$ko
    extends Translations$settings$channels$en {
  _Translations$settings$channels$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get stable => '안정';
  @override
  String get beta => '베타';
  @override
  String get dev => '개발';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$ko
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => '최신';
  @override
  String updateAvailable({required Object version}) => '${version} 사용 가능';
  @override
  String get notConfigured => '업데이트 서버 없음';
  @override
  String notFound({required Object channel}) => '${channel} 릴리스 없음';
  @override
  String get unreachable => '도달 불가';
  @override
  String get badManifest => '잘못된 매니페스트';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$ko
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get label => '키 바인딩 프로필';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => '숫자형';
  @override
  String get porcelainDescription => '연속 키 단축키입니다 (G 다음 C, H, B…).';
  @override
  String get numericDescription => '숫자 한 키 단축키입니다 (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$ko
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'api 키';
  @override
  String get endpointHint => '엔드포인트';
  @override
  String get test => '테스트';
  @override
  String get hide => '숨기기';
  @override
  String get show => '표시';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$ko
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => '이동';
  @override
  String get staging => '스테이징';
  @override
  String get branchesPrs => '브랜치 & PR';
  @override
  String get modifiers => '수정자';
  @override
  String get changes => '변경사항';
  @override
  String get history => '히스토리';
  @override
  String get branches => '브랜치';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => '전환 (항상)';
  @override
  String get search => '검색';
  @override
  String get dismiss => '닫기';
  @override
  String get refresh => '새로고침';
  @override
  String get shortcuts => '단축키';
  @override
  String get nextChange => '다음 변경';
  @override
  String get prevChange => '이전 변경';
  @override
  String get toggleLine => '줄 토글';
  @override
  String get toggleHunk => '헝크 토글';
  @override
  String get toggleFile => '파일 토글';
  @override
  String get pinContext => '컨텍스트 고정';
  @override
  String get commit => '커밋';
  @override
  String get acceptHint => '힌트 수락';
  @override
  String get undo => '실행 취소';
  @override
  String get navigateRow => '이동';
  @override
  String get expand => '펼치기';
  @override
  String get checkout => '체크아웃';
  @override
  String get approve => '승인';
  @override
  String get requestChanges => '변경 요청';
  @override
  String get selectRange => '범위 선택';
  @override
  String get extendedMenu => '확장 메뉴';
}

// Path: settings.toggles
class _Translations$settings$toggles$ko
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'AI 읽기 전용 모드';
  @override
  String get aiReadOnlyDescription => 'AI가 변경을 자동으로 쓰거나 스테이징하는 것을 막습니다.';
  @override
  String get logoMotionLabel => '탭 벗어날 때 로고 애니메이션';
  @override
  String get logoMotionDescriptionEnabled => '효율적으로 설계됐으니, 마음 상하게 하지 마세요';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => '작업 중인 내용 기억';
  @override
  String get rememberWipDescription => '세션 간에 커밋 초안과 파일 선택을 유지합니다.';
  @override
  String get stashCabinetLabel => '스태시 캐비닛을 펼친 채로 시작';
  @override
  String get stashCabinetDescription => '저장소에 선반이 있을 때 서랍을 기본으로 열어 둡니다.';
  @override
  String get instantBlameLabel => '즉시 blame 호버';
  @override
  String get instantBlameDescription =>
      'diff 줄에 blame 정보가 나타나기 전 180ms 지연을 건너뜁니다.';
  @override
  String get autoSelectLabel => '새 변경 자동 선택';
  @override
  String get autoSelectDescription => '새로 추적되거나 변경된 파일이 커밋 선택에 자동으로 추가됩니다.';
  @override
  String get changeIdLabel => 'change-id 헤더 기록';
  @override
  String get changeIdDescription =>
      '새 커밋에 change-id 식별 헤더를 추가합니다 (Jujutsu, GitButler, Gerrit 규약). 각 커밋은 생성 직후 한 번 다시 작성됩니다.';
  @override
  String get fetchIssuesLabel => '브랜치 로드 시 온라인 이슈 가져오기';
  @override
  String get fetchIssuesDescription =>
      '브랜치 페이지가 열릴 때 git 제공자에서 PR과 이슈 세부 정보를 백그라운드로 가져옵니다.';
  @override
  String get hateAiLabel => 'AI가 싫어요';
  @override
  String get hateAiDescription =>
      'LLM 기반 기능을 모두 추방합니다. Logos는 그저 스펙트럴 수학이므로 계속 작동합니다.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$ko
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff diff-능력';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$ko
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => '제공자 불러오는 중…';
  @override
  String get refreshingProviders => '제공자 진단 새로고침 중…';
  @override
  String get routeDescription => '구성의 이름을 바꾸고 감지된 제공자 모델로 라우팅합니다.';
  @override
  String get loadingCategories => '모델 카테고리 불러오는 중…';
  @override
  String get noOptions => '아직 사용 가능한 모델 옵션이 없습니다. 먼저 호환되는 로컬 AI CLI를 감지하십시오.';
  @override
  String get slotsAppearWhenAvailable => '제공자 모델이 준비되면 모델 슬롯 설정이 여기에 나타납니다.';
  @override
  String get effortDefault => '기본값';
  @override
  String get noModelsForSlot => '이 슬롯에 감지된 모델이 없습니다.';
  @override
  String viaProvider({required Object provider}) => '${provider} 경유';
  @override
  String get customModelId => '사용자 모델 id';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$ko
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) => '일치하는 모델 없음: "${query}"';
  @override
  String get noModels => '사용 가능한 모델 없음';
  @override
  String get filterHint => '모델 필터…';
  @override
  String get warming => '예열 중…';
  @override
  String get detailsUnavailable => '세부 정보 없음';
  @override
  String get free => '무료';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$ko
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      '구조, 목소리, 커버리지 설정을 사용해 스테이징된 변경으로 커밋 메시지 초안을 작성합니다.';
  @override
  String get reviewDescription => '커밋하기 전에 현재 커밋 범위를 검토합니다.';
  @override
  String get museDescription => '브레인스토밍한 뒤 diff의 나아갈 방향을 종합하는 3단계 오라클.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$ko
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => '스타일 가이드';
  @override
  String get styleGuideHint => '선택 사항. 목소리 / 톤 / 금지. 위 형식이 골격을 처리합니다.';
}

// Path: settings.review
class _Translations$settings$review$ko extends Translations$settings$review$en {
  _Translations$settings$review$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => '리뷰에 함께 참고할 추가 메모';
  @override
  String get doubleCheckLabel => '이중 확인 리뷰';
  @override
  String get doubleCheckDescription => '최종 보고서를 보여주기 전에 두 번째 검증 단계를 실행합니다.';
}

// Path: settings.museHint
class _Translations$settings$museHint$ko
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loose => '부드럽게 이끌 방향이 있나요? 오늘은 무드가 너그럽습니다.';
  @override
  String get balanced => '무엇에 머무를지, 무엇을 건너뛸지. 솔직하되 가혹하지 않게.';
  @override
  String get strict => '기준. 금지. muse가 그냥 넘어가지 않을 것들.';
  @override
  String get paranoid => '렌즈를 조율하세요. Manifold가 어떤 주파수로 울려야 할까요?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$ko
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'muse를 위한 추가 메모';
}

// Path: settings.museStage
class _Translations$settings$museStage$ko
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => '브레인스톰';
  @override
  String get synthesize => '종합';
  @override
  String get slot => '슬롯';
  @override
  String get ideaCountLoose => '아이디어 ~12개';
  @override
  String get ideaCountBalanced => '아이디어 ~16개';
  @override
  String get ideaCountStrict => '아이디어 ~20개';
  @override
  String get ideaCountParanoid => '아이디어 ~24개';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  가드레일: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$ko
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get folder => '폴더';
  @override
  String get history => '히스토리';
  @override
  String get far => '멀리';
  @override
  String get near => '가까이';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$ko
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => '모듈 맵';
  @override
  String get repoCenters => '저장소 중심';
  @override
  String get neighbors => '이웃';
  @override
  String get toTouch => '다음에 건드릴 것';
  @override
  String get relevanceEngine => '관련성 엔진';
  @override
  String get description =>
      '구조, 히스토리, 리듬 전반에 걸쳐 파일이 어떻게 함께 움직이는지 읽어, Manifold가 무엇이 변경됐는지뿐 아니라 무엇이 중요한지 압니다.';
  @override
  String get withinReach => '닿을 수 있는 범위';
  @override
  String get gate => '게이트';
  @override
  String get nearest => '가장 가까움';
  @override
  String get warming => '예열 중';
  @override
  String get emptyOpenRepo => '렌즈가 살아 움직이는 걸\n보려면 저장소를 여십시오';
  @override
  String get emptyNoFiles => '닿는 범위에\n파일 없음 — 히스토리\n쪽으로 드래그';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$ko
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '변경 정렬 가이드';
  @override
  String get related => '함께 변경되는 파일이 함께 묶입니다. 관심사가 먼저, 맥락이 뒤따릅니다.';
  @override
  String get relatedInverted => '고립된 변경이 먼저 옵니다. 단단히 결합된 클러스터는 맨 아래로 가라앉습니다.';
  @override
  String get alphabetical => '경로 기준 단순 A → Z. 대소문자 구분 없음, 숫자는 자연스러운 순서.';
  @override
  String get alphabeticalInverted =>
      '경로 기준 단순 Z → A. 대소문자 구분 없음, 숫자는 자연스러운 순서.';
  @override
  String get impact => '가장 무거운 변경이 먼저 떠오릅니다. 변동량에 가중치를 두고, 바이너리와 새 파일은 부스트됩니다.';
  @override
  String get impactInverted => '가장 가벼운 변경이 먼저 떠오릅니다. 손쉬운 것이 위로, 무거운 작업은 기다립니다.';
  @override
  String get nearRelated => '관련순';
  @override
  String get alphabeticalShort => '알파벳순';
  @override
  String get byImpact => '영향순';
  @override
  String get flipped => '반전됨';
  @override
  String get peek => '엿보기';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$ko
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API 모델 사용';
  @override
  String get codexNotDetected => 'codex 감지 안 됨';
  @override
  String get dormant => '휴면';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$ko
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => '뷰어';
  @override
  String get media => '미디어';
  @override
  String get binary => '바이너리';
  @override
  String get hidden => '숨김';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$ko
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => '파괴적 동작';
  @override
  String get discards => '버리기';
  @override
  String get commits => '커밋';
  @override
  String get commitPush => '커밋 + 푸시';
  @override
  String get all => '전체';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$ko
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get label => '실행 취소 창';
  @override
  String get off => '끔';
  @override
  String descriptionInstant({required Object scope}) => '${scope} 즉시 확정.';
  @override
  String descriptionDelayed({required Object scope, required Object seconds}) =>
      '${scope} 확정 전 ${seconds}초.';
  @override
  String get cycleScopeTooltip => '클릭하여 범위 순환 · 슬라이더 위/아래 드래그도 가능';
  @override
  String get resetTooltip => '모든 동작을 기본 창으로 초기화';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$ko
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => '아마 괜찮으면 괜찮은 것';
  @override
  String get proper => '제대로 된 읽기, 로직, 통합, 패턴';
  @override
  String get lookAgain => '다시 보십시오. 뭔가 숨어 있을 수 있습니다';
  @override
  String get assumeWrong => '뭔가 잘못됐다고 가정하십시오. 찾아내십시오';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$ko
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh => '예: 고수준 로직과 주요 버그에 집중하십시오. 간결하고 관대하게.';
  @override
  String get surfaceBugs => '예: 잠재적 버그, 아키텍처 불일치, 엣지 케이스 실패를 드러내십시오.';
  @override
  String get scrutinize => '예: 최적화, 보안, 패턴 준수를 위해 모든 줄을 면밀히 살피십시오.';
  @override
  String get trustNothing =>
      '예: 아무것도 믿지 마십시오. 모든 부작용을 의심하십시오. 모든 줄을 잠재적 실패로 취급하십시오.';
  @override
  String get optional => '리뷰가 무엇에 신경 써야 하는지에 대한 선택적 지침.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$ko
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '형식';
  @override
  String get peek => '엿보기';
  @override
  String get structure => '구조';
  @override
  String get voice => '목소리';
  @override
  String get coverage => '커버리지';
  @override
  String get structureTitleBody => '제목 + 본문';
  @override
  String get structureTitleOnly => '제목만';
  @override
  String get structureFreeform => '자유 형식';
  @override
  String get voiceVerbLed => '행동 지향';
  @override
  String get voiceDescriptive => '서술형';
  @override
  String get voiceNarrative => '이야기형';
  @override
  String get coverageEssentials => '핵심만';
  @override
  String get coverageBalanced => '균형';
  @override
  String get coverageEverything => '전부';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$ko
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$ko title =
      _Translations$settings$commitPreview$title$ko._(_root);
  @override
  late final _Translations$settings$commitPreview$base$ko base =
      _Translations$settings$commitPreview$base$ko._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$ko
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$ko._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$ko
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$ko._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$ko
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '외부 도구';
  @override
  String get summary =>
      '사이드바에서 프로젝트를 우클릭하면 이 도구들 중 하나로 엽니다. 인자는 프로젝트 폴더에 {path}를 사용합니다.';
  @override
  String get detecting => '설치된 도구 감지 중…';
  @override
  String get allPresetsAdded =>
      '알려진 프리셋은 이미 모두 추가됐습니다. 더 추가하려면 “+ Custom”을 사용하십시오.';
  @override
  String get noToolsConfigured => '아직 구성된 도구가 없습니다. 위에서 하나 추가하십시오.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => '편집기';
  @override
  String get categoryExplore => '탐색';
  @override
  String get categoryOps => '운영';
  @override
  String get categoryGitOps => 'git 운영';
  @override
  String get nameHint => '이름';
  @override
  String get commandHint => '명령';
  @override
  String get test => '테스트';
  @override
  String get removeTool => '도구 제거';
  @override
  String get modeTerminal => '터미널';
  @override
  String get modeDetached => '분리됨';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$ko
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '이번 달 ${used}${limit}';
}

// Path: settings.gitea
class _Translations$settings$gitea$ko extends Translations$settings$gitea$en {
  _Translations$settings$gitea$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gitea 토큰';
  @override
  String get hostHint => '호스트';
  @override
  String get tokenHint => '토큰';
  @override
  String get save => '저장';
}

// Path: settings.wick
class _Translations$settings$wick$ko extends Translations$settings$wick$en {
  _Translations$settings$wick$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'wick 실행 파일 선택';
  @override
  String get connected => 'wick · 연결됨';
  @override
  String get pathToExecutable => 'wick · 실행 파일 경로';
  @override
  String get off => '끔';
  @override
  String get disableHint => 'wick 통합 끄기';
  @override
  String get enableHint => 'wick 통합 켜기';
}

// Path: settings.integrations
class _Translations$settings$integrations$ko
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& 통합';
  @override
  String get alpha => '알파';
  @override
  String get planned => '예정';
  @override
  String get lspComingSoon => 'lsp · 곧 제공';
  @override
  String get alphaMathConnected => 'alpha-math · 연결됨';
  @override
  String get alphaMathComingSoon => 'alpha-math · 곧 제공';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$ko
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get label => '모션 줄이기';
  @override
  String get subtitleStill => '고요하게… 얼음처럼?';
  @override
  String get subtitleFlow => '물처럼 흐르게.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$ko
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => '초기화 & 종료';
  @override
  String get keepRepos => '저장소 유지';
  @override
  String get wipeAll => '전체 삭제';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$ko
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => '명령 진단';
  @override
  String get networkFlowTelemetry => '네트워크 플로 텔레메트리';
  @override
  String get clearSamples => '샘플 지우기';
  @override
  String get clearMetrics => '지표 지우기';
  @override
  String get clearTimings => '측정값 지우기';
  @override
  String get recalibrate => '재보정';
  @override
  String get ok => '정상';
  @override
  String get noCommandTimings => '아직 캡처된 명령 측정값이 없습니다. 일반 동작을 실행하여 진단을 채우십시오.';
  @override
  String get noBackendSamples =>
      '아직 캡처된 백엔드 명령 샘플이 없습니다. git과 설정 동작을 실행하여 이 로그를 채우십시오.';
  @override
  String get noDiffSessions =>
      '아직 캡처된 diff 렌더 세션이 없습니다. 파일 diff를 열고 스크롤하여 이 패널을 채우십시오.';
  @override
  String get noUiSessions =>
      '아직 캡처된 UI 측정 세션이 없습니다. 패널을 열고 경로를 이동하여 이 패널을 채우십시오.';
  @override
  String get recentOperations => '최근 작업';
  @override
  String get recentBackendOperations => '최근 백엔드 작업';
  @override
  String get recentDiffSessions => '최근 diff 세션';
  @override
  String get recentUiTimings => '최근 UI 측정값';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '고유 명령 ${n}개',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '범위 지정 명령 ${n}개',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '계측 이벤트 ${n}개',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | 잰크 ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => ['명령', 'p50', '신뢰도', '범위'];
  @override
  List<String> get headersBackend => ['범위', 'p50', 'p95', '실패'];
  @override
  List<String> get headersDiff => ['렌더러', '첫 페인트', '프레임 p95', '래스터 p95', '잰크'];
  @override
  List<String> get headersUi => ['이벤트', 'p50', '실패', '범위'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$ko
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '샘플 ${n}개',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '명령 ${n}개',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '세션 ${n}개',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '이벤트 ${n}개',
      );
  @override
  String stability({required Object pct}) => '${pct}% 안정성';
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
class _Translations$settings$flowEngine$ko
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => '실행 흐름';
  @override
  String get description => '코드 위에서 진동자를 시뮬레이션합니다. 취약한 실행 경로가 버그로 굳기 전에 드러냅니다.';
  @override
  String get idle => '유휴';
  @override
  String get emptyOpenRepo => '흐름 분석을 보려면\n저장소를 여십시오';
  @override
  String get scanning => '스캔 중';
  @override
  String get analysing => '렌즈 안의\n파일 분석 중…';
  @override
  String get fragility => '취약성';
  @override
  String get findings => '발견';
  @override
  String get gap => '간격';
  @override
  String get clean => '깨끗함';
  @override
  String get severity => '심각도';
  @override
  String get critical => '심각';
  @override
  String get warn => '경고';
  @override
  String get info => '정보';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$ko
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get spark => '영감의 불꽃 · 바로 다음 단계';
  @override
  String get current => '물속의 흐름 · 현재형 확장';
  @override
  String get horizon => '지평선 너머 · 뻗어 나가는 방향';
  @override
  String get fever => '열병 꿈에서 깨어나 · 도발';
  @override
  String get echo => '협곡을 가로지르는 메아리 · 다른 곳의 유사물';
  @override
  String get vertigo => '절벽 끝의 현기증 · 인접한 위험';
  @override
  String get ghost => '지난 것의 유령 · 역사적 맥락';
  @override
  String get mirror => '고요한 물 위의 거울 · 반전';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$ko
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'CLI 피기백';
  @override
  String get clearCacheLabel => '캐시 지우기';
  @override
  String get clearCacheTooltip => '캐시된 모델을 지우고 다시 탐지합니다. 제공자가 뺀 것들을 정리합니다.';
  @override
  String get refreshLabel => '제공자 새로고침';
  @override
  String get refreshTooltip => '지금 모든 제공자를 다시 탐지합니다.';
  @override
  String get body => '인터페이스 메시지를 로컬 제공자 바이너리로 직접 연결합니다.';
  @override
  String get cliTimeoutLabel => '실행당 타임아웃';
  @override
  String get cliTimeoutUnitMinutes => '분';
  @override
  String get cliTimeoutUnitMinute => '분';
  @override
  String get forceStopLabel => '모든 세션 중지';
  @override
  String get forceStopTooltip => '진행 중인 모든 CLI 실행을 강제 종료합니다.';
  @override
  String get forceStopConfirmTitle => '실행 중인 CLI 세션을 중지할까요?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      '진행 중인 CLI 실행 ${count}개를 강제 종료합니다. 출력이 사라집니다.';
  @override
  String get forceStopConfirmAction => '모두 중지';
  @override
  String get forceStopNoneRunning => '실행 중인 CLI 세션 없음';
  @override
  String get forceStopRecordError => '중지됨 — CLI 세션이 강제 종료되었습니다.';
}

// Path: settings.header
class _Translations$settings$header$ko extends Translations$settings$header$en {
  _Translations$settings$header$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '작업 공간 환경설정';
  @override
  String get subtitle => '전체 작업 공간의 전역 미학, 인터페이스 다이내믹스, 핵심 운영 안전장치를 구성합니다.';
  @override
  String get releaseNotesTooltip => '릴리스 노트';
  @override
  String get replayOnboardingTooltip => '온보딩 다시 보기';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$ko
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '성능 진단';
  @override
  String get copyTrace => '추적 복사';
  @override
  String get offenderRanking => '문제 요소 순위';
  @override
  String get offenderRankingSubtitle => '스트림 전반의 지연 유발 요인.';
  @override
  String get noOffenders => '아직 문제 요소 순위가 없습니다. 진단 활동을 캡처하여 이 목록을 채우십시오.';
}

// Path: settings.release
class _Translations$settings$release$ko
    extends Translations$settings$release$en {
  _Translations$settings$release$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '릴리스 배포';
  @override
  String get summary => '업데이트 관련 설정.';
  @override
  String get deploymentChannel => '배포 채널';
  @override
  String get captureCrashDiagnostics => '크래시 진단 캡처';
  @override
  String get comingSoon => '곧 제공.';
  @override
  String get checking => '확인 중…';
  @override
  String get pollForUpdates => '업데이트 확인';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$ko
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => '감지 중…';
  @override
  String get ready => '준비됨';
  @override
  String get notDetected => '감지 안 됨';
  @override
  String configured({required Object count}) => '${count}개 구성됨';
  @override
  String get notConfigured => '구성 안 됨';
  @override
  String get cliManaged => 'CLI 관리';
  @override
  String get connected => '연결됨';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '모델 ${n}개',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '제공자 ${n}개',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$ko
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get am => '오전';
  @override
  String get pm => '오후';
}

// Path: settings.offenders
class _Translations$settings$offenders$ko
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => '명령';
  @override
  String get diffStream => 'Diff 렌더';
  @override
  String get uiStream => 'UI 측정';
  @override
  String rendererName({required Object mode}) => '${mode} 렌더러';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% 실패';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% 잰크 | ${frame}ms 프레임 p95';
  @override
  String inStream({required Object stream}) => '${stream} 내';
}

// Path: sync.actions
class _Translations$sync$actions$ko extends Translations$sync$actions$en {
  _Translations$sync$actions$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => '동기화';
  @override
  String get syncOpenRepoDetail => '푸시와 풀 작업을 관리하려면 저장소를 여십시오.';
  @override
  String get detachedHeadLabel => '분리된 HEAD';
  @override
  String get detachedHeadDetail => '푸시나 풀 전에 브랜치를 체크아웃하십시오.';
  @override
  String get publishBranchLabel => '브랜치 게시';
  @override
  String publishBranchDetail({required Object branch}) =>
      '${branch} 푸시 후 업스트림 추적 브랜치를 설정합니다.';
  @override
  String get publishButtonLabel => '게시';
  @override
  String get syncBranchLabel => '브랜치 동기화';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => '리베이스로 ${behindCount} 풀한 뒤 ${aheadCount} 푸시합니다.';
  @override
  String get syncBranchButtonLabel => '풀(리베이스) 후 푸시';
  @override
  String get pushBranchLabel => '브랜치 푸시';
  @override
  String pushBranchDetail({required Object upstream, required Object count}) =>
      '${upstream}에 ${count} 푸시합니다.';
  @override
  String get pushBranchButtonLabel => '커밋 푸시';
  @override
  String get pullUpdatesLabel => '업데이트 풀';
  @override
  String pullUpdatesDetail({required Object upstream, required Object count}) =>
      '${upstream}에서 ${count} 풀합니다.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      '${upstream}에서 페치하고 업스트림 상태를 새로고침합니다.';
}

// Path: sync.panel
class _Translations$sync$panel$ko extends Translations$sync$panel$en {
  _Translations$sync$panel$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => '원격 상태 불러오는 중';
  @override
  String get loadingMessage => '브랜치 추적 정보를 확인하는 중.';
  @override
  String get remoteStatusUnavailable => '원격 상태를 사용할 수 없음';
  @override
  String get noUpstream => '업스트림 없음';
  @override
  String get aheadLabel => '앞섬';
  @override
  String get behindLabel => '뒤처짐';
  @override
  String get treeLabel => '트리';
  @override
  String get runningSync => '동기화 실행 중…';
  @override
  String get fetching => '페치 중…';
  @override
  String get fetchOnly => '페치만';
  @override
  String get syncFailed => '동기화 실패';
  @override
  String get forcePushRecoveryLabel => '강제 푸시(리스 사용)';
  @override
  String get conflictsToResolveTitle => '해결할 충돌';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} 해결 필요: ${list}';
  @override
  String get resolveConflicts => '충돌 해결';
  @override
  String get workingEllipsis => '작업 중…';
  @override
  String lastActivity({required Object operation}) => '마지막 활동: ${operation}';
  @override
  String get noOutput => '출력 없음.';
  @override
  String resolvedConflicts({required Object count}) => '${count} 해결됨.';
  @override
  String get cancelledUnchanged => '취소됨, 작업 트리 변경 없음.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) => '${count}에 커밋되지 않은 변경이 있습니다. 리베이스 동기화하려면 먼저 커밋하십시오 (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      '강제 푸시할 수 없음: "${branch}"에 업스트림이 구성되어 있지 않습니다.';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$ko extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => '강제 푸시(리스 사용)?';
  @override
  String target({required Object remote, required Object branch}) =>
      '대상: ${remote}/${branch}';
  @override
  String get warning =>
      '원격 브랜치를 로컬 히스토리로 덮어씁니다. 리스 사용 시 마지막 페치 이후 누군가 원격에 푸시했다면 중단되지만, 이미 페치한 변경은 여전히 덮어써집니다. 브랜치를 갈라지게 한 리베이스나 amend를 의도한 경우에만 사용하십시오.';
  @override
  String get confirmButton => '강제 푸시';
}

// Path: xray.board
class _Translations$xray$board$ko extends Translations$xray$board$en {
  _Translations$xray$board$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => '다른 모듈과 함께 움직임';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '리뷰어 ${n}명',
      );
  @override
  String get territory => '영역';
  @override
  String get unreviewed => '미리뷰';
}

// Path: xray.cadence
class _Translations$xray$cadence$ko extends Translations$xray$cadence$en {
  _Translations$xray$cadence$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '커밋 ${sum}개 · ${days}일\n${lines}';
  @override
  String burstTooltipSingle({required Object label, required Object n}) =>
      '${label}에 커밋 ${n}개';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      '${n}일 공백 · ${label}';
  @override
  String reflogTooltip({required Object label, required Object n}) =>
      '${label}에 reflog 이벤트 ${n}개';
}

// Path: xray.cards
class _Translations$xray$cards$ko extends Translations$xray$cards$en {
  _Translations$xray$cards$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$ko branchModel =
      _Translations$xray$cards$branchModel$ko._(_root);
  @override
  late final _Translations$xray$cards$bursty$ko bursty =
      _Translations$xray$cards$bursty$ko._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$ko hiddenRefs =
      _Translations$xray$cards$hiddenRefs$ko._(_root);
  @override
  late final _Translations$xray$cards$keystone$ko keystone =
      _Translations$xray$cards$keystone$ko._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$ko machineHistory =
      _Translations$xray$cards$machineHistory$ko._(_root);
  @override
  late final _Translations$xray$cards$migration$ko migration =
      _Translations$xray$cards$migration$ko._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$ko narrowHotspot =
      _Translations$xray$cards$narrowHotspot$ko._(_root);
  @override
  late final _Translations$xray$cards$noTags$ko noTags =
      _Translations$xray$cards$noTags$ko._(_root);
  @override
  late final _Translations$xray$cards$reflog$ko reflog =
      _Translations$xray$cards$reflog$ko._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$ko singleOwner =
      _Translations$xray$cards$singleOwner$ko._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$ko extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get branches => '브랜치';
  @override
  String get bursty => '폭발적';
  @override
  String get hiddenRefs => '숨겨진 ref';
  @override
  String get machineHeavy => '머신 과다';
  @override
  String get migration => '마이그레이션';
  @override
  String get narrowHotspot => '좁은 핫스폿';
  @override
  String get noTags => '태그 없음';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => '단일 소유자';
}

// Path: xray.grain
class _Translations$xray$grain$ko extends Translations$xray$grain$en {
  _Translations$xray$grain$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => '가장 거침 — 최상위 모듈';
  @override
  String get finest => '가장 미세한 결';
  @override
  String get mid => '중간 결';
  @override
  String get oneCharacteristic => '하나의 특징적 스케일';
}

// Path: xray.header
class _Translations$xray$header$ko extends Translations$xray$header$en {
  _Translations$xray$header$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => '더러움';
  @override
  String get machineChip => '머신';
  @override
  String get refresh => '새로고침';
  @override
  String get refreshing => '새로고침 중…';
  @override
  String get title => '저장소 X-Ray';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$ko extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => '클러스터 동료';
  @override
  String get coChangers => '공동 변경자';
  @override
  String get keystone => '키스톤';
  @override
  String keystoneScore({required Object score}) => '키스톤  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$ko extends Translations$xray$inspector$en {
  _Translations$xray$inspector$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => '브랜치';
  @override
  String commitsHumanMachine({required Object n}) => '사람 · 머신 ${n}개';
  @override
  String get commitsLabel => '커밋';
  @override
  String get confidenceLabel => '신뢰도';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => '엔진';
  @override
  String get gradientLabel => '그래디언트';
  @override
  String get harmonicLabel => '하모닉';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => '숨겨진 ref';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '머지 ${n}개',
      );
  @override
  String get noTags => '태그 없음';
  @override
  String get notesLabel => '노트';
  @override
  String get openCommit => '커밋 열기';
  @override
  String get pathLabel => '경로';
  @override
  String remoteCount({required Object n}) => '원격 ${n}개';
  @override
  String get renamesLabel => '이름 변경';
  @override
  String scannedAt({required Object time}) => '${time}에 스캔됨';
  @override
  String selectedCount({required Object n}) => '${n}개 선택됨';
  @override
  String get shapeLinear => '선형';
  @override
  String get shapeMergeHeavy => '머지 과다';
  @override
  String get shapeMostlyLinear => '대체로 선형';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '스태시 ${n}개',
      );
  @override
  String get stressLabel => 'stress';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '태그 ${n}개',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '작업 트리 ${n}개',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$ko
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage => 'Git 히스토리, ref, 리듬, 핫스폿을 조사하는 중.';
  @override
  String get buildingTitle => '저장소 X-Ray 생성 중';
  @override
  String get idleMessage => '현재 저장소를 조사하려면 패널을 다시 여십시오.';
  @override
  String get idleTitle => '저장소 X-Ray';
  @override
  String get unavailableTitle => '저장소 X-Ray를 사용할 수 없음';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$ko extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => '반감기 ${n}일';
}

// Path: xray.multi
class _Translations$xray$multi$ko extends Translations$xray$multi$en {
  _Translations$xray$multi$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '클러스터 ${n}개',
      );
  @override
  String clusterSingle({required Object id}) => '클러스터 ${id}';
  @override
  String couplingSuffix({required Object parts}) => '${parts} 결합';
  @override
  String externalCount({required Object n}) => '외부 ${n}개';
  @override
  String mutualCount({required Object n}) => '상호 ${n}개';
}

// Path: xray.recency
class _Translations$xray$recency$ko extends Translations$xray$recency$en {
  _Translations$xray$recency$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}일';
  @override
  String months({required Object n}) => '${n}개월';
  @override
  String get today => '오늘';
  @override
  String weeks({required Object n}) => '${n}주';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        one: '${n}년',
        other: '${n}년',
      );
}

// Path: xray.rings
class _Translations$xray$rings$ko extends Translations$xray$rings$en {
  _Translations$xray$rings$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => '하나의 혼합 구조';
  @override
  String get hintSelfSimilar => '자기 유사';
  @override
  String get oneBlendedBody => '하나의 혼합 구조 — 아직 분리 가능한 모듈 스케일이 드러나지 않습니다.';
  @override
  String get overHistory => '히스토리 전반';
  @override
  String get parts => '부분';
  @override
  String get readingHint => '구조 읽는 중…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '스케일 ${n}개',
      );
  @override
  String get scaleDissolved => '구조적 스케일 하나가 해체됨';
  @override
  String get scaleEmerged => '구조적 스케일 하나가 출현함';
  @override
  String get scaleSpectrum => '스케일 스펙트럼';
  @override
  String get selfSimilarBody =>
      '자기 유사 — 구조가 스케일 전반에 걸쳐 반복되며, 단일한 특징적 수준이 없습니다.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '히스토리에서 ${n}번 변화',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '구조적 변화 ${n}회',
      );
  @override
  String get title => '성장 나이테';
  @override
  String get unavailable => '사용 불가';
}

// Path: xray.stats
class _Translations$xray$stats$ko extends Translations$xray$stats$en {
  _Translations$xray$stats$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get alive => '활성';
  @override
  String get files => '파일';
  @override
  String get lastTouched => '마지막 터치';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '소유자',
      );
  @override
  String get touches => '터치';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$ko
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get current => '현재';
  @override
  String get legacy => '레거시';
  @override
  String get zone => '저장소 존';
}

// Path: xray.summary
class _Translations$xray$summary$ko extends Translations$xray$summary$en {
  _Translations$xray$summary$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) => '분석 실패: ${error}';
  @override
  String get analyze => '분석';
  @override
  String get copied => '요약을 클립보드에 복사했습니다.';
  @override
  String get directionHint => '방향';
  @override
  String get download => '다운로드';
  @override
  String get emptyState =>
      'Logos 분석을 실행하여 이 저장소의 구조와 영역을 매핑하십시오.\n(tw: slop rn)';
  @override
  String get exit => '종료';
  @override
  String get generating => '저장소를 읽고 특징을 클러스터링하는 중…';
  @override
  String get noModel => '구성된 AI 모델이 없습니다.';
  @override
  String get noModelConfigured => '구성된 AI 모델 없음';
  @override
  String presentWith({required Object label}) => '${label} 발표';
  @override
  String presentingWith({required Object label}) => '${label} 발표 중…';
  @override
  String get reanalyze => '재분석';
  @override
  String get saveDialogTitle => '저장소 요약 저장';
  @override
  String saveFailed({required Object error}) => '저장 실패: ${error}';
  @override
  String get savePresentationDialogTitle => '프레젠테이션 저장';
  @override
  String savedTo({required Object path}) => '${path}에 저장됨';
}

// Path: xray.tabs
class _Translations$xray$tabs$ko extends Translations$xray$tabs$en {
  _Translations$xray$tabs$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get map => '맵';
  @override
  String get signals => '신호';
  @override
  String get summary => '요약';
  @override
  String get time => '시간';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$ko extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => '연결성';
  @override
  String events({required Object n}) => '이벤트 ${n}개';
  @override
  String get openInOrrery => 'Orrery에서 열기';
  @override
  String get readingHint => '히스토리 읽는 중…';
  @override
  String snapshots({required Object n}) => '스냅샷 ${n}개';
  @override
  String get steady => '안정 — 이 구간에 구조적 이벤트 없음.';
  @override
  String get title => '구조적 궤적';
}

// Path: xray.verdict
class _Translations$xray$verdict$ko extends Translations$xray$verdict$en {
  _Translations$xray$verdict$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% 정준';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% 정준 · ${decisive}% 결정적';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$ko
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get manual => '수동';
  @override
  String get safe => '안전';
  @override
  String get guided => '안내';
  @override
  String get assisted => '보조';
  @override
  String get full => '전체';
  @override
  String label({required Object label}) => '신뢰: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$ko
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get accept => '수락';
  @override
  String get other => '다른 쪽';
  @override
  String get both => '둘 다';
  @override
  String get navigate => '이동';
  @override
  String get jumpNext => '다음으로 이동';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$ko
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get merge => '머지';
  @override
  String get cherryPick => '체리픽';
  @override
  String get revert => '되돌리기';
  @override
  String get resolve => '해결';
  @override
  String get switchOp => '전환';
  @override
  String get pull => '풀';
  @override
  String get rebase => '리베이스';
  @override
  String rebaseOnto({required Object base, required Object branch}) =>
      '${base} 위로 ${branch} 리베이스';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$ko
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane => '근처에 강한 소유자 한 명이 있는 최근 움직임.';
  @override
  String get activeSeam => '근처 여러 손에서 온 최근 움직임.';
  @override
  String get stableOwnerLane => '지배적 소유자 한 명이 있는 오래된 레인.';
  @override
  String get sharedLongLivedSeam => '시간이 지나며 쌓인 공유 이음새.';
  @override
  String get sharedLane => '단일 지배 소유자가 없는 공유 레인.';
  @override
  String get resolving => '이 줄 주변의 히스토리가 아직 정리되는 중입니다.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$ko
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get hot => '뜨거움';
  @override
  String get novel => '새로움';
  @override
  String get contested => '다툼';
  @override
  String get spreading => '확산';
  @override
  String get stable => '안정';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$ko
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => '${concept}에 자리함';
  @override
  String get sitsInLocalSeam => '로컬 이음새에 위치';
  @override
  String workedMostlyBy({required Object owner}) => '주로 근처 ${owner} 담당';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '다른 지점 ${n}곳에서 메아리침',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      '다음으로 ${path} 살펴보기${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$ko
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get tight => '꽉 맞음';
  @override
  String get close => '가깝게 맞음';
  @override
  String get loose => '느슨하게 맞음';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$ko
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => '근처 뒷받침 · ${label}';
  @override
  String localizedMove({required Object label}) => '국소적 이동 · ${label}';
  @override
  String surprisingMove({required Object label}) => '예상 밖 이동 · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$ko
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => '안정적 구조';
  @override
  String get conflictingSignals => '상충하는 신호';
  @override
  String get novelShape => '새로운 형태';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$ko
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => '테스트 미러';
  @override
  String get semanticHistorySibling => '의미 + 히스토리 형제';
  @override
  String get recentCoChange => '최근 공동 변경';
  @override
  String get semanticSibling => '의미 형제';
  @override
  String get relatedStructure => '관련 구조';
  @override
  String get tightlyBound => '단단히 묶임';
  @override
  String get orbiting => '공전 중';
  @override
  String get weaklyCoupled => '약하게 결합';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$ko
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => '히스토리 자취';
  @override
  String get testMirrorLane => '테스트 미러 레인';
  @override
  String get structuralLane => '구조 레인';
  @override
  String get semanticNeighbourhood => '의미 이웃';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$ko
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => '높은 중요도';
  @override
  String get importanceModerate => '보통 중요도';
  @override
  String get mostlyAdditions => '대부분 추가';
  @override
  String get mostlyDeletions => '대부분 삭제';
  @override
  String get tightlyCoupled => '단단히 결합된 파일';
  @override
  String get overlapsWorkingTree => '작업 트리와 겹침';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$ko
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$ko open =
      _Translations$onboarding$repo$doors$open$ko._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$ko clone =
      _Translations$onboarding$repo$doors$clone$ko._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$ko create =
      _Translations$onboarding$repo$doors$create$ko._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$ko
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'URL에서 클론';
  @override
  String get urlLabel => '저장소 URL';
  @override
  String get targetLabel => '대상 폴더';
  @override
  String get browse => '찾아보기…';
  @override
  String get clone => '클론';
  @override
  String get cloning => '클론 중…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$ko
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => '저장소 열기';
  @override
  String get createRepository => '저장소 생성';
  @override
  String get cloneTarget => '클론 대상';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$ko
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL과 대상 경로가 필요합니다.';
  @override
  String get createFailed => '저장소 생성에 실패했습니다.';
  @override
  String get cloneFailed => '저장소 클론에 실패했습니다.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$ko
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get xray => '저장소 X-Ray';
  @override
  String get settings => '설정';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$ko
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => '프로젝트';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$ko
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object total, required Object staged}) =>
      '${total}개 중 ${staged}개 파일';
  @override
  String stagedCount({required Object n}) => '${n}개 스테이징됨';
  @override
  String get commitMessageHint => '커밋 메시지…';
  @override
  String get commitAndPush => '커밋 & 푸시';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$ko
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get header => '히스토리';
  @override
  String get viewingLast => '최근 커밋 20개 보는 중';
  @override
  String get inFlight => '진행 중';
  @override
  String get you => '나';
  @override
  String get commit1 => '여우에게 삼키기 전에 냄새 맡는 법 가르치기';
  @override
  String get commit2 => '앰버: 밤새 향 붙잡아 두기';
  @override
  String get commit3 => '양배추 은퇴, 앰버 + 가시로 교체';
  @override
  String get commit4 => '가시가 문을 지킨다';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$ko
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => '브랜치';
  @override
  String get lensPRs => 'PR';
  @override
  String get absorbed => '흡수됨';
  @override
  String get desk => 'Desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ 추적: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$ko
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => '당신의 개인 Git 클라이언트.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$ko
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get question => '왜 FLUTTER인가?';
  @override
  String get body =>
      '이 앱의 첫 버전은 Tauri 앱(Rust + TypeScript)이었습니다. 느리다는 건 이미 느끼고 있었습니다. 그러다 평소 잘 보지도 않던 방송에서 어느 스트리머가 똑같은 말을 하는 걸 듣고, 그게 마침내 갈아탈 계기가 됐습니다. 그가 Flutter를 추천한 건 아닙니다. 오히려 정반대였죠. Dart는 제가 직접 찾아냈고, 프로토타입을 얼기설기 만들어 봤더니 시작 시간이 약 15초에서 1초 미만으로 줄었습니다. 하늘과 땅 차이였습니다. Tauri 시대여, 안녕.\n\nFlutter의 렌더링 파이프라인은 DOM보다 게임 엔진에 가깝고, UI 자체가 제품인 데스크톱 앱에서는 그게 전부입니다. Dart도 알고 보니 정말 좋은 언어였습니다. 스펙트럴 엔진 뒤의 수학은 Rust로 먼저 프로토타이핑했던 터라 그 작업은 무리 없이 옮겨졌습니다.\n\nFlutter는 기본적으로 크로스 플랫폼이라 좋지만, 태생이 구글스러운지라 몇 가지 특이한 구석이 있습니다.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$ko
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get question => '스펙트럴 엔진이란?';
  @override
  String get body =>
      '커밋할 때마다 함께 변경하는 파일들이 시간이 지나며 패턴을 이룹니다. 스펙트럴 엔진은 커밋 그래프를 읽어 이 공동 변경 패턴을 신호로 분해합니다. 어떤 파일들이 결합되어 있는지, 얼마나 단단히, 그리고 저장소에서 어떤 구조적 역할을 하는지 말입니다. 한마디로 개발 히스토리에 대한 스펙트럴 분석입니다. 그것도 git 클라이언트 안에서. 일부러요.\n\n이 수학은 새로운 것이라, 저는 이걸 게임 감각처럼 다룹니다. 조율하고, 테스트하고, 다듬고, 신호가 옳게 느껴질 때까지 계속 밀어붙입니다.\n\n이 신호들이 모든 것에 흘러들어갑니다. 히스토리의 지진계, 커밋 제목 아래 칠해진 막대, 리뷰 시스템, Muse, 파일 별자리까지. 앱 전체가 이 계층에서부터 위로 추론하지, 그 반대가 아닙니다.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$ko
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get question => '어디로 향하고 있나?';
  @override
  String get body =>
      '첫 번째 이정표는 GitHub Desktop, SourceTree, GitKraken과의 완전한 동등함입니다. 빠르게 느껴지고 기본기를 그 무엇보다 잘 다루는 크로스 플랫폼 git 클라이언트요. 그건 거의 다 왔습니다. 스펙트럴 엔진은 다른 클라이언트에서 수동으로 머리를 써야 하는 작업들에서 이미 우리에게 우위를 줍니다.\n\n그 너머의 목표는 속도, 접근성, 지능, 전반적인 UX에서 다른 모든 git 클라이언트를 능가하는 것입니다. 여기 공개된 것보다 더 많은 것이 준비 중입니다.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$ko
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$ko verbLed =
      _Translations$settings$commitPreview$title$verbLed$ko._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$ko
  descriptive = _Translations$settings$commitPreview$title$descriptive$ko._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$ko narrative =
      _Translations$settings$commitPreview$title$narrative$ko._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$ko
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$ko verbLed =
      _Translations$settings$commitPreview$base$verbLed$ko._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$ko
  descriptive = _Translations$settings$commitPreview$base$descriptive$ko._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$ko narrative =
      _Translations$settings$commitPreview$base$narrative$ko._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$ko
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$ko
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$ko._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$ko
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$ko._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$ko
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$ko._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$ko
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$ko
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$ko._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$ko
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$ko._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$ko
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$ko._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$ko
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim => '이 저장소는 브랜치 인식 탐색이 유용할 만큼 충분한 브랜치 표면을 가지고 있습니다.';
  @override
  String get broadTitle => '브랜치 모델에 표면적이 있음';
  @override
  String localBranchesDetail({required Object count}) => '로컬 브랜치 ${count}개.';
  @override
  String get localBranchesLabel => '로컬 브랜치';
  @override
  String remoteBranchesDetail({required Object count}) => '원격 브랜치 ${count}개.';
  @override
  String get remoteBranchesLabel => '원격 브랜치';
  @override
  String get simpleClaim => '보이는 브랜치 모델이 좁습니다.';
  @override
  String get simpleTitle => '단순한 브랜치 모델';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$ko
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '작업이 평탄한 일일 리듬보다 집중된 폭발로 이루어집니다.';
  @override
  String get title => '폭발적 개발 리듬';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$ko
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '정상적인 브랜치/태그 공간 밖에 ref ${count}개가 있습니다.';
  @override
  String evidenceDetail({required Object count}) =>
      'heads/remotes/tags 밖에 ref ${count}개.';
  @override
  String get evidenceLabel => '숨겨진 ref';
  @override
  String get namespacesLabel => '네임스페이스';
  @override
  String get title => '숨겨진 Git 네임스페이스';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$ko
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String claim({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '소수의 파일이 터치 횟수에 비해 불균형하게 큰 공동 변경 비중을 지닙니다.',
      );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '${n}회 터치 · pull φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('ko'))(
        n,
        other: '키스톤 브리지 파일 ${n}개',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$ko
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '체크포인트 방식의 커밋이 단순 히스토리 지표를 크게 왜곡합니다.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '커밋 ${count}개가 머신/세션 패턴과 일치했습니다.';
  @override
  String get machineCommitsLabel => '머신 커밋';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '원본 커밋 ${raw}개 대 필터링된 커밋 ${filtered}개.';
  @override
  String get rawVsFilteredLabel => '원본 대 필터링';
  @override
  String get title => '머신 히스토리가 원본 지표를 지배함';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$ko
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      '히스토리가 `${older}` → `${newer}` 방향으로 이동하여, 스택 또는 표면 전환을 시사합니다.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches}회 터치, 마지막 활동 ${lastActive}.';
  @override
  String get title => '아키텍처 마이그레이션이 보임';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$ko
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get claim => '소수의 파일과 디렉터리가 불균형하게 큰 변경 비중을 흡수합니다.';
  @override
  String get title => '핫스폿 집중이 좁음';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} — 보이는 핫스폿 집합의 ${pct}% 차지.';
  @override
  String get topHotspotLabel => '최상위 핫스폿';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '이 히스토리 구간에 작성자 ${count}명.';
  @override
  String get visibleAuthorsLabel => '보이는 작성자';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$ko
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'Git 태그가 눈에 보이는 릴리스나 마일스톤 계층으로 사용되지 않고 있습니다.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '원격 엔드포인트 ${count}개 구성됨.';
  @override
  String get remoteEndpointsLabel => '원격 엔드포인트';
  @override
  String get tagCountDetail => '태그 0개 발견.';
  @override
  String get tagCountLabel => '태그 수';
  @override
  String get title => '공식 릴리스/태그 자취 없음';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$ko
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get claim => 'reflog 양이 게시된 커밋 너머의 집중된 로컬 반복을 시사합니다.';
  @override
  String get peakReflogDayLabel => 'reflog 최다일';
  @override
  String get title => '집중적인 로컬 편집 세션';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$ko
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` — 뚜렷한 작성자 한 명이 보이는, 많이 터치된 ${kind}.';
  @override
  String ownerCountDetail({required Object count}) => '뚜렷한 작성자 ${count}명.';
  @override
  String get ownerCountLabel => '소유자 수';
  @override
  String get title => '단일 소유자 핫스폿';
  @override
  String get touchCountLabel => '터치 수';
  @override
  String touchDetailFiltered({required Object count}) =>
      '필터링된 히스토리에서 ${count}회 터치.';
  @override
  String touchDetailRaw({required Object count}) => '원본 히스토리에서 ${count}회 터치.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$ko
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '열기';
  @override
  String get subtitle => '기존';
  @override
  String get hint => '이미 가지고 있는 것';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$ko
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '클론';
  @override
  String get subtitle => 'URL에서';
  @override
  String get hint => '원격 URL 붙여넣기';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$ko
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get title => '생성';
  @override
  String get subtitle => '새로';
  @override
  String get hint => '새롭게 시작하기';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$ko
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '여우가 냄새 이상한 쿠키를 건너뛰게 하기';
  @override
  String get s2 => '삼키기 전에 손댄 쿠키를 거부하도록 여우 훈련';
  @override
  String get s3 => '문에서 모든 쿠키를 법의학적으로 검증하도록 여우를 강제';
  @override
  String get def => '여우에게 나쁜 쿠키를 거부하도록 가르치기';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$ko
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '이제 여우가 쿠키를 고른다';
  @override
  String get s2 => '쿠키 검사 루틴, 여우에게 반복 주입';
  @override
  String get s3 => '쿠키 검증 법의학, 반복으로 여우에 심음';
  @override
  String get def => '쿠키 냄새 맡기 프로토콜, 여우에 설치';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$ko
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '여우가 냄새 이상한 쿠키를 건너뛰기 시작했다';
  @override
  String get s2 => '여우와 마주 앉아 어떤 쿠키를 거부할지 하나하나 짚어봤다';
  @override
  String get s3 => '건네받은 모든 쿠키가 선의로 된 쿠키는 아니라는 걸 여우에게 납득시키느라 오후의 상당 부분을 썼다';
  @override
  String get def => '여우에게 먹기 전에 쿠키 냄새를 맡아 달라고 부탁했다';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$ko
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '여우가 흘긋 본다. 이상한 건 남겨둔다.';
  @override
  String get s2 => '여우가 각 토큰을 검사하고, 냄새 이상한 건 거절하며, 현관에 거절을 기록한다.';
  @override
  String get s3 =>
      '여우가 각 토큰을 빙 돌며 세 각도에서 공기를 맡고, 이상하게 읽히는 건 거부하며, 거부가 확실히 자리 잡도록 한 박자 기다린다.';
  @override
  String get def => '이제 여우가 각 토큰의 냄새를 맡고 의심스러운 건 정중히 거절한다.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$ko
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '이상한 것들은 대체로 슬쩍 넘긴다.';
  @override
  String get s2 => '냄새 이상한 모든 토큰에 대한 문서화된 거부, 현관에서 발부되어 기록됨.';
  @override
  String get s3 => '냄새 이상한 토큰마다 공증된 거부, 한 발은 들고 다른 발은 가만히 둔 채 현관에서 발부.';
  @override
  String get def => '의심스러운 토큰에 대한 정중한 거부, 현관에서 발부.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$ko
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$ko._(TranslationsKo root)
    : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => '여우가 그냥 이상한 것들을 안 먹기 시작했다. 간단하다.';
  @override
  String get s2 =>
      '예전엔 모든 토큰이 별생각 없이 넘어갔다. 이제는 멈춤이 있고, 제대로 된 관찰이 있고, 영 마음에 걸리는 것에 대한 거부가 있다.';
  @override
  String get s3 =>
      '예전엔 모든 토큰이 생각 없이 넘어갔다. 이제는: 멈춤. 공기를 들이마시고. 공기를 붙든다. 여우는 뭔가 이상할 때 이따금 나타나는 현관 널빤지의 미세한 떨림을 지켜보고, 그제야 판단을 내린다.';
  @override
  String get def => '예전엔 모든 토큰이 격식 없이 삼켜졌다. 이제는 먼저 한 번 킁킁한다.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$ko
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 현관은 괜찮다. 뒷마당은 아무래도 좋다.';
  @override
  String get s2 => ' 거부할 때마다 현관을 쓴다. 뒷마당 진흙은 게시된 시간 내에서 허용.';
  @override
  String get s3 => ' 현관을 쓸고 또 쓴다. 뒷마당 진흙은 발자국과 날씨로 분류되고, 여우는 전보다 문턱에 더 오래 머문다.';
  @override
  String get def => ' 현관은 깨끗이 유지되고, 뒷마당은 진흙 권리를 지킨다.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$ko
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 현관은 괜찮다. 뒷마당은 뒷마당다운 짓을 한다.';
  @override
  String get s2 => ' 현관은 증거처럼 깨끗한 구역, 뒷마당은 지정된 진흙 구역, 시간 게시됨.';
  @override
  String get s3 => ' 현관은 증거급 청정실, 뒷마당은 목록화된 진흙 기록소, 문턱은 여우가 서서 너무 오래 생각하는 곳.';
  @override
  String get def => ' 깨끗한 현관, 뒷마당에 보존된 진흙 권리.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$ko
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 현관은 괜찮았다. 뒷마당은, 누가 알겠나.';
  @override
  String get s2 => ' 그 뒤로 현관은 깨끗이 유지됐다. 여우는 뒷마당으로 물러났는데, 거기가 바로 생각이 이뤄지는 곳이다.';
  @override
  String get s3 =>
      ' 그날 저녁 현관은 두 번 문질러 닦였다. 여우는 뒷마당을 느리게 걸었고, 늘 그렇듯 같은 울타리 기둥에서 멈췄으며, 현관이 뭔가 빚진 것처럼 현관을 돌아봤다.';
  @override
  String get def => ' 현관은 깨끗이 유지되지만, 그래도 품위는 뒷마당이 이긴다.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$ko
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 앰버는 거기 있다. 드리프트는 떠돈다. 가시는 필요하면 찌른다. 대체로 아무 일 없다.';
  @override
  String get s2 =>
      ' 앰버는 검토를 위해 각 향을 붙든다. 드리프트는 하루의 공기를 문 가시 쪽으로 실어 나르고, 가시는 저녁 집계를 위해 각 거부를 표시한다.';
  @override
  String get s3 =>
      ' 앰버는 각 향을 붙들고 시각에 따라 다른 무게를 준다. 드리프트는 상관없어야 할 각도로 현관을 가로지르지만 실은 상관이 있다. 문 가시는 거부에는 한 번, 여우가 하마터면 놓칠 뻔한 것에는 두 번 찌르고, 여우는 아무도 모를 때조차 그 차이를 안다.';
  @override
  String get def => ' 앰버는 향을 붙든다. 드리프트는 그것을 흘려보낸다. 문 가시는 지나가선 안 될 것을 붙잡는다.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$ko
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 앰버는 기둥에. 드리프트는 공기 중에. 가시는 문에. 괜찮다.';
  @override
  String get s2 =>
      ' 앰버는 지정된 향 증인, 드리프트는 기록된 주변 환경, 가시 표시는 하루의 거부 기록, 해질녘에 대조됨.';
  @override
  String get s3 =>
      ' 앰버는 침묵 자체가 하나의 판독인 향 증인, 드리프트는 뭔가 잘못된 날엔 잘못 움직이는 패턴화된 주변 환경, 가시는 여우가 잠들기 전과 동트기 전에 다시 그 표시를 확인하는 문의 집계원.';
  @override
  String get def => ' 앰버는 향 증인, 드리프트는 주변 맥락, 가시는 문의 조용한 거부 표시.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$ko
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$ko._(
    TranslationsKo root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsKo _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' 앰버는 근처에 있었다. 드리프트는 왔다 갔다. 가시는 조용히 제 일을 했다. 어쨌든, 느긋했다.';
  @override
  String get s2 =>
      ' 앰버는 그날의 향 기록을 맡았고, 드리프트는 방향과 시각으로 기록됐으며, 가시의 표시는 집계되어 현관의 부서명을 받았다.';
  @override
  String get s3 =>
      ' 앰버는 향 기록을 맡았지만, 여우는 어떤 아침엔 그게 더 무겁게 느껴진다고 우긴다. 드리프트는 늘 그렇듯 현관을 가로질렀는데, 다시 말해 중요한 날엔 잘못 움직였다. 문 가시는 각 거부를 표시했고, 여우는 이미 세어 본 계단을 다시 세듯 첫 햇빛에 나가 그것들을 셌다.';
  @override
  String get def => ' 앰버는 향 기록을 맡았고, 드리프트는 공기를 움직였으며, 문 가시는 붙잡아야 할 것을 붙잡았다.';
}
