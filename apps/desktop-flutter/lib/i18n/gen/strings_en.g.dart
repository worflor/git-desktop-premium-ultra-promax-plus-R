///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element

class Translations with BaseTranslations<AppLocale, Translations> {
  /// Returns the current translations of the given [context].
  ///
  /// Usage:
  /// final t = Translations.of(context);
  static Translations of(BuildContext context) =>
      InheritedLocaleData.of<AppLocale, Translations>(context).translations;

  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  Translations({
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
             locale: AppLocale.en,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           );

  /// Metadata for the translations of <en>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final Translations _root = this; // ignore: unused_field

  Translations $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => Translations(meta: meta ?? this.$meta);

  // Translations
  late final Translations$app$en app = Translations$app$en.internal(_root);
  late final Translations$backend$en backend = Translations$backend$en.internal(
    _root,
  );
  late final Translations$branches$en branches =
      Translations$branches$en.internal(_root);
  late final Translations$changes$en changes = Translations$changes$en.internal(
    _root,
  );
  late final Translations$common$en common = Translations$common$en.internal(
    _root,
  );
  late final Translations$diff$en diff = Translations$diff$en.internal(_root);
  late final Translations$filament$en filament =
      Translations$filament$en.internal(_root);
  late final Translations$history$en history = Translations$history$en.internal(
    _root,
  );
  late final Translations$historySurgery$en historySurgery =
      Translations$historySurgery$en.internal(_root);
  late final Translations$onboarding$en onboarding =
      Translations$onboarding$en.internal(_root);
  late final Translations$orrery$en orrery = Translations$orrery$en.internal(
    _root,
  );
  late final Translations$palette$en palette = Translations$palette$en.internal(
    _root,
  );
  late final Translations$releaseNotes$en releaseNotes =
      Translations$releaseNotes$en.internal(_root);
  late final Translations$repoSummary$en repoSummary =
      Translations$repoSummary$en.internal(_root);
  late final Translations$review$en review = Translations$review$en.internal(
    _root,
  );
  late final Translations$settings$en settings =
      Translations$settings$en.internal(_root);
  late final Translations$sync$en sync = Translations$sync$en.internal(_root);
  late final Translations$xray$en xray = Translations$xray$en.internal(_root);
}

// Path: app
class Translations$app$en {
  Translations$app$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Settings'
  String get panelSettings => 'Settings';

  /// en: 'Release Notes'
  String get panelReleaseNotes => 'Release Notes';

  /// en: 'Filament Findings'
  String get panelFilamentFindings => 'Filament Findings';

  /// en: 'FILAMENT FINDINGS'
  String get filamentFindingsUpper => 'FILAMENT FINDINGS';

  late final Translations$app$cheatsheet$en cheatsheet =
      Translations$app$cheatsheet$en.internal(_root);

  /// en: 'Command palette /'
  String get commandPaletteTooltip => 'Command palette   /';

  /// en: 'new desk'
  String get newDeskFallback => 'new desk';

  /// en: 'desk'
  String get deskFallback => 'desk';

  /// en: 'current'
  String get currentDeskFallback => 'current';

  /// en: 'No repository open'
  String get noRepositoryOpen => 'No repository open';

  /// en: 'Couldn't open as desk: {error}'
  String couldntOpenAsDesk({required Object error}) =>
      'Couldn\'t open as desk: ${error}';

  /// en: 'Could not detect forge: {error}'
  String couldNotDetectForge({required Object error}) =>
      'Could not detect forge: ${error}';

  /// en: 'Cannot fetch PR: forge not detected for this repo.'
  String get cannotFetchPrNoForge =>
      'Cannot fetch PR: forge not detected for this repo.';

  /// en: 'Overwrite {ref} with the latest from the remote?'
  String overwriteRefConfirm({required Object ref}) =>
      'Overwrite ${ref} with the latest from the remote?';

  /// en: 'Overwrite'
  String get overwrite => 'Overwrite';

  /// en: 'Couldn't fetch PR: {error}'
  String couldntFetchPr({required Object error}) =>
      'Couldn\'t fetch PR: ${error}';

  /// en: 'Promote desk to PR'
  String get promoteDeskToPr => 'Promote desk to PR';

  /// en: 'Apply to main'
  String get applyToMain => 'Apply to main';

  /// en: 'Update {target} from {source}'
  String updateDeskFrom({required Object target, required Object source}) =>
      'Update ${target} from ${source}';

  /// en: 'Bring changes from {source} here'
  String bringChangesFromHere({required Object source}) =>
      'Bring changes from ${source} here';

  /// en: 'Edit local PR'
  String get editLocalPr => 'Edit local PR';

  /// en: 'Discard local PR'
  String get discardLocalPr => 'Discard local PR';

  /// en: 'Close desk'
  String get closeDesk => 'Close desk';

  /// en: 'Couldn't promote: {error}'
  String couldntPromote({required Object error}) =>
      'Couldn\'t promote: ${error}';

  /// en: 'Commit or shelve the desk's changes before applying.'
  String get commitOrShelveBeforeApplying =>
      'Commit or shelve the desk\'s changes before applying.';

  /// en: 'Could not resolve the main worktree path.'
  String get couldNotResolveMainWorktree =>
      'Could not resolve the main worktree path.';

  /// en: 'Couldn't promote desk: {error}'
  String couldntPromoteDesk({required Object error}) =>
      'Couldn\'t promote desk: ${error}';

  /// en: 'Couldn't determine the base branch for this desk.'
  String get couldntDetermineBaseBranch =>
      'Couldn\'t determine the base branch for this desk.';

  /// en: 'PR base and head are the same branch ({branch}) — nothing to apply.'
  String prBaseHeadSame({required Object branch}) =>
      'PR base and head are the same branch (${branch}) — nothing to apply.';

  /// en: 'Applied {branch} to {base}'
  String appliedBranchToBase({required Object branch, required Object base}) =>
      'Applied ${branch} to ${base}';

  /// en: '(one) {Updated {target} to {source} ({n} commit).} (other) {Updated {target} to {source} ({n} commits).}'
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Updated ${target} to ${source} (${n} commit).',
    other: 'Updated ${target} to ${source} (${n} commits).',
  );

  /// en: 'Fast-forward couldn't land cleanly — showing a patch preview instead.'
  String get fastForwardFailedFallback =>
      'Fast-forward couldn\'t land cleanly — showing a patch preview instead.';

  /// en: '(one) {{target} is ahead of {source} by {n} commit.} (other) {{target} is ahead of {source} by {n} commits.}'
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${target} is ahead of ${source} by ${n} commit.',
    other: '${target} is ahead of ${source} by ${n} commits.',
  );

  /// en: '{target} is already up to date with {source}.'
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} is already up to date with ${source}.';

  /// en: 'Uncommitted changes in {target} — previewing as a patch instead.'
  String uncommittedPreviewNotice({required Object target}) =>
      'Uncommitted changes in ${target} — previewing as a patch instead.';

  /// en: 'update {target} from {source}'
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'update ${target} from ${source}';

  /// en: 'No updates to bring from {source}.'
  String noUpdatesToBringFrom({required Object source}) =>
      'No updates to bring from ${source}.';

  /// en: 'Update prep failed'
  String get updatePrepFailed => 'Update prep failed';

  /// en: 'bring changes from {source} into {target}'
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'bring changes from ${source} into ${target}';

  /// en: 'No patchable changes to bring from {source} into {target}.'
  String noPatchableChanges({required Object source, required Object target}) =>
      'No patchable changes to bring from ${source} into ${target}.';

  /// en: 'Patch prep failed'
  String get patchPrepFailed => 'Patch prep failed';

  /// en: '{label}: {error}'
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';

  /// en: 'title'
  String get titleHint => 'title';

  /// en: 'body'
  String get bodyHint => 'body';

  /// en: 'body (optional)'
  String get bodyOptionalHint => 'body (optional)';

  /// en: 'draft'
  String get draftLower => 'draft';

  /// en: 'cancel'
  String get cancelLower => 'cancel';

  /// en: 'save'
  String get saveLower => 'save';

  /// en: 'Couldn't save: {error}'
  String couldntSave({required Object error}) => 'Couldn\'t save: ${error}';

  /// en: 'Changes stashed — no other desk to apply them to. Use git stash pop to recover.'
  String get stashedNoOtherDesk =>
      'Changes stashed — no other desk to apply them to. Use git stash pop to recover.';

  /// en: 'suggested source'
  String get suggestedSource => 'suggested source';

  /// en: '{n} modified'
  String tooltipModifiedCount({required Object n}) => '${n} modified';

  /// en: '{n} ahead'
  String tooltipAheadCount({required Object n}) => '${n} ahead';

  /// en: '{n} behind'
  String tooltipBehindCount({required Object n}) => '${n} behind';

  /// en: 'focused edits'
  String get focusedEdits => 'focused edits';

  /// en: 'edits spread across subsystems'
  String get editsSpreadAcrossSubsystems => 'edits spread across subsystems';

  /// en: 'edits touching many subsystems'
  String get editsTouchingManySubsystems => 'edits touching many subsystems';

  /// en: 'focused branch'
  String get focusedBranch => 'focused branch';

  /// en: 'branch spans multiple subsystems'
  String get branchSpansMultipleSubsystems =>
      'branch spans multiple subsystems';

  /// en: 'structurally divergent from mainline'
  String get structurallyDivergentFromMainline =>
      'structurally divergent from mainline';

  /// en: 'local PR'
  String get localPr => 'local PR';

  /// en: 'last touched {time}'
  String lastTouched({required Object time}) => 'last touched ${time}';

  /// en: '{n} in {dir}'
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} in ${dir}';

  /// en: '{summary} +{remainder}'
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';

  /// en: 'Uncommitted changes'
  String get uncommittedChanges => 'Uncommitted changes';

  /// en: 'Close desk?'
  String get closeDeskQuestion => 'Close desk?';

  /// en: '(one) {{n} uncommitted file.} (other) {{n} uncommitted files.}'
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} uncommitted file.',
        other: '${n} uncommitted files.',
      );

  /// en: '(one) {{n} commit ahead of main.} (other) {{n} commits ahead of main.}'
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} commit ahead of main.',
        other: '${n} commits ahead of main.',
      );

  /// en: 'This will remove the worktree directory.'
  String get willRemoveWorktreeDirectory =>
      'This will remove the worktree directory.';

  /// en: '(one) {{n} file changed} (other) {{n} files changed}'
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file changed',
        other: '${n} files changed',
      );

  /// en: 'Shelve here'
  String get shelveHere => 'Shelve here';

  /// en: 'Discard & close'
  String get discardAndClose => 'Discard & close';

  /// en: 'no repository'
  String get noRepository => 'no repository';

  /// en: 'Issue promoted to remote.'
  String get issuePromotedToRemote => 'Issue promoted to remote.';

  /// en: 'Pushed to remote.'
  String get pushedToRemote => 'Pushed to remote.';

  /// en: 'Pulled from remote.'
  String get pulledFromRemote => 'Pulled from remote.';

  /// en: 'remote issue not found'
  String get remoteIssueNotFound => 'remote issue not found';

  /// en: 'Imported #{id} locally.'
  String importedIssueLocally({required Object id}) =>
      'Imported #${id} locally.';

  /// en: 'Issue abandoned.'
  String get issueAbandoned => 'Issue abandoned.';

  /// en: 'Abandon issue'
  String get abandonIssue => 'Abandon issue';

  /// en: 'Permanently remove local issue #{id}? This deletes its ref and can't be undone.'
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Permanently remove local issue #${id}? This deletes its ref and can\'t be undone.';

  /// en: 'Abandon'
  String get abandon => 'Abandon';

  /// en: 'Published {branch}.'
  String publishedBranch({required Object branch}) => 'Published ${branch}.';

  /// en: 'Publishing…'
  String get publishingEllipsis => 'Publishing…';

  /// en: 'Publish'
  String get publish => 'Publish';

  /// en: 'No remote configured for this repository.'
  String get noRemoteConfigured => 'No remote configured for this repository.';

  /// en: 'Jump to desk'
  String get jumpToDesk => 'Jump to desk';

  /// en: '→ open'
  String get arrowOpen => '→ open';

  /// en: 'Open on a new desk'
  String get openOnANewDesk => 'Open on a new desk';

  /// en: '+ desk'
  String get plusDesk => '+ desk';

  /// en: '+ '
  String get plusSpace => '+ ';

  /// en: 'new-branch-name'
  String get newBranchNameHint => 'new-branch-name';

  /// en: 'esc'
  String get escLower => 'esc';

  /// en: '+ new desk'
  String get plusNewDesk => '+ new desk';

  /// en: 'from HEAD...'
  String get fromHeadEllipsis => 'from HEAD...';

  /// en: 'View all branches'
  String get viewAllBranches => 'View all branches';

  /// en: 'issues'
  String get issuesLower => 'issues';

  /// en: 'new issue'
  String get newIssueLower => 'new issue';

  /// en: 'none linked'
  String get noneLinked => 'none linked';

  /// en: 'no open issues'
  String get noOpenIssues => 'no open issues';

  /// en: 'create + push'
  String get createAndPushLower => 'create + push';

  /// en: 'create'
  String get createLower => 'create';

  /// en: 'remote'
  String get remoteLower => 'remote';

  /// en: '#{id} {title}'
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';

  /// en: 'Promote to remote'
  String get promoteToRemote => 'Promote to remote';

  /// en: 'Push to remote'
  String get pushToRemote => 'Push to remote';

  /// en: 'Pull from remote'
  String get pullFromRemote => 'Pull from remote';

  /// en: 'Import'
  String get importLabel => 'Import';

  /// en: 'Failed to create repository.'
  String get failedToCreateRepository => 'Failed to create repository.';

  /// en: 'open repository'
  String get openRepositoryLower => 'open repository';

  /// en: 'new repository'
  String get newRepositoryLower => 'new repository';

  /// en: 'Back'
  String get back => 'Back';

  /// en: 'Open Repository'
  String get openRepositoryDialogTitle => 'Open Repository';

  /// en: 'Create Repository'
  String get createRepositoryDialogTitle => 'Create Repository';

  /// en: 'Clone Target'
  String get cloneTargetDialogTitle => 'Clone Target';

  /// en: 'Clone to'
  String get cloneToDialogTitle => 'Clone to';

  /// en: 'Export to'
  String get exportToDialogTitle => 'Export to';

  /// en: 'Create from template in'
  String get createFromTemplateInDialogTitle => 'Create from template in';

  /// en: 'Not a git repository. Initialize one here?'
  String get notAGitRepoInitConfirm =>
      'Not a git repository. Initialize one here?';

  /// en: 'Repository URL required.'
  String get repositoryUrlRequired => 'Repository URL required.';

  /// en: 'Failed to clone repository.'
  String get failedToCloneRepository => 'Failed to clone repository.';

  /// en: 'Cloning {name}...'
  String cloningEllipsis({required Object name}) => 'Cloning ${name}...';

  /// en: 'Clone cancelled.'
  String get cloneCancelled => 'Clone cancelled.';

  /// en: 'No projects yet'
  String get noProjectsYet => 'No projects yet';

  /// en: 'Dissolve group'
  String get dissolveGroup => 'Dissolve group';

  /// en: 'Projects'
  String get projectsHeader => 'Projects';

  /// en: 'Clone'
  String get cloneLabel => 'Clone';

  /// en: 'Create'
  String get createLabel => 'Create';

  /// en: 'Open'
  String get openLabel => 'Open';

  /// en: 'Repository URL'
  String get repositoryUrlPlaceholder => 'Repository URL';

  /// en: 'project-name or full path'
  String get projectNameOrFullPathPlaceholder => 'project-name or full path';

  /// en: '/path/to/project'
  String get pathToProjectPlaceholder => '/path/to/project';

  /// en: 'Clone to folder path'
  String get cloneToFolderPathPlaceholder => 'Clone to folder path';

  /// en: 'Switch to Create repo'
  String get switchToCreateRepo => 'Switch to Create repo';

  /// en: 'Explorer'
  String get explorer => 'Explorer';

  /// en: 'Terminal'
  String get terminal => 'Terminal';

  /// en: 'Clone URL'
  String get cloneUrl => 'Clone URL';

  /// en: 'Copy path'
  String get copyPath => 'Copy path';

  /// en: 'Export'
  String get export => 'Export';

  /// en: 'README'
  String get readme => 'README';

  /// en: 'Duplicate'
  String get duplicate => 'Duplicate';

  /// en: 'Template'
  String get template => 'Template';

  /// en: 'Forget this project'
  String get forgetThisProject => 'Forget this project';

  /// en: 'commit message'
  String get aiKindCommitMessage => 'commit message';

  /// en: 'review'
  String get aiKindReview => 'review';

  /// en: 'muse'
  String get aiKindMuse => 'muse';

  /// en: 'present'
  String get aiKindPresent => 'present';

  /// en: 'debug'
  String get aiKindDebug => 'debug';

  /// en: '{kind} running'
  String aiStatusRunning({required Object kind}) => '${kind} running';

  /// en: '{kind} failed (unread)'
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} failed (unread)';

  /// en: '{kind} ready (unread)'
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} ready (unread)';

  /// en: 'files'
  String get filesLower => 'files';

  /// en: 'commits'
  String get commitsLower => 'commits';

  /// en: 'Undo'
  String get undoLabel => 'Undo';

  /// en: 'go'
  String get goLabel => 'go';

  /// en: '{n}s'
  String countdownSeconds({required Object n}) => '${n}s';

  /// en: '▲ collapse'
  String get collapseGlyph => '▲ collapse';

  /// en: '▼ {n} more lines'
  String moreLinesGlyph({required Object n}) => '▼ ${n} more lines';
}

// Path: backend
class Translations$backend$en {
  Translations$backend$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$backend$ops$en ops =
      Translations$backend$ops$en.internal(_root);
  late final Translations$backend$mergeOutcome$en mergeOutcome =
      Translations$backend$mergeOutcome$en.internal(_root);
}

// Path: branches
class Translations$branches$en {
  Translations$branches$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Running AI review…'
  String get runningAiReview => 'Running AI review…';

  /// en: 'PR #{number}'
  String prNumberLabel({required Object number}) => 'PR #${number}';

  /// en: 'FINDINGS'
  String get findings => 'FINDINGS';

  /// en: 'OBSERVATIONS'
  String get observations => 'OBSERVATIONS';

  /// en: 'Rename…'
  String get renameEllipsis => 'Rename…';

  /// en: 'Publish'
  String get publish => 'Publish';

  /// en: 'Publish failed: {error}'
  String publishFailed({required Object error}) => 'Publish failed: ${error}';

  /// en: 'Couldn't open desk: {error}'
  String couldntOpenDesk({required Object error}) =>
      'Couldn\'t open desk: ${error}';

  /// en: 'Sync failed: {error}'
  String syncFailed({required Object error}) => 'Sync failed: ${error}';

  /// en: 'Rename branch'
  String get renameBranchTitle => 'Rename branch';

  /// en: 'new name'
  String get newNameHint => 'new name';

  /// en: 'Rename'
  String get rename => 'Rename';

  /// en: ''{name}' is not a valid branch name.'
  String invalidBranchName({required Object name}) =>
      '\'${name}\' is not a valid branch name.';

  /// en: 'Rename failed: {error}'
  String renameFailed({required Object error}) => 'Rename failed: ${error}';

  /// en: 'Deleting {name}'
  String deletingBranch({required Object name}) => 'Deleting ${name}';

  /// en: ''{name}' is open in desk '{desk}'.'
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' is open in desk \'${desk}\'.';

  /// en: 'Open desk'
  String get openDesk => 'Open desk';

  /// en: 'open in desk '{desk}''
  String openInDeskShort({required Object desk}) => 'open in desk \'${desk}\'';

  /// en: 'could not pin the branch tip; delete skipped'
  String get couldNotPinBranch =>
      'could not pin the branch tip; delete skipped';

  /// en: 'could not pin the tag; delete skipped'
  String get couldNotPinTag => 'could not pin the tag; delete skipped';

  /// en: 'Deleting tag {name}'
  String deletingTag({required Object name}) => 'Deleting tag ${name}';

  /// en: 'Apply to active changes…'
  String get applyToActiveChanges => 'Apply to active changes…';

  /// en: 'Could not load PR diff.'
  String get couldNotLoadPrDiff => 'Could not load PR diff.';

  /// en: 'PR #{number}: {title}'
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';

  /// en: 'Merge into {branch}…'
  String mergeIntoDesk({required Object branch}) => 'Merge into ${branch}…';

  /// en: 'Checkout this PR'
  String get checkoutThisPr => 'Checkout this PR';

  /// en: 'Merge into new desk…'
  String get mergeIntoNewDesk => 'Merge into new desk…';

  /// en: 'Push to forge'
  String get pushToForge => 'Push to forge';

  /// en: 'Link to issue…'
  String get linkToIssue => 'Link to issue…';

  /// en: '↓ git patch'
  String get gitPatch => '↓ git patch';

  /// en: 'Copy branch name'
  String get copyBranchName => 'Copy branch name';

  /// en: 'Copied "{ref}"'
  String copiedRef({required Object ref}) => 'Copied "${ref}"';

  /// en: 'Review PR'
  String get reviewPr => 'Review PR';

  /// en: 'Open in browser'
  String get openInBrowser => 'Open in browser';

  /// en: 'Mark as read'
  String get markAsRead => 'Mark as read';

  /// en: 'Mark as unread'
  String get markAsUnread => 'Mark as unread';

  /// en: 'Replace local commits?'
  String get replaceLocalCommitsTitle => 'Replace local commits?';

  /// en: '{ref} has local commits that are not on the remote PR head. Updating it will replace them with the latest from the remote.'
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} has local commits that are not on the remote PR head. Updating it will replace them with the latest from the remote.';

  /// en: 'Update'
  String get update => 'Update';

  /// en: 'Couldn't fetch PR: {error}'
  String couldntFetchPr({required Object error}) =>
      'Couldn\'t fetch PR: ${error}';

  /// en: 'Couldn't open as desk: {error}'
  String couldntOpenAsDesk({required Object error}) =>
      'Couldn\'t open as desk: ${error}';

  /// en: 'Couldn't open in browser: {error}'
  String couldntOpenInBrowser({required Object error}) =>
      'Couldn\'t open in browser: ${error}';

  /// en: 'No issues yet. Open one upstream, or use "+ new local issue" in the issues lens.'
  String get noIssuesYetLocal =>
      'No issues yet. Open one upstream, or use "+ new local issue" in the issues lens.';

  /// en: 'Remote PRs can only link to local issues. Create one with "+ new local issue".'
  String get remotePrsLinkLocalOnly =>
      'Remote PRs can only link to local issues. Create one with "+ new local issue".';

  /// en: 'Link PR #{number} to issue(s)'
  String linkPrToIssues({required Object number}) =>
      'Link PR #${number} to issue(s)';

  /// en: 'No PRs yet. Open one upstream, or promote a desk to PR.'
  String get noPrsYetLocal =>
      'No PRs yet. Open one upstream, or promote a desk to PR.';

  /// en: 'Remote issues can only link to local PRs. Promote a desk to PR first.'
  String get remoteIssuesLinkLocalOnly =>
      'Remote issues can only link to local PRs. Promote a desk to PR first.';

  /// en: 'Link issue #{number} to PR(s)'
  String linkIssueToPrs({required Object number}) =>
      'Link issue #${number} to PR(s)';

  /// en: 'Couldn't toggle link: {error}'
  String couldntToggleLink({required Object error}) =>
      'Couldn\'t toggle link: ${error}';

  /// en: 'Open patch (.patch / .diff)'
  String get openPatchDialogTitle => 'Open patch (.patch / .diff)';

  /// en: 'Clipboard has no text.'
  String get clipboardNoText => 'Clipboard has no text.';

  /// en: 'clipboard.patch'
  String get clipboardPatchLabel => 'clipboard.patch';

  /// en: 'Failed to open patch: {error}'
  String failedToOpenPatch({required Object error}) =>
      'Failed to open patch: ${error}';

  /// en: 'Patch is empty or unparseable.'
  String get patchEmptyOrUnparseable => 'Patch is empty or unparseable.';

  /// en: 'PR pushed to forge.'
  String get prPushedToForge => 'PR pushed to forge.';

  /// en: 'Overwrite {ref} with the latest from the remote?'
  String overwriteRefConfirm({required Object ref}) =>
      'Overwrite ${ref} with the latest from the remote?';

  /// en: 'Overwrite'
  String get overwrite => 'Overwrite';

  /// en: 'Loading branches'
  String get loadingBranchesTitle => 'Loading branches';

  /// en: 'Reading local branches and tags.'
  String get loadingBranchesMessage => 'Reading local branches and tags.';

  /// en: 'Branches unavailable'
  String get branchesUnavailableTitle => 'Branches unavailable';

  /// en: 'filter pull requests…'
  String get filterPullRequestsHint => 'filter pull requests…';

  /// en: 'filter issues…'
  String get filterIssuesHint => 'filter issues…';

  /// en: 'branch name'
  String get branchNameHint => 'branch name';

  /// en: 'tags, newest first'
  String get tagsNewestFirst => 'tags, newest first';

  /// en: 'tags, oldest first'
  String get tagsOldestFirst => 'tags, oldest first';

  /// en: 'flip sort direction'
  String get flipSortDirection => 'flip sort direction';

  /// en: 'Reading pull requests…'
  String get readingPullRequests => 'Reading pull requests…';

  /// en: 'No open pull requests'
  String get noOpenPullRequests => 'No open pull requests';

  /// en: 'Open one from a branch, or promote a desk.'
  String get noPullRequestsHint => 'Open one from a branch, or promote a desk.';

  /// en: 'No PRs match these filters'
  String get noPrsMatchFilters => 'No PRs match these filters';

  /// en: 'Toggle filters off in the row above.'
  String get toggleFiltersRowAbove => 'Toggle filters off in the row above.';

  /// en: 'issues, newest first'
  String get issuesNewestFirst => 'issues, newest first';

  /// en: 'issues, oldest first'
  String get issuesOldestFirst => 'issues, oldest first';

  /// en: 'ISSUES'
  String get issuesHeading => 'ISSUES';

  /// en: 'reading issues…'
  String get readingIssuesLower => 'reading issues…';

  /// en: 'No open issues'
  String get noOpenIssues => 'No open issues';

  /// en: '+ new for tracking work and bugs.'
  String get noIssuesHint => '+ new for tracking work and bugs.';

  /// en: 'Nothing matches'
  String get nothingMatches => 'Nothing matches';

  /// en: 'Toggle filters off above.'
  String get toggleFiltersAbove => 'Toggle filters off above.';

  /// en: 'FRESH'
  String get bucketFresh => 'FRESH';

  /// en: 'THIS WEEK'
  String get bucketThisWeek => 'THIS WEEK';

  /// en: 'STALLED'
  String get bucketStalled => 'STALLED';

  /// en: 'OLDER'
  String get bucketOlder => 'OLDER';

  /// en: 'Could not resolve the main worktree path.'
  String get couldNotResolveMainWorktree =>
      'Could not resolve the main worktree path.';

  /// en: 'Couldn't submit review: {error}'
  String couldntSubmitReview({required Object error}) =>
      'Couldn\'t submit review: ${error}';

  /// en: 'Review AI is not available yet.'
  String get reviewAiNotAvailable => 'Review AI is not available yet.';

  /// en: 'No review model is configured.'
  String get noReviewModelConfigured => 'No review model is configured.';

  /// en: 'desk'
  String get deskFallback => 'desk';

  /// en: '(one) {{branch} has {n} uncommitted change — commit or stash first.} (other) {{branch} has {n} uncommitted changes — commit or stash first.}'
  String deskUncommittedChanges({required num n, required Object branch}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${branch} has ${n} uncommitted change — commit or stash first.',
        other:
            '${branch} has ${n} uncommitted changes — commit or stash first.',
      );

  /// en: 'Target desk has no branch.'
  String get targetDeskNoBranch => 'Target desk has no branch.';

  /// en: 'Merge PR #{number} into {branch}'
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Merge PR #${number} into ${branch}';

  /// en: 'Conflict check unavailable — git 2.38+ required'
  String get conflictCheckUnavailableVersion =>
      'Conflict check unavailable — git 2.38+ required';

  /// en: 'Conflict check unavailable'
  String get conflictCheckUnavailable => 'Conflict check unavailable';

  /// en: '(one) {WILL CONFLICT · {n} file} (other) {WILL CONFLICT · {n} files}'
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'WILL CONFLICT · ${n} file',
        other: 'WILL CONFLICT · ${n} files',
      );

  /// en: '+{n} more'
  String plusMore({required Object n}) => '+${n} more';

  /// en: 'Rebase'
  String get rebase => 'Rebase';

  /// en: 'Squash'
  String get squash => 'Squash';

  /// en: 'Merge commit'
  String get mergeCommit => 'Merge commit';

  /// en: 'No desk found for branch {branch}'
  String noDeskForBranch({required Object branch}) =>
      'No desk found for branch ${branch}';

  /// en: 'Merge anyway'
  String get mergeAnyway => 'Merge anyway';

  /// en: 'Reading issues…'
  String get readingIssues => 'Reading issues…';

  /// en: 'Open one upstream, or open a local one.'
  String get openUpstreamOrLocal => 'Open one upstream, or open a local one.';

  /// en: 'No issues match these filters'
  String get noIssuesMatchFilters => 'No issues match these filters';

  /// en: 'Couldn't create issue: {error}'
  String couldntCreateIssue({required Object error}) =>
      'Couldn\'t create issue: ${error}';

  /// en: 'Promote to remote'
  String get promoteToRemote => 'Promote to remote';

  /// en: 'Push to remote'
  String get pushToRemote => 'Push to remote';

  /// en: 'Pull from remote'
  String get pullFromRemote => 'Pull from remote';

  /// en: 'Import'
  String get import => 'Import';

  /// en: 'Link to PR…'
  String get linkToPr => 'Link to PR…';

  /// en: 'Abandon'
  String get abandon => 'Abandon';

  /// en: 'Issue promoted to remote.'
  String get issuePromotedToRemote => 'Issue promoted to remote.';

  /// en: 'Pushed to remote.'
  String get issuePushedToRemote => 'Pushed to remote.';

  /// en: 'Pulled from remote.'
  String get issuePulledFromRemote => 'Pulled from remote.';

  /// en: 'Imported #{number} locally.'
  String issueImportedLocally({required Object number}) =>
      'Imported #${number} locally.';

  /// en: 'Abandon issue'
  String get abandonIssueTitle => 'Abandon issue';

  /// en: 'Permanently remove local issue #{id}? This deletes its ref and can't be undone.'
  String abandonIssueMessage({required Object id}) =>
      'Permanently remove local issue #${id}? This deletes its ref and can\'t be undone.';

  /// en: 'Couldn't abandon: {error}'
  String couldntAbandon({required Object error}) =>
      'Couldn\'t abandon: ${error}';

  /// en: 'Couldn't post comment: {error}'
  String couldntPostComment({required Object error}) =>
      'Couldn\'t post comment: ${error}';

  /// en: 'Couldn't close issue: {error}'
  String couldntCloseIssue({required Object error}) =>
      'Couldn\'t close issue: ${error}';

  /// en: 'Couldn't add label: {error}'
  String couldntAddLabel({required Object error}) =>
      'Couldn\'t add label: ${error}';

  /// en: 'BRANCHES'
  String get lensBranches => 'BRANCHES';

  /// en: 'PRs'
  String get lensPrs => 'PRs';

  /// en: '↑ patch'
  String get patchUp => '↑ patch';

  /// en: '⇅ sync'
  String get syncRibbon => '⇅ sync';

  /// en: 'KEYBOARD'
  String get kbHeading => 'KEYBOARD';

  /// en: 'navigate rows'
  String get kbNavigateRows => 'navigate rows';

  /// en: 'expand / collapse focused row'
  String get kbExpandCollapse => 'expand / collapse focused row';

  /// en: 'checkout focused PR locally'
  String get kbCheckoutPr => 'checkout focused PR locally';

  /// en: 'approve · review'
  String get kbApproveReview => 'approve · review';

  /// en: 'request changes'
  String get kbRequestChanges => 'request changes';

  /// en: 'focus search'
  String get kbFocusSearch => 'focus search';

  /// en: 'switch lens (branches · prs)'
  String get kbSwitchLens => 'switch lens (branches · prs)';

  /// en: 'toggle this overlay'
  String get kbToggleOverlay => 'toggle this overlay';

  /// en: 'press anywhere to dismiss'
  String get kbPressToDismiss => 'press anywhere to dismiss';

  /// en: 'merged with failing checks or without an approving review — investigate first under fire'
  String get overrideScarTooltip =>
      'merged with failing checks or without an approving review — investigate first under fire';

  /// en: '(one) {{n} file overlap your uncommitted work} (other) {{n} files overlap your uncommitted work}'
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file overlap your uncommitted work',
        other: '${n} files overlap your uncommitted work',
      );

  /// en: '(one) {#{pr} ({n} file)} (other) {#{pr} ({n} files)}'
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '#${pr}  (${n} file)',
        other: '#${pr}  (${n} files)',
      );

  /// en: 'DRAFT'
  String get prStateDraft => 'DRAFT';

  /// en: 'LOCAL'
  String get localBadge => 'LOCAL';

  /// en: 'your review pending'
  String get myReviewPending => 'your review pending';

  /// en: 'you ✓'
  String get myReviewApproved => 'you ✓';

  /// en: 'you ✗ requested changes'
  String get myReviewChangesRequested => 'you ✗ requested changes';

  /// en: 'you commented'
  String get myReviewCommented => 'you commented';

  /// en: 'you'
  String get myReviewDefault => 'you';

  /// en: '{count} comments · last from author shown'
  String tailCommentsAuthor({required Object count}) =>
      '${count} comments · last from author shown';

  /// en: 'last comment'
  String get tailLastComment => 'last comment';

  /// en: 'last review · {state}'
  String tailLastReviewState({required Object state}) =>
      'last review · ${state}';

  /// en: 'last review'
  String get tailLastReview => 'last review';

  /// en: 'last check · {state}'
  String tailLastCheckState({required Object state}) => 'last check · ${state}';

  /// en: 'last commit'
  String get tailLastCommit => 'last commit';

  /// en: 'last activity'
  String get tailLastActivity => 'last activity';

  /// en: '(one) {closes {n} issue — click to jump} (other) {closes {n} issues — click to jump}'
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'closes ${n} issue — click to jump',
        other: 'closes ${n} issues — click to jump',
      );

  /// en: '(one) {addressed by {n} PR — click to jump} (other) {addressed by {n} PRs — click to jump}'
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'addressed by ${n} PR — click to jump',
        other: 'addressed by ${n} PRs — click to jump',
      );

  /// en: 'checks'
  String get checksLabel => 'checks';

  /// en: 'reviewers'
  String get reviewersLabel => 'reviewers';

  /// en: 'conflicts'
  String get conflictsLabel => 'conflicts';

  /// en: 'Export failed: {error}'
  String exportFailed({required Object error}) => 'Export failed: ${error}';

  /// en: 'reading files…'
  String get readingFiles => 'reading files…';

  /// en: 'no detail available'
  String get noDetailAvailable => 'no detail available';

  /// en: 'no files reported'
  String get noFilesReported => 'no files reported';

  /// en: 'reading git history…'
  String get readingGitHistory => 'reading git history…';

  /// en: 'knows this code'
  String get knowsThisCode => 'knows this code';

  /// en: '(one) {{n} commit on these files in the last year} (other) {{n} commits on these files in the last year}'
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} commit on these files in the last year',
        other: '${n} commits on these files in the last year',
      );

  /// en: 'WILL FIGHT'
  String get willFight => 'WILL FIGHT';

  /// en: 'orbital partner — cos {cos}'
  String orbitalPartnerCos({required Object cos}) =>
      'orbital partner — cos ${cos}';

  /// en: 'orbit'
  String get orbitLabel => 'orbit';

  /// en: 'TOUCHES YOUR LOCAL WORK'
  String get touchesYourLocalWork => 'TOUCHES YOUR LOCAL WORK';

  /// en: 'merging will likely conflict with your uncommitted changes'
  String get mergingWillConflict =>
      'merging will likely conflict with your uncommitted changes';

  /// en: 'CLOSES'
  String get closesHeading => 'CLOSES';

  /// en: 'FILES'
  String get filesHeading => 'FILES';

  /// en: 'aligned'
  String get orientAligned => 'aligned';

  /// en: 'adjacent'
  String get orientAdjacent => 'adjacent';

  /// en: 'orthogonal'
  String get orientOrthogonal => 'orthogonal';

  /// en: 'field {v}'
  String shapeField({required Object v}) => 'field ${v}';

  /// en: 'source {v}'
  String shapeSource({required Object v}) => 'source ${v}';

  /// en: 'srcΔ {v}'
  String shapeSrcDelta({required Object v}) => 'srcΔ ${v}';

  /// en: 'fldΔ {v}'
  String shapeFldDelta({required Object v}) => 'fldΔ ${v}';

  /// en: 'hf {v}'
  String shapeHf({required Object v}) => 'hf ${v}';

  /// en: 'ho {v}'
  String shapeHo({required Object v}) => 'ho ${v}';

  /// en: 'rg {v}'
  String shapeRg({required Object v}) => 'rg ${v}';

  /// en: 'g {v}'
  String shapeFlowG({required Object v}) => 'g ${v}';

  /// en: 'c {v}'
  String shapeFlowC({required Object v}) => 'c ${v}';

  /// en: 'h {v}'
  String shapeFlowH({required Object v}) => 'h ${v}';

  /// en: 'stress {v}'
  String shapeStress({required Object v}) => 'stress ${v}';

  /// en: 'wit {v}'
  String shapeWit({required Object v}) => 'wit ${v}';

  /// en: 'resonance {v}'
  String resonanceReadout({required Object v}) => 'resonance ${v}';

  /// en: 'usually moves with the files in this PR ({path})'
  String ghostFileTooltip({required Object path}) =>
      'usually moves with the files in this PR\n(${path})';

  /// en: 'draft'
  String get prStateDraftLower => 'draft';

  /// en: 'keystone — repo-wide bridge file'
  String get keystoneTooltip => 'keystone — repo-wide bridge file';

  /// en: 'leave a note (optional)…'
  String get reviewNoteHint => 'leave a note (optional)…';

  /// en: 'comment'
  String get reviewComment => 'comment';

  /// en: 'request changes'
  String get reviewRequestChanges => 'request changes';

  /// en: '✓ approve'
  String get reviewApprove => '✓ approve';

  /// en: '↓ patch'
  String get actionPatchDown => '↓ patch';

  /// en: '✦ pr review'
  String get actionPrReview => '✦ pr review';

  /// en: '⊞ open as desk'
  String get actionOpenAsDesk => '⊞ open as desk';

  /// en: '[c] checkout'
  String get actionCheckout => '[c] checkout';

  /// en: '[m] merge ▾'
  String get actionMerge => '[m] merge ▾';

  /// en: 'merge commit'
  String get mergeMenuMergeCommit => 'merge commit';

  /// en: 'squash & merge'
  String get mergeMenuSquash => 'squash & merge';

  /// en: 'rebase & merge'
  String get mergeMenuRebase => 'rebase & merge';

  /// en: 'delete branch after'
  String get deleteBranchAfter => 'delete branch after';

  /// en: '{n}s'
  String checkDurationSec({required Object n}) => '${n}s';

  /// en: '{m}m {s}s'
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';

  /// en: 'assigned: {names}'
  String assignedTo({required Object names}) => 'assigned: ${names}';

  /// en: '{n} conv · {time}'
  String issueConvLine({required Object n, required Object time}) =>
      '${n} conv · ${time}';

  /// en: 'reading thread…'
  String get readingThread => 'reading thread…';

  /// en: 'ADDRESSED BY'
  String get addressedByHeading => 'ADDRESSED BY';

  /// en: 'DESCRIPTION'
  String get descriptionHeading => 'DESCRIPTION';

  /// en: 'THREAD'
  String get threadHeading => 'THREAD';

  /// en: 'reply…'
  String get replyHint => 'reply…';

  /// en: 'assign me'
  String get assignMe => 'assign me';

  /// en: 'close'
  String get closeLower => 'close';

  /// en: '↩ post'
  String get postReply => '↩ post';

  /// en: 'Remote provider unavailable'
  String get remoteProviderUnavailable => 'Remote provider unavailable';

  /// en: 'No recognised remote host for this repo.'
  String get noRecognisedRemoteHost =>
      'No recognised remote host for this repo.';

  /// en: 'gone'
  String get corpseGone => 'gone';

  /// en: 'absorbed'
  String get corpseAbsorbed => 'absorbed';

  /// en: 'squashed'
  String get corpseSquashed => 'squashed';

  /// en: 'delivered in {hash}'
  String absorbedDeliveredIn({required Object hash}) => 'delivered in ${hash}';

  /// en: 'merging adds no changes'
  String get absorbedNoChanges => 'merging adds no changes';

  /// en: 'upstream gone'
  String get corpseTagUpstreamGone => 'upstream gone';

  /// en: 'absorbed, {receipt}'
  String corpseTagAbsorbed({required Object receipt}) => 'absorbed, ${receipt}';

  /// en: 'squashed and merged'
  String get corpseTagSquashed => 'squashed and merged';

  /// en: '{name}, current branch'
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, current branch';

  /// en: '{name}, tracking {upstream}'
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, tracking ${upstream}';

  /// en: '{label}, {tag}'
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';

  /// en: '{label}, worktree open'
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, worktree open';

  /// en: '{name}, {phrase}'
  String semanticsIdle({required Object name, required Object phrase}) =>
      '${name}, ${phrase}';

  /// en: '{name}, {tag}, {phrase}'
  String semanticsCorpse({
    required Object name,
    required Object tag,
    required Object phrase,
  }) => '${name}, ${tag}, ${phrase}';

  /// en: 'desk'
  String get crossLinkDesk => 'desk';

  /// en: 'PR'
  String get crossLinkPr => 'PR';

  /// en: 'PR · draft'
  String get crossLinkPrDraft => 'PR · draft';

  /// en: '(one) {{n} issue} (other) {{n} issues}'
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} issue',
        other: '${n} issues',
      );

  /// en: 'HEAD'
  String get headBadge => 'HEAD';

  /// en: '→ tracking: {upstream}'
  String trackingLine({required Object upstream}) => '→ tracking: ${upstream}';

  /// en: 'Checkout'
  String get checkoutButton => 'Checkout';

  /// en: 'Create branch'
  String get createBranch => 'Create branch';

  /// en: 'New branch name'
  String get newBranchName => 'New branch name';

  /// en: 'New branch name — {error}'
  String newBranchNameError({required Object error}) =>
      'New branch name — ${error}';

  /// en: 'Force?'
  String get forceDelete => 'Force?';

  /// en: 'annotated'
  String get annotated => 'annotated';

  /// en: 'apply --check failed'
  String get applyCheckFailed => 'apply --check failed';

  /// en: 'OPEN PATCH FROM'
  String get openPatchFrom => 'OPEN PATCH FROM';

  /// en: 'from file…'
  String get patchFromFile => 'from file…';

  /// en: '.patch / .diff'
  String get patchFromFileHint => '.patch / .diff';

  /// en: 'from clipboard'
  String get patchFromClipboard => 'from clipboard';

  /// en: 'paste text'
  String get patchFromClipboardHint => 'paste text';

  /// en: 'PATCH PREVIEW'
  String get patchPreviewHeading => 'PATCH PREVIEW';

  /// en: '{files} · +{adds} −{dels}'
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';

  /// en: 'staged.'
  String get stagedDone => 'staged.';

  /// en: 'applied.'
  String get appliedDone => 'applied.';

  /// en: 'opening…'
  String get opening => 'opening…';

  /// en: '⇋ merge editor'
  String get mergeEditor => '⇋ merge editor';

  /// en: 'staging…'
  String get staging => 'staging…';

  /// en: 'applying…'
  String get applying => 'applying…';

  /// en: 'stage'
  String get stage => 'stage';

  /// en: 'apply'
  String get apply => 'apply';

  /// en: 'refine… (e.g. "also drop the logger changes")'
  String get refineHint => 'refine… (e.g. "also drop the logger changes")';

  /// en: 'armed — next apply will REVERT the patch (-R)'
  String get reverseArmedTooltip =>
      'armed — next apply will REVERT the patch (-R)';

  /// en: 'arm reverse (-R) — undo instead of apply'
  String get reverseDisarmedTooltip =>
      'arm reverse (-R) — undo instead of apply';

  /// en: '⟲ reverse ✓'
  String get reverseArmedLabel => '⟲ reverse ✓';

  /// en: '⟲ reverse'
  String get reverseLabel => '⟲ reverse';

  /// en: '⚠ UNTOUCHED'
  String get untouchedHeading => '⚠ UNTOUCHED';

  /// en: '(one) {{count} of {n} file not in the patch} (other) {{count} of {n} files not in the patch}'
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${count} of ${n} file not in the patch',
        other: '${count} of ${n} files not in the patch',
      );

  /// en: 'these files will stay conflicted — applying will not stage them'
  String get staysConflicted =>
      'these files will stay conflicted — applying will not stage them';

  /// en: 'OR WITH'
  String get orWith => 'OR WITH';

  /// en: 'no AI model configured'
  String get noAiModelConfigured => 'no AI model configured';

  /// en: 'apply with patch from {label}'
  String applyWithPatchFrom({required Object label}) =>
      'apply with patch from ${label}';

  /// en: 'apply with patch from {label} · {model}'
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'apply with patch from ${label}  ·  ${model}';

  /// en: 'patching…'
  String get patching => 'patching…';

  /// en: '✦ apply with patch from {label}'
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  apply with patch from ${label}';

  /// en: 'or with another model'
  String get orWithAnotherModel => 'or with another model';

  /// en: 'git apply --check passed — patch will apply cleanly'
  String get applyCheckPassed =>
      'git apply --check passed — patch will apply cleanly';

  /// en: 'git apply --check failed'
  String get gitApplyCheckFailed => 'git apply --check failed';

  /// en: 'applies cleanly'
  String get appliesClean => 'applies cleanly';

  /// en: 'will not apply'
  String get willNotApply => 'will not apply';

  /// en: 'new local issue'
  String get newLocalIssue => 'new local issue';

  /// en: 'filter…'
  String get filterHint => 'filter…';

  /// en: 'Nothing to link yet.'
  String get nothingToLink => 'Nothing to link yet.';

  /// en: 'Nothing matches.'
  String get nothingMatchesDot => 'Nothing matches.';

  /// en: 'RELEVANT'
  String get relevantHeading => 'RELEVANT';

  /// en: 'ALL'
  String get allHeading => 'ALL';

  /// en: 'done'
  String get doneLower => 'done';

  /// en: 'R'
  String get candidateRemote => 'R';

  /// en: 'L'
  String get candidateLocal => 'L';

  /// en: 'New local issue'
  String get newLocalIssueTitle => 'New local issue';

  /// en: 'title'
  String get titleHint => 'title';

  /// en: 'body (markdown)'
  String get bodyHint => 'body (markdown)';

  /// en: 'cancel'
  String get cancelLower => 'cancel';

  /// en: 'create'
  String get createLower => 'create';

  /// en: 'delete failed'
  String get deleteFailed => 'delete failed';

  /// en: 'Review failed: {error}'
  String reviewFailed({required Object error}) => 'Review failed: ${error}';

  /// en: 'resolution failed'
  String get resolutionFailed => 'resolution failed';

  /// en: 'model returned patch blocks that did not cover the failing files'
  String get patchBlocksNoCover =>
      'model returned patch blocks that did not cover the failing files';

  /// en: 'apply failed'
  String get applyFailed => 'apply failed';

  /// en: 'model returned an empty or unparseable patch'
  String get emptyOrUnparseablePatch =>
      'model returned an empty or unparseable patch';

  /// en: 'no model configured for "{label}"'
  String noModelConfiguredFor({required Object label}) =>
      'no model configured for "${label}"';

  /// en: 'CHECKS'
  String get checksHeading => 'CHECKS';

  /// en: 'PEOPLE'
  String get peopleHeading => 'PEOPLE';

  /// en: 'CONVERSATION'
  String get conversationHeading => 'CONVERSATION';
}

// Path: changes
class Translations$changes$en {
  Translations$changes$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$changes$usage$en usage =
      Translations$changes$usage$en.internal(_root);
  late final Translations$changes$tabs$en tabs =
      Translations$changes$tabs$en.internal(_root);
  late final Translations$changes$tabStrip$en tabStrip =
      Translations$changes$tabStrip$en.internal(_root);
  late final Translations$changes$select$en select =
      Translations$changes$select$en.internal(_root);
  late final Translations$changes$constellationToggle$en constellationToggle =
      Translations$changes$constellationToggle$en.internal(_root);
  late final Translations$changes$nudgeChip$en nudgeChip =
      Translations$changes$nudgeChip$en.internal(_root);
  late final Translations$changes$minimap$en minimap =
      Translations$changes$minimap$en.internal(_root);
  late final Translations$changes$tagInput$en tagInput =
      Translations$changes$tagInput$en.internal(_root);
  late final Translations$changes$composer$en composer =
      Translations$changes$composer$en.internal(_root);
  late final Translations$changes$commit$en commit =
      Translations$changes$commit$en.internal(_root);
  late final Translations$changes$rebase$en rebase =
      Translations$changes$rebase$en.internal(_root);
  late final Translations$changes$editor$en editor =
      Translations$changes$editor$en.internal(_root);
  late final Translations$changes$editorTitles$en editorTitles =
      Translations$changes$editorTitles$en.internal(_root);
  late final Translations$changes$askHint$en askHint =
      Translations$changes$askHint$en.internal(_root);
  late final Translations$changes$fileMenu$en fileMenu =
      Translations$changes$fileMenu$en.internal(_root);
  late final Translations$changes$multiFileMenu$en multiFileMenu =
      Translations$changes$multiFileMenu$en.internal(_root);
  late final Translations$changes$ignoreMenu$en ignoreMenu =
      Translations$changes$ignoreMenu$en.internal(_root);
  late final Translations$changes$discard$en discard =
      Translations$changes$discard$en.internal(_root);
  late final Translations$changes$snack$en snack =
      Translations$changes$snack$en.internal(_root);
  late final Translations$changes$trace$en trace =
      Translations$changes$trace$en.internal(_root);
  late final Translations$changes$cleanTree$en cleanTree =
      Translations$changes$cleanTree$en.internal(_root);
  late final Translations$changes$guardrail$en guardrail =
      Translations$changes$guardrail$en.internal(_root);
  late final Translations$changes$dropHint$en dropHint =
      Translations$changes$dropHint$en.internal(_root);
  late final Translations$changes$diffEmpty$en diffEmpty =
      Translations$changes$diffEmpty$en.internal(_root);
  late final Translations$changes$shelvePill$en shelvePill =
      Translations$changes$shelvePill$en.internal(_root);
  late final Translations$changes$stashAction$en stashAction =
      Translations$changes$stashAction$en.internal(_root);
  late final Translations$changes$stashContents$en stashContents =
      Translations$changes$stashContents$en.internal(_root);
  late final Translations$changes$stashFile$en stashFile =
      Translations$changes$stashFile$en.internal(_root);
  late final Translations$changes$fileRow$en fileRow =
      Translations$changes$fileRow$en.internal(_root);
  late final Translations$changes$resolveStrip$en resolveStrip =
      Translations$changes$resolveStrip$en.internal(_root);
  late final Translations$changes$badge$en badge =
      Translations$changes$badge$en.internal(_root);
  late final Translations$changes$review$en review =
      Translations$changes$review$en.internal(_root);
  late final Translations$changes$commitBtn$en commitBtn =
      Translations$changes$commitBtn$en.internal(_root);
  late final Translations$changes$shapeBtn$en shapeBtn =
      Translations$changes$shapeBtn$en.internal(_root);
  late final Translations$changes$dejaVu$en dejaVu =
      Translations$changes$dejaVu$en.internal(_root);
  late final Translations$changes$identity$en identity =
      Translations$changes$identity$en.internal(_root);
  late final Translations$changes$staleScope$en staleScope =
      Translations$changes$staleScope$en.internal(_root);
  late final Translations$changes$finding$en finding =
      Translations$changes$finding$en.internal(_root);
  late final Translations$changes$muse$en muse =
      Translations$changes$muse$en.internal(_root);
  late final Translations$changes$debug$en debug =
      Translations$changes$debug$en.internal(_root);
  late final Translations$changes$includeSummary$en includeSummary =
      Translations$changes$includeSummary$en.internal(_root);
  late final Translations$changes$status$en status =
      Translations$changes$status$en.internal(_root);
  late final Translations$changes$stash$en stash =
      Translations$changes$stash$en.internal(_root);
  late final Translations$changes$tooltips$en tooltips =
      Translations$changes$tooltips$en.internal(_root);
  late final Translations$changes$mergeEditor$en mergeEditor =
      Translations$changes$mergeEditor$en.internal(_root);
  late final Translations$changes$conflictResolution$en conflictResolution =
      Translations$changes$conflictResolution$en.internal(_root);
  late final Translations$changes$mergeFlow$en mergeFlow =
      Translations$changes$mergeFlow$en.internal(_root);
  late final Translations$changes$constellation$en constellation =
      Translations$changes$constellation$en.internal(_root);
}

// Path: common
class Translations$common$en {
  Translations$common$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ', '
  String get listSeparator => ', ';

  /// en: 'Cancel'
  String get cancel => 'Cancel';

  /// en: 'Close'
  String get close => 'Close';

  /// en: 'Save'
  String get save => 'Save';

  /// en: 'Delete'
  String get delete => 'Delete';

  /// en: 'Retry'
  String get retry => 'Retry';

  /// en: 'Copy'
  String get copy => 'Copy';

  /// en: 'Copied'
  String get copied => 'Copied';

  /// en: 'Done'
  String get done => 'Done';

  /// en: 'Loading…'
  String get loading => 'Loading…';

  /// en: '(one) {{n} file} (other) {{n} files}'
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file',
        other: '${n} files',
      );

  /// en: '(one) {{n} commit} (other) {{n} commits}'
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );

  /// en: '(one) {{n} branch} (other) {{n} branches}'
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} branch',
        other: '${n} branches',
      );

  /// en: '(one) {{n} local commit} (other) {{n} local commits}'
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} local commit',
        other: '${n} local commits',
      );

  /// en: '(one) {{n} remote commit} (other) {{n} remote commits}'
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} remote commit',
        other: '${n} remote commits',
      );

  /// en: '(one) {{n} conflicted file} (other) {{n} conflicted files}'
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} conflicted file',
        other: '${n} conflicted files',
      );

  late final Translations$common$time$en time =
      Translations$common$time$en.internal(_root);
  late final Translations$common$size$en size =
      Translations$common$size$en.internal(_root);
}

// Path: diff
class Translations$diff$en {
  Translations$diff$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$diff$status$en status =
      Translations$diff$status$en.internal(_root);
  late final Translations$diff$toolbar$en toolbar =
      Translations$diff$toolbar$en.internal(_root);
  late final Translations$diff$hunkDropdown$en hunkDropdown =
      Translations$diff$hunkDropdown$en.internal(_root);

  /// en: 'Partial stage failed: {error}'
  String stagingFailed({required Object error}) =>
      'Partial stage failed: ${error}';

  late final Translations$diff$trail$en trail =
      Translations$diff$trail$en.internal(_root);
  late final Translations$diff$pinned$en pinned =
      Translations$diff$pinned$en.internal(_root);
  late final Translations$diff$hunkHint$en hunkHint =
      Translations$diff$hunkHint$en.internal(_root);
  late final Translations$diff$binary$en binary =
      Translations$diff$binary$en.internal(_root);
  late final Translations$diff$media$en media =
      Translations$diff$media$en.internal(_root);
}

// Path: filament
class Translations$filament$en {
  Translations$filament$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'No repository open.'
  String get noRepositoryOpen => 'No repository open.';

  /// en: 'scanning {scanned} / {total} files…'
  String scanningProgress({required Object scanned, required Object total}) =>
      'scanning ${scanned} / ${total} files…';

  /// en: '{count} findings across {files} files'
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} findings across ${files} files';

  /// en: 'Copied {count} findings'
  String copiedFindings({required Object count}) => 'Copied ${count} findings';

  /// en: 'COPY'
  String get copy => 'COPY';

  /// en: 'No execution-flow findings.'
  String get noFindings => 'No execution-flow findings.';

  late final Translations$filament$severity$en severity =
      Translations$filament$severity$en.internal(_root);
  late final Translations$filament$kind$en kind =
      Translations$filament$kind$en.internal(_root);

  /// en: 'L{line}'
  String lineLabel({required Object line}) => 'L${line}';

  /// en: '{source} — {kind}'
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class Translations$history$en {
  Translations$history$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$history$commitLede$en commitLede =
      Translations$history$commitLede$en.internal(_root);
  late final Translations$history$seismograph$en seismograph =
      Translations$history$seismograph$en.internal(_root);
  late final Translations$history$worldline$en worldline =
      Translations$history$worldline$en.internal(_root);
  late final Translations$history$contextMenu$en contextMenu =
      Translations$history$contextMenu$en.internal(_root);
  late final Translations$history$cherryPick$en cherryPick =
      Translations$history$cherryPick$en.internal(_root);
  late final Translations$history$revert$en revert =
      Translations$history$revert$en.internal(_root);
  late final Translations$history$reflog$en reflog =
      Translations$history$reflog$en.internal(_root);

  /// en: '(one) {That commit is deeper than the {n} commit loaded.} (other) {That commit is deeper than the {n} commits loaded.}'
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'That commit is deeper than the ${n} commit loaded.',
        other: 'That commit is deeper than the ${n} commits loaded.',
      );

  /// en: 'Failed to delete tag: {error}'
  String deleteTagFailed({required Object error}) =>
      'Failed to delete tag: ${error}';

  /// en: 'Loading history'
  String get loadingTitle => 'Loading history';

  /// en: 'Reading recent commits.'
  String get loadingMessage => 'Reading recent commits.';

  /// en: 'History unavailable'
  String get unavailableTitle => 'History unavailable';

  /// en: 'Toggle worldline'
  String get toggleWorldline => 'Toggle worldline';

  /// en: 'History'
  String get pageTitle => 'History';

  /// en: 'Viewing last'
  String get viewingLast => 'Viewing last';

  /// en: 'commits'
  String get commitsUnit => 'commits';

  /// en: 'No commit selected'
  String get noCommitSelectedTitle => 'No commit selected';

  /// en: 'Select a commit to inspect its changes.'
  String get noCommitSelectedMessage =>
      'Select a commit to inspect its changes.';

  /// en: 'Loading commit'
  String get loadingCommitTitle => 'Loading commit';

  /// en: 'Reading commit details.'
  String get loadingCommitMessage => 'Reading commit details.';

  /// en: 'Commit unavailable'
  String get commitUnavailableTitle => 'Commit unavailable';

  /// en: 'Could not load commit.'
  String get couldNotLoadCommit => 'Could not load commit.';

  /// en: 'reflog'
  String get reflogDividerLabel => 'reflog';

  /// en: 'Load reflog'
  String get loadReflog => 'Load reflog';

  /// en: 'Create tag'
  String get createTag => 'Create tag';

  /// en: 'New tag name'
  String get newTagName => 'New tag name';

  /// en: 'New tag name — {error}'
  String newTagNameError({required Object error}) => 'New tag name — ${error}';

  /// en: '(one) {{n} file · all changes} (other) {{n} files · all changes}'
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file · all changes',
        other: '${n} files · all changes',
      );

  /// en: 'all changes'
  String get allChangesLabel => 'all changes';

  late final Translations$history$rebase$en rebase =
      Translations$history$rebase$en.internal(_root);
  late final Translations$history$inFlight$en inFlight =
      Translations$history$inFlight$en.internal(_root);
}

// Path: historySurgery
class Translations$historySurgery$en {
  Translations$historySurgery$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$historySurgery$chrome$en chrome =
      Translations$historySurgery$chrome$en.internal(_root);
  late final Translations$historySurgery$select$en select =
      Translations$historySurgery$select$en.internal(_root);
  late final Translations$historySurgery$understand$en understand =
      Translations$historySurgery$understand$en.internal(_root);
  late final Translations$historySurgery$confirm$en confirm =
      Translations$historySurgery$confirm$en.internal(_root);
  late final Translations$historySurgery$execute$en execute =
      Translations$historySurgery$execute$en.internal(_root);
  late final Translations$historySurgery$verify$en verify =
      Translations$historySurgery$verify$en.internal(_root);
  late final Translations$historySurgery$forcePush$en forcePush =
      Translations$historySurgery$forcePush$en.internal(_root);
}

// Path: onboarding
class Translations$onboarding$en {
  Translations$onboarding$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$onboarding$nav$en nav =
      Translations$onboarding$nav$en.internal(_root);
  late final Translations$onboarding$naming$en naming =
      Translations$onboarding$naming$en.internal(_root);
  late final Translations$onboarding$theme$en theme =
      Translations$onboarding$theme$en.internal(_root);
  late final Translations$onboarding$repo$en repo =
      Translations$onboarding$repo$en.internal(_root);
  late final Translations$onboarding$preview$en preview =
      Translations$onboarding$preview$en.internal(_root);
}

// Path: orrery
class Translations$orrery$en {
  Translations$orrery$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$orrery$header$en header =
      Translations$orrery$header$en.internal(_root);
  late final Translations$orrery$status$en status =
      Translations$orrery$status$en.internal(_root);
  late final Translations$orrery$legend$en legend =
      Translations$orrery$legend$en.internal(_root);
  late final Translations$orrery$node$en node =
      Translations$orrery$node$en.internal(_root);
  late final Translations$orrery$milestone$en milestone =
      Translations$orrery$milestone$en.internal(_root);
  late final Translations$orrery$structure$en structure =
      Translations$orrery$structure$en.internal(_root);
  late final Translations$orrery$rail$en rail =
      Translations$orrery$rail$en.internal(_root);
  late final Translations$orrery$selection$en selection =
      Translations$orrery$selection$en.internal(_root);
  late final Translations$orrery$findingKind$en findingKind =
      Translations$orrery$findingKind$en.internal(_root);
  late final Translations$orrery$findings$en findings =
      Translations$orrery$findings$en.internal(_root);
  late final Translations$orrery$anchor$en anchor =
      Translations$orrery$anchor$en.internal(_root);
  late final Translations$orrery$compare$en compare =
      Translations$orrery$compare$en.internal(_root);
}

// Path: palette
class Translations$palette$en {
  Translations$palette$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'active'
  String get active => 'active';

  late final Translations$palette$prefixes$en prefixes =
      Translations$palette$prefixes$en.internal(_root);
  late final Translations$palette$chips$en chips =
      Translations$palette$chips$en.internal(_root);
  late final Translations$palette$predictive$en predictive =
      Translations$palette$predictive$en.internal(_root);
  late final Translations$palette$topTouched$en topTouched =
      Translations$palette$topTouched$en.internal(_root);
  late final Translations$palette$coherence$en coherence =
      Translations$palette$coherence$en.internal(_root);
  late final Translations$palette$keystone$en keystone =
      Translations$palette$keystone$en.internal(_root);
  late final Translations$palette$repoSub$en repoSub =
      Translations$palette$repoSub$en.internal(_root);
  late final Translations$palette$desks$en desks =
      Translations$palette$desks$en.internal(_root);
  late final Translations$palette$actions$en actions =
      Translations$palette$actions$en.internal(_root);
  late final Translations$palette$tools$en tools =
      Translations$palette$tools$en.internal(_root);
  late final Translations$palette$gitCommands$en gitCommands =
      Translations$palette$gitCommands$en.internal(_root);
  late final Translations$palette$pr$en pr =
      Translations$palette$pr$en.internal(_root);
  late final Translations$palette$ai$en ai =
      Translations$palette$ai$en.internal(_root);
  late final Translations$palette$undo$en undo =
      Translations$palette$undo$en.internal(_root);
  late final Translations$palette$navigation$en navigation =
      Translations$palette$navigation$en.internal(_root);
  late final Translations$palette$settings$en settings =
      Translations$palette$settings$en.internal(_root);
  late final Translations$palette$info$en info =
      Translations$palette$info$en.internal(_root);
  late final Translations$palette$debug$en debug =
      Translations$palette$debug$en.internal(_root);
  late final Translations$palette$dev$en dev =
      Translations$palette$dev$en.internal(_root);
  late final Translations$palette$historySurgery$en historySurgery =
      Translations$palette$historySurgery$en.internal(_root);
  late final Translations$palette$orrery$en orrery =
      Translations$palette$orrery$en.internal(_root);
  late final Translations$palette$command$en command =
      Translations$palette$command$en.internal(_root);
  late final Translations$palette$search$en search =
      Translations$palette$search$en.internal(_root);
  late final Translations$palette$wick$en wick =
      Translations$palette$wick$en.internal(_root);
  late final Translations$palette$gitCache$en gitCache =
      Translations$palette$gitCache$en.internal(_root);
}

// Path: releaseNotes
class Translations$releaseNotes$en {
  Translations$releaseNotes$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'dev'
  String get versionFallback => 'dev';

  late final Translations$releaseNotes$about$en about =
      Translations$releaseNotes$about$en.internal(_root);
  late final Translations$releaseNotes$legal$en legal =
      Translations$releaseNotes$legal$en.internal(_root);
}

// Path: repoSummary
class Translations$repoSummary$en {
  Translations$repoSummary$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$repoSummary$backbone$en backbone =
      Translations$repoSummary$backbone$en.internal(_root);
  late final Translations$repoSummary$glance$en glance =
      Translations$repoSummary$glance$en.internal(_root);
  late final Translations$repoSummary$heading$en heading =
      Translations$repoSummary$heading$en.internal(_root);

  /// en: 'Ranking is limited: the coupling graph had no edges (fresh clone or too few commits). File order reflects size, not structural centrality.'
  String get historyStarvedCaveat =>
      'Ranking is limited: the coupling graph had no edges (fresh clone or too few commits). File order reflects size, not structural centrality.';

  late final Translations$repoSummary$pitch$en pitch =
      Translations$repoSummary$pitch$en.internal(_root);
  late final Translations$repoSummary$region$en region =
      Translations$repoSummary$region$en.internal(_root);
  late final Translations$repoSummary$shape$en shape =
      Translations$repoSummary$shape$en.internal(_root);
}

// Path: review
class Translations$review$en {
  Translations$review$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'unresolved'
  String get unresolved => 'unresolved';

  /// en: 'done'
  String get done => 'done';

  /// en: 'ack'
  String get ack => 'ack';

  /// en: 'reply'
  String get reply => 'reply';

  /// en: 'please fix'
  String get pleaseFix => 'please fix';

  /// en: 'draft'
  String get draft => 'draft';

  /// en: 'engine'
  String get engine => 'engine';

  /// en: 'moved'
  String get moved => 'moved';

  /// en: 'your turn'
  String get yourTurn => 'your turn';

  /// en: 'drafts'
  String get drafts => 'drafts';

  /// en: 'publish'
  String get publish => 'publish';

  /// en: 'discard'
  String get discard => 'discard';

  /// en: 'save draft'
  String get saveDraft => 'save draft';

  /// en: 'cancel'
  String get cancel => 'cancel';

  /// en: 'approve'
  String get verdictApprove => 'approve';

  /// en: 'request changes'
  String get verdictRequestChanges => 'request changes';

  /// en: 'comment'
  String get verdictComment => 'comment';

  /// en: 'caught up'
  String get caughtUp => 'caught up';

  /// en: 'since your last look'
  String get sinceLastLook => 'since your last look';

  /// en: 'full diff'
  String get fullDiff => 'full diff';

  /// en: 'write a comment'
  String get commentHint => 'write a comment';

  /// en: 'outdated · last seen R{round}'
  String outdatedLastSeen({required Object round}) =>
      'outdated · last seen R${round}';

  /// en: '{verb} · {who}'
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';

  /// en: 'waiting on {who}'
  String waitingOnFmt({required Object who}) => 'waiting on ${who}';

  /// en: 'R{round}'
  String roundChip({required Object round}) => 'R${round}';

  /// en: '(one) {1 file since your last look} (other) {{n} files since your last look}'
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '1 file since your last look',
        other: '${n} files since your last look',
      );

  /// en: '{n} unresolved'
  String unresolvedCountFmt({required Object n}) => '${n} unresolved';

  /// en: '(one) {1 draft} (other) {{n} drafts}'
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '1 draft',
        other: '${n} drafts',
      );

  /// en: 'Couldn't start the review: {error}'
  String startReviewFailed({required Object error}) =>
      'Couldn\'t start the review: ${error}';

  /// en: 'That line can't be anchored — the file is too large or unavailable.'
  String get anchorUnavailable =>
      'That line can\'t be anchored — the file is too large or unavailable.';

  /// en: 'Review action failed: {error}'
  String reviewActionFailed({required Object error}) =>
      'Review action failed: ${error}';

  /// en: 'That comparison is too large to show here — staying on the full diff.'
  String get lensTooLarge =>
      'That comparison is too large to show here — staying on the full diff.';

  /// en: 'Nothing changed between these snapshots.'
  String get lensEmpty => 'Nothing changed between these snapshots.';

  /// en: 'reopen'
  String get reopen => 'reopen';

  /// en: 'not blocking on me'
  String get notBlocking => 'not blocking on me';

  /// en: 'reviewed'
  String get markReviewed => 'reviewed';

  /// en: '(one) {1 new comment} (other) {{n} new comments}'
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '1 new comment',
        other: '${n} new comments',
      );

  /// en: 'hand to'
  String get handTo => 'hand to';

  /// en: 'REVIEW'
  String get heading => 'REVIEW';

  /// en: 'Set a git identity to review'
  String get identityNeeded => 'Set a git identity to review';

  /// en: 'That file can't be read here — it's too large or missing at this round.'
  String get fileUnreadable =>
      'That file can\'t be read here — it\'s too large or missing at this round.';
}

// Path: settings
class Translations$settings$en {
  Translations$settings$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$settings$language$en language =
      Translations$settings$language$en.internal(_root);
  late final Translations$settings$sectionLabels$en sectionLabels =
      Translations$settings$sectionLabels$en.internal(_root);
  late final Translations$settings$errors$en errors =
      Translations$settings$errors$en.internal(_root);
  late final Translations$settings$promptStatus$en promptStatus =
      Translations$settings$promptStatus$en.internal(_root);
  late final Translations$settings$clearData$en clearData =
      Translations$settings$clearData$en.internal(_root);
  List<String> get guardrailStageLabels => [
    'Loose',
    'Balanced',
    'Strict',
    'Paranoid',
  ];
  late final Translations$settings$guardrailMacro$en guardrailMacro =
      Translations$settings$guardrailMacro$en.internal(_root);
  late final Translations$settings$guardrails$en guardrails =
      Translations$settings$guardrails$en.internal(_root);
  late final Translations$settings$appearance$en appearance =
      Translations$settings$appearance$en.internal(_root);
  late final Translations$settings$retention$en retention =
      Translations$settings$retention$en.internal(_root);
  late final Translations$settings$navigation$en navigation =
      Translations$settings$navigation$en.internal(_root);
  late final Translations$settings$behaviour$en behaviour =
      Translations$settings$behaviour$en.internal(_root);
  late final Translations$settings$retentionClear$en retentionClear =
      Translations$settings$retentionClear$en.internal(_root);
  late final Translations$settings$channels$en channels =
      Translations$settings$channels$en.internal(_root);
  late final Translations$settings$pollResult$en pollResult =
      Translations$settings$pollResult$en.internal(_root);
  late final Translations$settings$keybindingProfile$en keybindingProfile =
      Translations$settings$keybindingProfile$en.internal(_root);
  late final Translations$settings$apiKeys$en apiKeys =
      Translations$settings$apiKeys$en.internal(_root);
  late final Translations$settings$shortcuts$en shortcuts =
      Translations$settings$shortcuts$en.internal(_root);
  late final Translations$settings$toggles$en toggles =
      Translations$settings$toggles$en.internal(_root);
  late final Translations$settings$diffDiffability$en diffDiffability =
      Translations$settings$diffDiffability$en.internal(_root);
  late final Translations$settings$modelSlots$en modelSlots =
      Translations$settings$modelSlots$en.internal(_root);
  late final Translations$settings$modelPicker$en modelPicker =
      Translations$settings$modelPicker$en.internal(_root);
  late final Translations$settings$aiFeatures$en aiFeatures =
      Translations$settings$aiFeatures$en.internal(_root);
  late final Translations$settings$commitEditor$en commitEditor =
      Translations$settings$commitEditor$en.internal(_root);
  late final Translations$settings$review$en review =
      Translations$settings$review$en.internal(_root);
  late final Translations$settings$museHint$en museHint =
      Translations$settings$museHint$en.internal(_root);
  late final Translations$settings$museEditor$en museEditor =
      Translations$settings$museEditor$en.internal(_root);
  late final Translations$settings$museStage$en museStage =
      Translations$settings$museStage$en.internal(_root);
  late final Translations$settings$lensAxis$en lensAxis =
      Translations$settings$lensAxis$en.internal(_root);
  late final Translations$settings$logosLens$en logosLens =
      Translations$settings$logosLens$en.internal(_root);
  late final Translations$settings$sortGuide$en sortGuide =
      Translations$settings$sortGuide$en.internal(_root);
  late final Translations$settings$piggyback$en piggyback =
      Translations$settings$piggyback$en.internal(_root);
  late final Translations$settings$diffStage$en diffStage =
      Translations$settings$diffStage$en.internal(_root);
  late final Translations$settings$undoScope$en undoScope =
      Translations$settings$undoScope$en.internal(_root);
  late final Translations$settings$undoWindow$en undoWindow =
      Translations$settings$undoWindow$en.internal(_root);
  late final Translations$settings$guardrailPhrase$en guardrailPhrase =
      Translations$settings$guardrailPhrase$en.internal(_root);
  late final Translations$settings$reviewGuideHint$en reviewGuideHint =
      Translations$settings$reviewGuideHint$en.internal(_root);
  late final Translations$settings$commitFormat$en commitFormat =
      Translations$settings$commitFormat$en.internal(_root);
  late final Translations$settings$commitPreview$en commitPreview =
      Translations$settings$commitPreview$en.internal(_root);
  late final Translations$settings$externalTools$en externalTools =
      Translations$settings$externalTools$en.internal(_root);
  late final Translations$settings$apiUsage$en apiUsage =
      Translations$settings$apiUsage$en.internal(_root);
  late final Translations$settings$gitea$en gitea =
      Translations$settings$gitea$en.internal(_root);
  late final Translations$settings$wick$en wick =
      Translations$settings$wick$en.internal(_root);
  late final Translations$settings$integrations$en integrations =
      Translations$settings$integrations$en.internal(_root);
  late final Translations$settings$reduceMotion$en reduceMotion =
      Translations$settings$reduceMotion$en.internal(_root);
  late final Translations$settings$resetQuit$en resetQuit =
      Translations$settings$resetQuit$en.internal(_root);
  late final Translations$settings$diagnostics$en diagnostics =
      Translations$settings$diagnostics$en.internal(_root);
  late final Translations$settings$telemetry$en telemetry =
      Translations$settings$telemetry$en.internal(_root);
  late final Translations$settings$flowEngine$en flowEngine =
      Translations$settings$flowEngine$en.internal(_root);
  late final Translations$settings$museStrands$en museStrands =
      Translations$settings$museStrands$en.internal(_root);
  late final Translations$settings$cliPiggyback$en cliPiggyback =
      Translations$settings$cliPiggyback$en.internal(_root);
  late final Translations$settings$header$en header =
      Translations$settings$header$en.internal(_root);
  late final Translations$settings$diagnosticsPanel$en diagnosticsPanel =
      Translations$settings$diagnosticsPanel$en.internal(_root);
  late final Translations$settings$release$en release =
      Translations$settings$release$en.internal(_root);
  late final Translations$settings$providerStatus$en providerStatus =
      Translations$settings$providerStatus$en.internal(_root);
  late final Translations$settings$meridiem$en meridiem =
      Translations$settings$meridiem$en.internal(_root);
  late final Translations$settings$offenders$en offenders =
      Translations$settings$offenders$en.internal(_root);
}

// Path: sync
class Translations$sync$en {
  Translations$sync$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$sync$actions$en actions =
      Translations$sync$actions$en.internal(_root);
  late final Translations$sync$panel$en panel =
      Translations$sync$panel$en.internal(_root);
  late final Translations$sync$forcePush$en forcePush =
      Translations$sync$forcePush$en.internal(_root);
}

// Path: xray
class Translations$xray$en {
  Translations$xray$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$xray$board$en board =
      Translations$xray$board$en.internal(_root);
  late final Translations$xray$cadence$en cadence =
      Translations$xray$cadence$en.internal(_root);
  late final Translations$xray$cards$en cards =
      Translations$xray$cards$en.internal(_root);
  late final Translations$xray$cardTitle$en cardTitle =
      Translations$xray$cardTitle$en.internal(_root);
  late final Translations$xray$grain$en grain =
      Translations$xray$grain$en.internal(_root);
  late final Translations$xray$header$en header =
      Translations$xray$header$en.internal(_root);
  late final Translations$xray$hotspot$en hotspot =
      Translations$xray$hotspot$en.internal(_root);
  late final Translations$xray$inspector$en inspector =
      Translations$xray$inspector$en.internal(_root);
  late final Translations$xray$loadingCard$en loadingCard =
      Translations$xray$loadingCard$en.internal(_root);
  late final Translations$xray$metabolism$en metabolism =
      Translations$xray$metabolism$en.internal(_root);
  late final Translations$xray$multi$en multi =
      Translations$xray$multi$en.internal(_root);
  late final Translations$xray$recency$en recency =
      Translations$xray$recency$en.internal(_root);
  late final Translations$xray$rings$en rings =
      Translations$xray$rings$en.internal(_root);
  late final Translations$xray$stats$en stats =
      Translations$xray$stats$en.internal(_root);
  late final Translations$xray$stratumLabel$en stratumLabel =
      Translations$xray$stratumLabel$en.internal(_root);
  late final Translations$xray$summary$en summary =
      Translations$xray$summary$en.internal(_root);
  late final Translations$xray$tabs$en tabs =
      Translations$xray$tabs$en.internal(_root);
  late final Translations$xray$trajectory$en trajectory =
      Translations$xray$trajectory$en.internal(_root);
  late final Translations$xray$verdict$en verdict =
      Translations$xray$verdict$en.internal(_root);
}

// Path: app.cheatsheet
class Translations$app$cheatsheet$en {
  Translations$app$cheatsheet$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Keyboard'
  String get title => 'Keyboard';

  /// en: 'navigate'
  String get sectionNavigate => 'navigate';

  /// en: 'staging'
  String get sectionStaging => 'staging';

  /// en: 'branches & PRs'
  String get sectionBranchesPrs => 'branches & PRs';

  /// en: 'Changes'
  String get changes => 'Changes';

  /// en: 'History'
  String get history => 'History';

  /// en: 'Branches'
  String get branches => 'Branches';

  /// en: 'X-Ray'
  String get xray => 'X-Ray';

  /// en: 'Switch (always)'
  String get switchAlways => 'Switch (always)';

  /// en: 'Command Palette'
  String get commandPalette => 'Command Palette';

  /// en: 'Elevated Palette'
  String get elevatedPalette => 'Elevated Palette';

  /// en: 'Dismiss'
  String get dismiss => 'Dismiss';

  /// en: 'Refresh'
  String get refresh => 'Refresh';

  /// en: 'Next / prev change'
  String get nextPrevChange => 'Next / prev change';

  /// en: 'Toggle line'
  String get toggleLine => 'Toggle line';

  /// en: 'Toggle hunk'
  String get toggleHunk => 'Toggle hunk';

  /// en: 'Toggle file'
  String get toggleFile => 'Toggle file';

  /// en: 'Pin context'
  String get pinContext => 'Pin context';

  /// en: 'Commit'
  String get commit => 'Commit';

  /// en: 'Accept AI hint'
  String get acceptAiHint => 'Accept AI hint';

  /// en: 'Undo'
  String get undo => 'Undo';

  /// en: 'Navigate'
  String get navigate => 'Navigate';

  /// en: 'Expand'
  String get expand => 'Expand';

  /// en: 'Checkout PR'
  String get checkoutPr => 'Checkout PR';

  /// en: 'Approve'
  String get approve => 'Approve';

  /// en: 'Request changes'
  String get requestChanges => 'Request changes';

  /// en: '{profile} profile · switch in Settings'
  String profileSwitchHint({required Object profile}) =>
      '${profile} profile · switch in Settings';
}

// Path: backend.ops
class Translations$backend$ops$en {
  Translations$backend$ops$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Merge'
  String get merge => 'Merge';

  /// en: 'Pull'
  String get pull => 'Pull';

  /// en: 'Apply'
  String get apply => 'Apply';

  /// en: 'Switch'
  String get switchOp => 'Switch';

  /// en: 'Sync'
  String get sync => 'Sync';
}

// Path: backend.mergeOutcome
class Translations$backend$mergeOutcome$en {
  Translations$backend$mergeOutcome$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{op} cancelled.'
  String cancelled({required Object op}) => '${op} cancelled.';

  /// en: '{op} complete.'
  String complete({required Object op}) => '${op} complete.';

  /// en: '(one) {{n} conflict left — resolve them on the Changes page.} (other) {{n} conflicts left — resolve them on the Changes page.}'
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} conflict left — resolve them on the Changes page.',
        other: '${n} conflicts left — resolve them on the Changes page.',
      );

  /// en: '(one) {Resolved {n} conflict.} (other) {Resolved {n} conflicts.}'
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Resolved ${n} conflict.',
        other: 'Resolved ${n} conflicts.',
      );

  /// en: '(one) {{n} file have uncommitted edits — commit them first.} (other) {{n} files have uncommitted edits — commit them first.}'
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file have uncommitted edits — commit them first.',
        other: '${n} files have uncommitted edits — commit them first.',
      );
}

// Path: changes.usage
class Translations$changes$usage$en {
  Translations$changes$usage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{input} in · {output} out'
  String caption({required Object input, required Object output}) =>
      '${input} in · ${output} out';

  /// en: '{fresh} in · {cached} cached · {out} out'
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} in · ${cached} cached · ${out} out';

  /// en: 'in'
  String get inWord => 'in';

  /// en: 'cached'
  String get cachedWord => 'cached';

  /// en: 'out'
  String get outWord => 'out';

  /// en: '{value} in'
  String tipIn({required Object value}) => '${value}  in';

  /// en: '{value} cache read'
  String tipCacheRead({required Object value}) => '${value}  cache read';

  /// en: '{value} cache write'
  String tipCacheWrite({required Object value}) => '${value}  cache write';

  /// en: '{value} out'
  String tipOut({required Object value}) => '${value}  out';

  /// en: '{value} reasoning'
  String tipReasoning({required Object value}) => '${value}  reasoning';

  /// en: '{value}s wall clock'
  String tipWallClock({required Object value}) => '${value}s  wall clock';
}

// Path: changes.tabs
class Translations$changes$tabs$en {
  Translations$changes$tabs$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Changes'
  String get defaultLabel => 'Changes';

  /// en: 'Empty'
  String get empty => 'Empty';
}

// Path: changes.tabStrip
class Translations$changes$tabStrip$en {
  Translations$changes$tabStrip$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'New Diff Tab'
  String get newDiffTab => 'New Diff Tab';
}

// Path: changes.select
class Translations$changes$select$en {
  Translations$changes$select$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Select all'
  String get selectAll => 'Select all';

  /// en: 'Deselect all'
  String get deselectAll => 'Deselect all';
}

// Path: changes.constellationToggle
class Translations$changes$constellationToggle$en {
  Translations$changes$constellationToggle$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'back to list'
  String get backToList => 'back to list';

  /// en: 'atlas, see commit candidates'
  String get atlas => 'atlas, see commit candidates';
}

// Path: changes.nudgeChip
class Translations$changes$nudgeChip$en {
  Translations$changes$nudgeChip$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{path} couples with {anchor} · {pct}%{receipts}'
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\ncouples with ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class Translations$changes$minimap$en {
  Translations$changes$minimap$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'new'
  String get roleNew => 'new';

  /// en: 'bridge'
  String get roleBridge => 'bridge';

  /// en: 'hub'
  String get roleHub => 'hub';

  /// en: 'leaf'
  String get roleLeaf => 'leaf';

  /// en: 'connected'
  String get roleConnected => 'connected';

  /// en: '{role} · {well}'
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';

  /// en: 'changes with {name}'
  String changesWith({required Object name}) => 'changes with ${name}';

  /// en: 'new file'
  String get newFile => 'new file';

  /// en: 'near {count} other changes in {dir}'
  String nearOtherChanges({required Object count, required Object dir}) =>
      'near ${count} other changes in ${dir}';

  /// en: '{name} usually changes with this file'
  String usuallyChangesWithFile({required Object name}) =>
      '${name} usually changes with this file';
}

// Path: changes.tagInput
class Translations$changes$tagInput$en {
  Translations$changes$tagInput$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'tag...'
  String get hint => 'tag...';
}

// Path: changes.composer
class Translations$changes$composer$en {
  Translations$changes$composer$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'commit message...'
  String get hintPlaceholder => 'commit message...';

  /// en: '{hint} · {char}'
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class Translations$changes$commit$en {
  Translations$changes$commit$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Commit changes'
  String get primaryCommitChanges => 'Commit changes';

  /// en: 'Detached HEAD: commit locally without syncing.'
  String get primaryCommitChangesDetail =>
      'Detached HEAD: commit locally without syncing.';

  /// en: 'Commit & publish'
  String get primaryPublish => 'Commit & publish';

  /// en: 'Create the commit and publish this branch in one step.'
  String get primaryPublishDetail =>
      'Create the commit and publish this branch in one step.';

  /// en: 'Commit & sync'
  String get primarySync => 'Commit & sync';

  /// en: 'Create the commit, then reconcile and ship the branch.'
  String get primarySyncDetail =>
      'Create the commit, then reconcile and ship the branch.';

  /// en: 'Commit & push'
  String get primaryPush => 'Commit & push';

  /// en: 'Create the commit and push it immediately.'
  String get primaryPushDetail => 'Create the commit and push it immediately.';

  /// en: 'Amend last commit'
  String get amendLast => 'Amend last commit';

  /// en: 'Amend & {action}'
  String amendAnd({required Object action}) => 'Amend & ${action}';

  /// en: 'Choose at least one file for the next commit.'
  String get chooseFile => 'Choose at least one file for the next commit.';

  /// en: 'Write a commit message first.'
  String get writeMessage => 'Write a commit message first.';

  /// en: 'Committing'
  String get committing => 'Committing';

  /// en: 'Committing and syncing'
  String get committingSync => 'Committing and syncing';

  /// en: 'Committed.'
  String get committed => 'Committed.';

  /// en: 'Undo failed.'
  String get undoFailed => 'Undo failed.';

  /// en: 'Working…'
  String get working => 'Working…';

  /// en: 'Commit only'
  String get commitOnly => 'Commit only';

  /// en: 'No runtime-discovered models are available for commit messages.'
  String get noRuntimeModels =>
      'No runtime-discovered models are available for commit messages.';

  /// en: '{err} Could not restore the staging of excluded files; check the index before retrying.'
  String restoreFailedRetry({required Object err}) =>
      '${err}\nCould not restore the staging of excluded files; check the index before retrying.';

  /// en: 'Committed {summary} ({hash}).'
  String committedSummary({required Object summary, required Object hash}) =>
      'Committed ${summary} (${hash}).';

  /// en: 'Could not re-stage the selections of excluded files; sync skipped. Check the index before syncing.'
  String get restoreFailedSync =>
      'Could not re-stage the selections of excluded files; sync skipped. Check the index before syncing.';

  /// en: 'No model'
  String get noModelLabel => 'No model';

  /// en: 'Choose at least one file before generating.'
  String get chooseBeforeGenerate =>
      'Choose at least one file before generating.';

  /// en: 'Commit-message AI is not available yet.'
  String get aiUnavailable => 'Commit-message AI is not available yet.';

  /// en: 'Generate failed.'
  String get generateFailed => 'Generate failed.';

  /// en: 'Failed to stage files.'
  String get stageFailed => 'Failed to stage files.';

  /// en: 'Commit failed.'
  String get commitFailed => 'Commit failed.';

  /// en: 'Committed {summary} ({hash}) and ran {operation}.'
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Committed ${summary} (${hash}) and ran ${operation}.';

  /// en: '(one) {Committed {summary} ({hash}); resolved {n} conflict.} (other) {Committed {summary} ({hash}); resolved {n} conflicts.}'
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: 'Committed ${summary} (${hash}); resolved ${n} conflict.',
    other: 'Committed ${summary} (${hash}); resolved ${n} conflicts.',
  );

  /// en: '(one) {{n} conflict left to resolve.} (other) {{n} conflicts left to resolve.}'
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} conflict left to resolve.',
        other: '${n} conflicts left to resolve.',
      );

  /// en: '(one) {Commit succeeded, but sync was blocked by {n} uncommitted file.} (other) {Commit succeeded, but sync was blocked by {n} uncommitted files.}'
  String syncBlocked({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Commit succeeded, but sync was blocked by ${n} uncommitted file.',
        other:
            'Commit succeeded, but sync was blocked by ${n} uncommitted files.',
      );

  /// en: 'Commit succeeded, but sync stalled: {message}'
  String syncStalled({required Object message}) =>
      'Commit succeeded, but sync stalled: ${message}';

  /// en: 'Commit succeeded, but sync failed: {message}'
  String syncFailed({required Object message}) =>
      'Commit succeeded, but sync failed: ${message}';
}

// Path: changes.rebase
class Translations$changes$rebase$en {
  Translations$changes$rebase$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Could not continue the rebase.'
  String get continueFailed => 'Could not continue the rebase.';
}

// Path: changes.editor
class Translations$changes$editor$en {
  Translations$changes$editor$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Close editor'
  String get closeBarrier => 'Close editor';
}

// Path: changes.editorTitles
class Translations$changes$editorTitles$en {
  Translations$changes$editorTitles$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  List<String> get any => [
    'dear git log',
    'for-git me heaven for i hath…',
    'name this moment',
    'yap on',
    'speak!',
    'your mother was a dangling reference and your father smelt of semicolons',
  ];
  List<String> get short => [
    'oh?',
    'hello there:)',
    'btw:',
    'a few words',
    'the polite version',
    'leave a note',
    'you were saying..?',
    'oh yeah, get it out',
  ];
  List<String> get mid => [
    'for the record',
    'tell the future you',
    'but first?',
    'how it went',
    'in your own words',
    'you did WHAT now?',
    'duly noted',
    'you have my attention',
  ];
  List<String> get long => [
    'your dreams, please',
    'say something nice',
    '... and then I said:',
    'posterity awaits',
    'writing more makes your bugs disappear',
    'oh wow',
    'the sacred texts',
  ];
}

// Path: changes.askHint
class Translations$changes$askHint$en {
  Translations$changes$askHint$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'round {n} — refine or add context.'
  String round({required Object n}) => 'round ${n} — refine or add context.';

  /// en: 'describe the symptom.'
  String get symptom => 'describe the symptom.';

  /// en: 'what's broken?'
  String get broken => 'what\'s broken?';

  /// en: 'describe the bug.'
  String get bug => 'describe the bug.';

  /// en: 'paste the error.'
  String get error => 'paste the error.';
}

// Path: changes.fileMenu
class Translations$changes$fileMenu$en {
  Translations$changes$fileMenu$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Ripple'
  String get ripple => 'Ripple';

  /// en: 'Include co-changes'
  String get includeCoChanges => 'Include co-changes';

  /// en: 'Delete {name}…'
  String deleteFile({required Object name}) => 'Delete ${name}…';

  /// en: 'Discard changes to {name}…'
  String discardChangesTo({required Object name}) =>
      'Discard changes to ${name}…';

  /// en: 'Ignore'
  String get ignore => 'Ignore';

  /// en: 'Diff Tab from selection'
  String get diffTabFromSelection => 'Diff Tab from selection';

  /// en: 'Add selected to {name}'
  String addSelectedToTab({required Object name}) => 'Add selected to ${name}';

  /// en: 'Diff Tab from {name}'
  String diffTabFromFile({required Object name}) => 'Diff Tab from ${name}';

  /// en: 'Add {file} to {tab}'
  String addFileToTab({required Object file, required Object tab}) =>
      'Add ${file} to ${tab}';

  /// en: 'Copy file path'
  String get copyFilePath => 'Copy file path';

  /// en: 'Show in Explorer'
  String get showInExplorer => 'Show in Explorer';
}

// Path: changes.multiFileMenu
class Translations$changes$multiFileMenu$en {
  Translations$changes$multiFileMenu$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'tightly coupled'
  String get cohesionTight => 'tightly coupled';

  /// en: 'loosely related'
  String get cohesionLoose => 'loosely related';

  /// en: 'structurally scattered'
  String get cohesionScattered => 'structurally scattered';

  /// en: 'all in one cluster'
  String get clusterOne => 'all in one cluster';

  /// en: 'spans {count} clusters ({parts} files)'
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'spans ${count} clusters (${parts} files)';

  /// en: 'spans {count} clusters'
  String clusterSpans({required Object count}) => 'spans ${count} clusters';

  /// en: '{count} files · {cohesion}'
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} files · ${cohesion}';

  /// en: '{file} usually changes with this group'
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} usually changes with this group';

  /// en: 'Split to new tab'
  String get splitToNewTab => 'Split to new tab';

  /// en: 'Copy {count} paths'
  String copyPaths({required Object count}) => 'Copy ${count} paths';
}

// Path: changes.ignoreMenu
class Translations$changes$ignoreMenu$en {
  Translations$changes$ignoreMenu$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '.{ext} extension'
  String extension({required Object ext}) => '.${ext} extension';

  /// en: 'All {count} selected'
  String allSelected({required Object count}) => 'All ${count} selected';

  /// en: '(one) {Couples with {n} included file} (other) {Couples with {n} included files}'
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Couples with ${n} included file',
        other: 'Couples with ${n} included files',
      );

  /// en: 'Failed to update .gitignore.'
  String get updateFailed => 'Failed to update .gitignore.';
}

// Path: changes.discard
class Translations$changes$discard$en {
  Translations$changes$discard$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Delete {name}?'
  String deleteTitle({required Object name}) => 'Delete ${name}?';

  /// en: 'Discard changes to {name}?'
  String discardTitle({required Object name}) => 'Discard changes to ${name}?';

  /// en: '{path} will be removed from disk. This cannot be undone from inside the app.'
  String deleteBody({required Object path}) =>
      '${path} will be removed from disk. This cannot be undone from inside the app.';

  /// en: 'All changes to {path} will be reverted to their state in HEAD. This cannot be undone.'
  String discardBody({required Object path}) =>
      'All changes to ${path} will be reverted to their state in HEAD. This cannot be undone.';

  /// en: 'Discard'
  String get discard => 'Discard';

  /// en: 'Deleting {name}'
  String deletingFile({required Object name}) => 'Deleting ${name}';

  /// en: 'Discarding {name}'
  String discardingFile({required Object name}) => 'Discarding ${name}';

  /// en: 'Failed to discard changes.'
  String get discardFailed => 'Failed to discard changes.';

  /// en: 'Discard changes to {count} files?'
  String discardManyTitle({required Object count}) =>
      'Discard changes to ${count} files?';

  /// en: 'Tracked files will be reverted to their state in HEAD; untracked files will be removed from disk. This cannot be undone.'
  String get discardManyBody =>
      'Tracked files will be reverted to their state in HEAD; untracked files will be removed from disk. This cannot be undone.';

  /// en: 'Discard {count}'
  String discardManyConfirm({required Object count}) => 'Discard ${count}';

  /// en: 'Discarding {count} files'
  String discardingManyFiles({required Object count}) =>
      'Discarding ${count} files';

  /// en: 'Failed to open file explorer: {error}'
  String failedOpenExplorer({required Object error}) =>
      'Failed to open file explorer: ${error}';

  /// en: 'Some discards failed.'
  String get someFailed => 'Some discards failed.';
}

// Path: changes.snack
class Translations$changes$snack$en {
  Translations$changes$snack$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Same worktree — nothing to dump.'
  String get sameWorktree => 'Same worktree — nothing to dump.';

  /// en: 'Diff failed: {error}'
  String diffFailed({required Object error}) => 'Diff failed: ${error}';

  /// en: 'Desk has nothing ahead of you — empty dump.'
  String get deskEmpty => 'Desk has nothing ahead of you — empty dump.';

  /// en: 'desk {label}'
  String sourceDesk({required Object label}) => 'desk ${label}';

  /// en: 'Shelf read failed: {error}'
  String shelfReadFailed({required Object error}) =>
      'Shelf read failed: ${error}';

  /// en: 'Empty shelf — nothing to dump.'
  String get shelfEmpty => 'Empty shelf — nothing to dump.';

  /// en: 'shelf {label}'
  String sourceShelf({required Object label}) => 'shelf ${label}';

  /// en: 'No model configured for "{label}".'
  String noModelConfigured({required Object label}) =>
      'No model configured for "${label}".';

  /// en: 'Fetch failed: {error}'
  String fetchFailed({required Object error}) => 'Fetch failed: ${error}';
}

// Path: changes.trace
class Translations$changes$trace$en {
  Translations$changes$trace$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Verification trace'
  String get title => 'Verification trace';

  /// en: 'Draft review'
  String get draftReview => 'Draft review';
}

// Path: changes.cleanTree
class Translations$changes$cleanTree$en {
  Translations$changes$cleanTree$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Working tree clean'
  String get title => 'Working tree clean';

  /// en: 'No staged or unstaged changes detected.'
  String get subtitle => 'No staged or unstaged changes detected.';

  /// en: ' · no upstream'
  String get noUpstream => '  ·  no upstream';

  /// en: ' ahead'
  String get ahead => ' ahead';

  /// en: ' behind'
  String get behind => ' behind';

  /// en: 'Refreshing...'
  String get refreshing => 'Refreshing...';

  /// en: 'Refresh'
  String get refresh => 'Refresh';

  /// en: 'check'
  String get check => 'check';

  /// en: 'Fetch and local refresh.'
  String get checkTooltip => 'Fetch and local refresh.';

  /// en: '& sync'
  String get sync => '& sync';
}

// Path: changes.guardrail
class Translations$changes$guardrail$en {
  Translations$changes$guardrail$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Loose'
  String get loose => 'Loose';

  /// en: 'Balanced'
  String get balanced => 'Balanced';

  /// en: 'Strict'
  String get strict => 'Strict';

  /// en: 'Paranoid'
  String get paranoid => 'Paranoid';
}

// Path: changes.dropHint
class Translations$changes$dropHint$en {
  Translations$changes$dropHint$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'drop to bring changes from this shelf here'
  String get fromShelf => 'drop to bring changes from this shelf here';

  /// en: 'drop to bring changes from this desk here'
  String get fromDesk => 'drop to bring changes from this desk here';
}

// Path: changes.diffEmpty
class Translations$changes$diffEmpty$en {
  Translations$changes$diffEmpty$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'No file selected'
  String get title => 'No file selected';

  /// en: 'Select a changed file to inspect its diff.'
  String get message => 'Select a changed file to inspect its diff.';
}

// Path: changes.shelvePill
class Translations$changes$shelvePill$en {
  Translations$changes$shelvePill$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '↓ shelve {count}'
  String shelveN({required Object count}) => '↓ shelve ${count}';

  /// en: '↓ shelve'
  String get shelve => '↓ shelve';

  /// en: '{count} shelved {glyph}'
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} shelved ${glyph}';
}

// Path: changes.stashAction
class Translations$changes$stashAction$en {
  Translations$changes$stashAction$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'pick up'
  String get pickUp => 'pick up';

  /// en: 'peek'
  String get peek => 'peek';

  /// en: 'toss'
  String get toss => 'toss';
}

// Path: changes.stashContents
class Translations$changes$stashContents$en {
  Translations$changes$stashContents$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'reading shelf…'
  String get reading => 'reading shelf…';

  /// en: 'empty shelf'
  String get empty => 'empty shelf';
}

// Path: changes.stashFile
class Translations$changes$stashFile$en {
  Translations$changes$stashFile$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'bin'
  String get binary => 'bin';
}

// Path: changes.fileRow
class Translations$changes$fileRow$en {
  Translations$changes$fileRow$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'commits staged lines only'
  String get stagedLinesOnly => 'commits staged lines only';

  /// en: 'double-click: toggle whole group'
  String get doubleClickToggle => 'double-click: toggle whole group';

  /// en: 'Repository root'
  String get repoRoot => 'Repository root';
}

// Path: changes.resolveStrip
class Translations$changes$resolveStrip$en {
  Translations$changes$resolveStrip$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {reading {n} file · drafting resolution…} (other) {reading {n} files · drafting resolution…}'
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'reading ${n} file · drafting resolution…',
        other: 'reading ${n} files · drafting resolution…',
      );

  /// en: '(one) {{n} conflict across {files}} (other) {{n} conflicts across {files}}'
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} conflict across ${files}',
        other: '${n} conflicts across ${files}',
      );

  /// en: 'Resolve'
  String get resolve => 'Resolve';

  /// en: 'OR WITH'
  String get orWith => 'OR WITH';

  /// en: 'resolve with {label}'
  String resolveWith({required Object label}) => 'resolve with ${label}';

  /// en: 'resolve with {label} · {model}'
  String resolveWithModel({required Object label, required Object model}) =>
      'resolve with ${label}  ·  ${model}';

  /// en: 'resolving…'
  String get resolving => 'resolving…';

  /// en: '↵ resolve with {label}'
  String resolveWithGlyph({required Object label}) =>
      '↵  resolve with ${label}';

  /// en: 'or with another model'
  String get orWithAnother => 'or with another model';
}

// Path: changes.badge
class Translations$changes$badge$en {
  Translations$changes$badge$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Staged edit'
  String get stagedEdit => 'Staged edit';

  /// en: 'Edited'
  String get edited => 'Edited';

  /// en: 'Staged add'
  String get stagedAdd => 'Staged add';

  /// en: 'Added'
  String get added => 'Added';

  /// en: 'Staged delete'
  String get stagedDelete => 'Staged delete';

  /// en: 'Deleted'
  String get deleted => 'Deleted';

  /// en: 'Staged rename'
  String get stagedRename => 'Staged rename';

  /// en: 'Renamed'
  String get renamed => 'Renamed';

  /// en: 'Staged copy'
  String get stagedCopy => 'Staged copy';

  /// en: 'Copied'
  String get copied => 'Copied';

  /// en: 'Conflict'
  String get conflict => 'Conflict';

  /// en: 'Staged type change'
  String get stagedTypeChange => 'Staged type change';

  /// en: 'Type changed'
  String get typeChanged => 'Type changed';

  /// en: 'Untracked'
  String get untracked => 'Untracked';
}

// Path: changes.review
class Translations$changes$review$en {
  Translations$changes$review$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Code review'
  String get title => 'Code review';

  /// en: '(one) {{n} included file} (other) {{n} included files}'
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} included file',
        other: '${n} included files',
      );

  /// en: '(one) {{n} hunk} (other) {{n} hunks}'
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );

  /// en: '{guardrail} | {model}'
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';

  /// en: 'Review unavailable'
  String get unavailable => 'Review unavailable';

  /// en: 'Back to diff'
  String get backToDiff => 'Back to diff';

  /// en: 'Verified'
  String get verified => 'Verified';

  /// en: 'Draft only'
  String get draftOnly => 'Draft only';

  /// en: 'Run again'
  String get runAgain => 'Run again';

  /// en: '{error} Draft review is shown below.'
  String draftShownBelow({required Object error}) =>
      '${error} Draft review is shown below.';

  /// en: 'Hide trace'
  String get hideTrace => 'Hide trace';

  /// en: 'Show trace'
  String get showTrace => 'Show trace';

  /// en: 'Show verification trace'
  String get showVerificationTrace => 'Show verification trace';

  /// en: 'Why this review landed here'
  String get whyLanded => 'Why this review landed here';

  /// en: 'No findings'
  String get noFindings => 'No findings';

  /// en: 'Findings'
  String get findings => 'Findings';

  /// en: 'No evidence-backed issues were surfaced for this commit scope.'
  String get noEvidenceIssues =>
      'No evidence-backed issues were surfaced for this commit scope.';

  /// en: 'Observations'
  String get observations => 'Observations';

  /// en: 'Choose at least one file before reviewing.'
  String get chooseBeforeReview => 'Choose at least one file before reviewing.';

  /// en: 'Review AI is not available yet.'
  String get aiUnavailable => 'Review AI is not available yet.';

  /// en: 'Review failed.'
  String get failed => 'Review failed.';

  /// en: 'No runtime-discovered models are available for commit review.'
  String get noRuntimeModels =>
      'No runtime-discovered models are available for commit review.';
}

// Path: changes.commitBtn
class Translations$changes$commitBtn$en {
  Translations$changes$commitBtn$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Switch to: {label} '
  String switchTo({required Object label}) => 'Switch to: ${label}\n';
}

// Path: changes.shapeBtn
class Translations$changes$shapeBtn$en {
  Translations$changes$shapeBtn$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'asking with {cat}…'
  String askingWith({required Object cat}) => 'asking with ${cat}…';

  /// en: 'ask with {cat}'
  String askWith({required Object cat}) => 'ask with ${cat}';

  /// en: 'no AI model configured'
  String get noModel => 'no AI model configured';

  /// en: 'next: {cat} · shift-click for previous'
  String nextTooltip({required Object cat}) =>
      'next: ${cat}  ·  shift-click for previous';

  /// en: 'only one AI category configured'
  String get onlyOne => 'only one AI category configured';
}

// Path: changes.dejaVu
class Translations$changes$dejaVu$en {
  Translations$changes$dejaVu$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {{pct}% déjà vu — {n} ghost edge from discarded timelines touch this diff} (other) {{pct}% déjà vu — {n} ghost edges from discarded timelines touch this diff}'
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one:
        '${pct}% déjà vu — ${n} ghost edge from discarded timelines touch this diff',
    other:
        '${pct}% déjà vu — ${n} ghost edges from discarded timelines touch this diff',
  );

  /// en: 'déjà vu'
  String get label => 'déjà vu';
}

// Path: changes.identity
class Translations$changes$identity$en {
  Translations$changes$identity$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'no commit identity configured'
  String get none => 'no commit identity configured';

  /// en: 'as {name}'
  String asName({required Object name}) => 'as ${name}';

  /// en: 'as {name} <{email}>'
  String asNameEmail({required Object name, required Object email}) =>
      'as ${name} <${email}>';

  /// en: 'as {name} '
  String asNameSpace({required Object name}) => 'as ${name} ';

  /// en: '<{email}>'
  String emailAngle({required Object email}) => '<${email}>';

  /// en: ' first commit in this repo'
  String get firstCommit => '\nfirst commit in this repo';

  /// en: ' new to this repo'
  String get newToRepo => '\nnew to this repo';
}

// Path: changes.staleScope
class Translations$changes$staleScope$en {
  Translations$changes$staleScope$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'selection changed since this ran'
  String get message => 'selection changed since this ran';

  /// en: 'rerun'
  String get rerun => 'rerun';
}

// Path: changes.finding
class Translations$changes$finding$en {
  Translations$changes$finding$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Open diff'
  String get openDiff => 'Open diff';

  /// en: 'recorded'
  String get recorded => 'recorded';

  /// en: 'Dismiss'
  String get dismiss => 'Dismiss';
}

// Path: changes.muse
class Translations$changes$muse$en {
  Translations$changes$muse$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Muse'
  String get title => 'Muse';

  /// en: 'you pulled this'
  String get youPulledThis => 'you pulled this';

  /// en: 'from idea: "{text}"'
  String fromIdea({required Object text}) => 'from idea: "${text}"';

  /// en: 'foothold — '
  String get foothold => 'foothold — ';

  /// en: 'brainstorm spew'
  String get brainstormSpew => 'brainstorm spew';

  /// en: '{label} · {count}'
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';

  /// en: 'Copy {count}'
  String copyN({required Object count}) => 'Copy ${count}';

  /// en: 'Clear'
  String get clear => 'Clear';

  /// en: 'Choose at least one file before invoking the muse.'
  String get chooseBeforeMuse =>
      'Choose at least one file before invoking the muse.';

  /// en: 'Muse AI is not available yet.'
  String get aiUnavailable => 'Muse AI is not available yet.';

  /// en: 'Muse failed.'
  String get failed => 'Muse failed.';

  /// en: 'No runtime-discovered models are available for the muse.'
  String get noRuntimeModels =>
      'No runtime-discovered models are available for the muse.';

  /// en: 'Muse needs at least one configured model.'
  String get needsModel => 'Muse needs at least one configured model.';

  /// en: 'the muse is dreaming...'
  String get dreaming => 'the muse is dreaming...';
}

// Path: changes.debug
class Translations$changes$debug$en {
  Translations$changes$debug$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Debug'
  String get title => 'Debug';

  /// en: '· round {n}'
  String round({required Object n}) => '· round ${n}';

  /// en: 'clear'
  String get clear => 'clear';

  /// en: 'close'
  String get close => 'close';

  /// en: 'analyzing symptom…'
  String get analyzing => 'analyzing symptom…';

  /// en: 'describe a symptom, then press debug.'
  String get describeSymptom => 'describe a symptom, then press debug.';

  /// en: 'for'
  String get evidenceFor => 'for';

  /// en: 'but'
  String get evidenceAgainst => 'but';

  /// en: 'what would help narrow it down:'
  String get narrowDown => 'what would help narrow it down:';

  /// en: 'Debug failed.'
  String get failed => 'Debug failed.';

  /// en: 'Debug refinement failed.'
  String get refinementFailed => 'Debug refinement failed.';
}

// Path: changes.includeSummary
class Translations$changes$includeSummary$en {
  Translations$changes$includeSummary$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'None'
  String get none => 'None';

  /// en: ' · {count} staged'
  String stagedSuffix({required Object count}) => ' · ${count} staged';

  /// en: '(one) {All {n} file{staged}} (other) {All {n} files{staged}}'
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'All ${n} file${staged}',
        other: 'All ${n} files${staged}',
      );

  /// en: '{count} of {n}{staged}'
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} of ${n}${staged}';

  /// en: 'All {n}{staged}'
  String shortAll({required Object n, required Object staged}) =>
      'All ${n}${staged}';
}

// Path: changes.status
class Translations$changes$status$en {
  Translations$changes$status$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Repository status unavailable'
  String get unavailableTitle => 'Repository status unavailable';

  /// en: 'Loading repository status'
  String get loadingTitle => 'Loading repository status';

  /// en: 'Reading the working tree.'
  String get loadingMessage => 'Reading the working tree.';
}

// Path: changes.stash
class Translations$changes$stash$en {
  Translations$changes$stash$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Stash applied with conflicts — resolve them on the Changes page (the stash entry was kept).'
  String get appliedWithConflicts =>
      'Stash applied with conflicts — resolve them on the Changes page (the stash entry was kept).';

  /// en: 'Could not pop stash.'
  String get couldNotPop => 'Could not pop stash.';

  /// en: 'The stash list changed; drop skipped. Try again.'
  String get listChanged => 'The stash list changed; drop skipped. Try again.';

  /// en: 'Dropping stash'
  String get droppingStash => 'Dropping stash';
}

// Path: changes.tooltips
class Translations$changes$tooltips$en {
  Translations$changes$tooltips$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'generating commit message...'
  String get commitGenerating => 'generating commit message...';

  /// en: 'preparing commit-message...'
  String get commitPreparing => 'preparing commit-message...';

  /// en: 'select at least one file to generate a commit message.'
  String get commitSelectFile =>
      'select at least one file to generate a commit message.';

  /// en: 'configure commit-message in Settings > Behavioural Dynamics > Commit Messages.'
  String get commitConfigure =>
      'configure commit-message in Settings > Behavioural Dynamics > Commit Messages.';

  /// en: 'fast'
  String get fastFallback => 'fast';

  /// en: 'generate commit message with {label} model'
  String commitGenerateWith({required Object label}) =>
      'generate commit message with ${label} model';

  /// en: 'consulting the muse...'
  String get museConsulting => 'consulting the muse...';

  /// en: 'show muse'
  String get showMuse => 'show muse';

  /// en: 'select at least one file for the muse.'
  String get museSelectFile => 'select at least one file for the muse.';

  /// en: 'show muse error'
  String get showMuseError => 'show muse error';

  /// en: 'ask the muse for direction'
  String get museAsk => 'ask the muse for direction';

  /// en: 'ask the muse for direction {brainstorm} → {synthesis}'
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'ask the muse for direction\n${brainstorm} → ${synthesis}';

  /// en: 'quality'
  String get qualityFallback => 'quality';

  /// en: 'reviewing...'
  String get reviewing => 'reviewing...';

  /// en: 'show review'
  String get showReview => 'show review';

  /// en: 'preparing commit review...'
  String get reviewPreparing => 'preparing commit review...';

  /// en: 'select at least one file to review.'
  String get reviewSelectFile => 'select at least one file to review.';

  /// en: 'configure review AI in settings.'
  String get reviewConfigure => 'configure review AI in settings.';

  /// en: 'viewing review'
  String get viewingReview => 'viewing review';

  /// en: '{guardrail} review with {label} model'
  String reviewWith({required Object guardrail, required Object label}) =>
      '${guardrail} review with ${label} model';
}

// Path: changes.mergeEditor
class Translations$changes$mergeEditor$en {
  Translations$changes$mergeEditor$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'yours'
  String get resolutionYours => 'yours';

  /// en: 'theirs'
  String get resolutionTheirs => 'theirs';

  /// en: 'custom'
  String get resolutionCustom => 'custom';

  /// en: 'keep both'
  String get keepBoth => 'keep both';

  late final Translations$changes$mergeEditor$trust$en trust =
      Translations$changes$mergeEditor$trust$en.internal(_root);

  /// en: 'all resolved'
  String get allResolved => 'all resolved';

  /// en: 'resolve easy conflicts'
  String get resolveEasy => 'resolve easy conflicts';

  /// en: 'base'
  String get base => 'base';

  /// en: 'cancel'
  String get cancel => 'cancel';

  /// en: 'save'
  String get save => 'save';

  /// en: 'complete'
  String get complete => 'complete';

  /// en: 'next file'
  String get nextFile => 'next file';

  /// en: 'edit'
  String get edit => 'edit';

  /// en: 'auto'
  String get auto => 'auto';

  /// en: 'undo'
  String get undo => 'undo';

  late final Translations$changes$mergeEditor$keyHints$en keyHints =
      Translations$changes$mergeEditor$keyHints$en.internal(_root);

  /// en: 'structurally favored by coupling analysis'
  String get favoredTooltip => 'structurally favored by coupling analysis';

  /// en: '(new on both sides)'
  String get newOnBothSides => '(new on both sides)';

  /// en: 'Failed to write resolved files: {error}'
  String writeFailed({required Object error}) =>
      'Failed to write resolved files: ${error}';

  /// en: '{changed}/{total} neighbors co-changed'
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} neighbors co-changed';

  /// en: 'integrity {pct}%'
  String integrity({required Object pct}) => 'integrity ${pct}%';

  /// en: 'reviewer: {name}'
  String reviewer({required Object name}) => 'reviewer: ${name}';
}

// Path: changes.conflictResolution
class Translations$changes$conflictResolution$en {
  Translations$changes$conflictResolution$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'No model configured for "{category}". Set one in Settings → AI.'
  String noModelConfigured({required Object category}) =>
      'No model configured for "${category}". Set one in Settings → AI.';

  /// en: '(one) {{n} sensitive file skipped — resolve by hand.} (other) {{n} sensitive files skipped — resolve by hand.}'
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} sensitive file skipped — resolve by hand.',
        other: '${n} sensitive files skipped — resolve by hand.',
      );

  /// en: 'Could not read any conflicted files.'
  String get couldNotReadFiles => 'Could not read any conflicted files.';

  /// en: 'Blocked — a conflicted file looks like it contains a {secret}. Resolve by hand.'
  String blockedSecret({required Object secret}) =>
      'Blocked — a conflicted file looks like it contains a ${secret}. Resolve by hand.';

  /// en: 'Resolution failed: {error}'
  String resolutionFailed({required Object error}) =>
      'Resolution failed: ${error}';

  /// en: '◇ merge resolution · {resolved}/{total} files · {category}'
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ merge resolution · ${resolved}/${total} files · ${category}';

  /// en: '{op} · {conflicts} across {files}'
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} across ${files}';

  /// en: '(one) {{n} conflict} (other) {{n} conflicts}'
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} conflict',
        other: '${n} conflicts',
      );

  /// en: '⇋ merge editor'
  String get mergeEditorButton => '⇋ merge editor';

  /// en: 'no AI model'
  String get noAiModel => 'no AI model';

  /// en: 'later'
  String get later => 'later';

  /// en: 'discard'
  String get discard => 'discard';

  /// en: '◇ resolve with AI'
  String get resolveWithAi => '◇ resolve with AI';

  /// en: 'other model'
  String get otherModel => 'other model';

  /// en: 'with {model}'
  String withModel({required Object model}) => 'with ${model}';
}

// Path: changes.mergeFlow
class Translations$changes$mergeFlow$en {
  Translations$changes$mergeFlow$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$changes$mergeFlow$op$en op =
      Translations$changes$mergeFlow$op$en.internal(_root);

  /// en: 'Push failed'
  String get pushFailed => 'Push failed';

  /// en: 'Rebased and pushed.'
  String get rebasedAndPushed => 'Rebased and pushed.';

  /// en: 'Switched to {name}.'
  String switchedTo({required Object name}) => 'Switched to ${name}.';

  /// en: 'Switch failed.'
  String get switchFailed => 'Switch failed.';

  /// en: 'Switched to {name} (changes carried over).'
  String switchedToCarried({required Object name}) =>
      'Switched to ${name} (changes carried over).';

  /// en: 'Already up to date.'
  String get alreadyUpToDate => 'Already up to date.';

  /// en: 'Merged {upstream} ({n} files).'
  String merged({required Object upstream, required Object n}) =>
      'Merged ${upstream} (${n} files).';

  /// en: 'Rebase did not converge — resolve manually.'
  String get rebaseNotConverge => 'Rebase did not converge — resolve manually.';

  /// en: 'Rebased.'
  String get rebased => 'Rebased.';

  /// en: '(one) {Rebased (resolved {n} file).} (other) {Rebased (resolved {n} files).}'
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Rebased (resolved ${n} file).',
        other: 'Rebased (resolved ${n} files).',
      );

  /// en: 'Cannot sync: detached HEAD state. Check out a branch first.'
  String get detachedHead =>
      'Cannot sync: detached HEAD state. Check out a branch first.';

  /// en: 'Publish failed.'
  String get publishFailed => 'Publish failed.';

  /// en: 'No remote configured. Add one to publish this branch.'
  String get noRemote =>
      'No remote configured. Add one to publish this branch.';

  /// en: 'failed'
  String get failed => 'failed';
}

// Path: changes.constellation
class Translations$changes$constellation$en {
  Translations$changes$constellation$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'STRUCTURE'
  String get axisStructure => 'STRUCTURE';

  /// en: 'CO-CHANGE'
  String get axisCoChange => 'CO-CHANGE';

  /// en: 'SPECTRAL PROFILE'
  String get axisSpectralProfile => 'SPECTRAL PROFILE';

  /// en: 'PATH SIBLINGS'
  String get axisPathSiblings => 'PATH SIBLINGS';

  /// en: 'DIFF STRUCTURE'
  String get axisDiffStructure => 'DIFF STRUCTURE';

  /// en: 'SPECTRAL'
  String get axisSpectral => 'SPECTRAL';

  /// en: 'UNSORTED'
  String get titleUnsorted => 'UNSORTED';

  /// en: 'SINGLETON'
  String get titleSingleton => 'SINGLETON';

  /// en: 'MIXED'
  String get titleMixed => 'MIXED';

  /// en: 'untie'
  String get untie => 'untie';

  /// en: 'bind'
  String get bind => 'bind';

  /// en: 'no clusters yet'
  String get emptyClusters => 'no clusters yet';
}

// Path: common.time
class Translations$common$time$en {
  Translations$common$time$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'now'
  String get now => 'now';

  /// en: 'just now'
  String get justNow => 'just now';

  /// en: 'TODAY'
  String get today => 'TODAY';

  /// en: '{n}m ago'
  String minutesAgo({required Object n}) => '${n}m ago';

  /// en: '{n}h ago'
  String hoursAgo({required Object n}) => '${n}h ago';

  /// en: '{n}d ago'
  String daysAgo({required Object n}) => '${n}d ago';

  /// en: '{n}w ago'
  String weeksAgo({required Object n}) => '${n}w ago';

  /// en: '{n}mo ago'
  String monthsAgo({required Object n}) => '${n}mo ago';

  /// en: '(one) {{n}y ago} (other) {{n}y ago}'
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n}y ago',
        other: '${n}y ago',
      );

  /// en: '{n}m'
  String minutesShort({required Object n}) => '${n}m';

  /// en: '{n}h'
  String hoursShort({required Object n}) => '${n}h';

  /// en: '{n}d'
  String daysShort({required Object n}) => '${n}d';

  /// en: '{n}w'
  String weeksShort({required Object n}) => '${n}w';

  /// en: '{n}mo'
  String monthsShort({required Object n}) => '${n}mo';

  /// en: '(one) {{n}y} (other) {{n}y}'
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n}y',
        other: '${n}y',
      );

  /// en: '{n}m'
  String commitMonthsShort({required Object n}) => '${n}m';

  /// en: 'idle'
  String get idle => 'idle';

  /// en: 'idle {n} days'
  String idleDays({required Object n}) => 'idle ${n} days';

  /// en: '(one) {idle {n} year} (other) {idle {n} years}'
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'idle ${n} year',
        other: 'idle ${n} years',
      );

  List<String> get monthAbbrevs => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

// Path: common.size
class Translations$common$size$en {
  Translations$common$size$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{n} B'
  String bytes({required Object n}) => '${n} B';

  /// en: '{n} KB'
  String kb({required Object n}) => '${n} KB';

  /// en: '{n} MB'
  String mb({required Object n}) => '${n} MB';

  /// en: '{n} GB'
  String gb({required Object n}) => '${n} GB';
}

// Path: diff.status
class Translations$diff$status$en {
  Translations$diff$status$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Loading diff'
  String get loadingTitle => 'Loading diff';

  /// en: 'Reading file changes.'
  String get loadingMessage => 'Reading file changes.';

  /// en: 'Diff unavailable'
  String get unavailableTitle => 'Diff unavailable';

  /// en: 'No changes'
  String get noChangesTitle => 'No changes';

  /// en: 'This file has no diff content to display.'
  String get noChangesMessage => 'This file has no diff content to display.';
}

// Path: diff.toolbar
class Translations$diff$toolbar$en {
  Translations$diff$toolbar$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'search diff...'
  String get searchHint => 'search diff...';

  /// en: '(one) {{n} line} (other) {{n} lines}'
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} line',
        other: '${n} lines',
      );

  /// en: 'blame...'
  String get blameLoading => 'blame...';

  /// en: 'blame'
  String get blame => 'blame';

  /// en: 'wear · on'
  String get wearMapOn => 'wear · on';

  /// en: 'wear map on — click to hide'
  String get wearMapOnHint => 'wear map on — click to hide';

  /// en: 'show wear map (activity heatmap)'
  String get wearMapOffHint => 'show wear map (activity heatmap)';

  /// en: '· trail'
  String get trailBadge => '· trail';
}

// Path: diff.hunkDropdown
class Translations$diff$hunkDropdown$en {
  Translations$diff$hunkDropdown$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Jump to change block. Git calls these hunks.'
  String get tooltip => 'Jump to change block. Git calls these hunks.';

  /// en: '(one) {{n} change} (other) {{n} changes}'
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} change',
        other: '${n} changes',
      );
}

// Path: diff.trail
class Translations$diff$trail$en {
  Translations$diff$trail$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'loading trail...'
  String get loading => 'loading trail...';

  /// en: 'no history found'
  String get noHistory => 'no history found';

  /// en: 'now · working copy'
  String get nowWorkingCopy => 'now · working copy';

  /// en: '{hash} · {author} · {time} · {subject}'
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class Translations$diff$pinned$en {
  Translations$diff$pinned$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'loading pinned context'
  String get loadingContext => 'loading pinned context';

  /// en: 'Manifold'
  String get pageManifold => 'Manifold';

  /// en: 'Signals'
  String get pageSignals => 'Signals';

  /// en: 'Echoes'
  String get echoesTitle => 'Echoes';

  /// en: 'Technical Ledger'
  String get technicalLedger => 'Technical Ledger';

  /// en: 'No secondary cues detected.'
  String get noSecondaryCues => 'No secondary cues detected.';

  /// en: 'Linked Paths'
  String get linkedPaths => 'Linked Paths';

  /// en: '+{n} more'
  String moreCount({required Object n}) => '+${n} more';

  /// en: 'Local seam'
  String get localSeam => 'Local seam';

  /// en: 'shared ownership'
  String get sharedOwnership => 'shared ownership';

  /// en: 'History warming up'
  String get historyWarmingUp => 'History warming up';

  /// en: '{n} TOTAL'
  String echoesTotal({required Object n}) => '${n} TOTAL';

  /// en: 'No echoes in this diff.'
  String get noEchoes => 'No echoes in this diff.';

  /// en: 'Open related file {name}'
  String openRelatedFile({required Object name}) => 'Open related file ${name}';

  /// en: 'inspect {name}'
  String inspectFile({required Object name}) => 'inspect ${name}';

  /// en: 'jump echo'
  String get jumpEcho => 'jump echo';

  /// en: 'copy line'
  String get copyLine => 'copy line';

  /// en: 'T'
  String get signalTempo => 'T';

  /// en: 'N'
  String get signalNovelty => 'N';

  /// en: 'R'
  String get signalReach => 'R';

  late final Translations$diff$pinned$tempo$en tempo =
      Translations$diff$pinned$tempo$en.internal(_root);
  late final Translations$diff$pinned$tone$en tone =
      Translations$diff$pinned$tone$en.internal(_root);
  late final Translations$diff$pinned$summary$en summary =
      Translations$diff$pinned$summary$en.internal(_root);
  late final Translations$diff$pinned$tightness$en tightness =
      Translations$diff$pinned$tightness$en.internal(_root);

  /// en: '{concept} ({tightness})'
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';

  /// en: 'Why this matters'
  String get storyWhyThisMatters => 'Why this matters';

  /// en: 'Confidence'
  String get storyConfidence => 'Confidence';

  /// en: 'Secondary signal'
  String get storySecondarySignal => 'Secondary signal';

  /// en: 'Neighbourhood'
  String get storyNeighbourhood => 'Neighbourhood';

  /// en: 'This line sits close to {name} in the current codebase field.'
  String neighbourhoodDetail({required Object name}) =>
      'This line sits close to ${name} in the current codebase field.';

  /// en: 'Propagation lane'
  String get propagationLane => 'Propagation lane';

  /// en: 'Propagation lane: {lane}'
  String propagationLaneNamed({required Object lane}) =>
      'Propagation lane: ${lane}';

  late final Translations$diff$pinned$witness$en witness =
      Translations$diff$pinned$witness$en.internal(_root);
  late final Translations$diff$pinned$integrity$en integrity =
      Translations$diff$pinned$integrity$en.internal(_root);
  late final Translations$diff$pinned$related$en related =
      Translations$diff$pinned$related$en.internal(_root);
  late final Translations$diff$pinned$axis$en axis =
      Translations$diff$pinned$axis$en.internal(_root);
}

// Path: diff.hunkHint
class Translations$diff$hunkHint$en {
  Translations$diff$hunkHint$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{n} hidden'
  String hiddenCount({required Object n}) => '${n} hidden';

  /// en: 'landing'
  String get landing => 'landing';
}

// Path: diff.binary
class Translations$diff$binary$en {
  Translations$diff$binary$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{size} MB (too large to preview)'
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (too large to preview)';

  /// en: 'Unable to load blob'
  String get unableToLoadBlob => 'Unable to load blob';

  /// en: 'media'
  String get omittedKindMedia => 'media';

  /// en: 'binary'
  String get omittedKindBinary => 'binary';

  /// en: '{kind} · hidden'
  String omittedStub({required Object kind}) => '${kind} · hidden';
}

// Path: diff.media
class Translations$diff$media$en {
  Translations$diff$media$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Unable to decode image'
  String get unableToDecodeImage => 'Unable to decode image';

  /// en: '{format} {size}'
  String sizeLabel({required Object format, required Object size}) =>
      '${format}  ${size}';

  /// en: '{oldSize} → {newSize} ({sign}{delta})'
  String sizeDelta({
    required Object oldSize,
    required Object newSize,
    required Object sign,
    required Object delta,
  }) => '${oldSize} → ${newSize}  (${sign}${delta})';

  /// en: 'added'
  String get stateAdded => 'added';

  /// en: 'deleted'
  String get stateDeleted => 'deleted';

  /// en: 'modified'
  String get stateModified => 'modified';

  /// en: 'Binary'
  String get fallbackFormatName => 'Binary';
}

// Path: filament.severity
class Translations$filament$severity$en {
  Translations$filament$severity$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'critical'
  String get critical => 'critical';

  /// en: 'warn'
  String get warn => 'warn';

  /// en: 'info'
  String get info => 'info';

  /// en: 'joint'
  String get joint => 'joint';
}

// Path: filament.kind
class Translations$filament$kind$en {
  Translations$filament$kind$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'stale value'
  String get staleValue => 'stale value';

  /// en: 'temporal shift'
  String get temporalShift => 'temporal shift';

  /// en: 'context inversion'
  String get contextInversion => 'context inversion';

  /// en: 'contradictory flow'
  String get contradictoryFlow => 'contradictory flow';
}

// Path: history.commitLede
class Translations$history$commitLede$en {
  Translations$history$commitLede$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$history$commitLede$semantics$en semantics =
      Translations$history$commitLede$semantics$en.internal(_root);
}

// Path: history.seismograph
class Translations$history$seismograph$en {
  Translations$history$seismograph$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(root)'
  String get rootTrackLabel => '(root)';

  /// en: '({name})'
  String dirTrackLabel({required Object name}) => '(${name})';

  /// en: '+{n} more'
  String moreLabel({required Object n}) => '+${n} more';

  /// en: '(one) {{n} file in {path}/} (other) {{n} files in {path}/}'
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file in ${path}/',
        other: '${n} files in ${path}/',
      );

  /// en: '(one) {{n} more file} (other) {{n} more files}'
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} more file',
        other: '${n} more files',
      );

  /// en: 'all'
  String get breadcrumbAll => 'all';

  /// en: 'Current focus: {target}'
  String breadcrumbCurrentFocus({required Object target}) =>
      'Current focus: ${target}';

  /// en: 'View all changes in this commit'
  String get breadcrumbViewAllChanges => 'View all changes in this commit';

  /// en: 'Drill up to {target}'
  String breadcrumbDrillUpTo({required Object target}) =>
      'Drill up to ${target}';

  /// en: '(one) {{n} file +{adds} -{dels}} (other) {{n} files +{adds} -{dels}}'
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} file  +${adds}  -${dels}',
    other: '${n} files  +${adds}  -${dels}',
  );

  /// en: '(one) {{n} subdir} (other) {{n} subdirs}'
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} subdir',
        other: '${n} subdirs',
      );

  /// en: '{path}, {adds} added, {dels} deleted'
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} added, ${dels} deleted';

  /// en: '(one) {{n} file, {adds} added, {dels} deleted} (other) {{n} files, {adds} added, {dels} deleted}'
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one: '${n} file, ${adds} added, ${dels} deleted',
    other: '${n} files, ${adds} added, ${dels} deleted',
  );

  /// en: '(one) {{n} hunk} (other) {{n} hunks}'
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} hunk',
        other: '${n} hunks',
      );

  /// en: 'largest change in this view'
  String get largestChangeInView => 'largest change in this view';

  /// en: 'conflicted'
  String get conflictedTag => 'conflicted';

  /// en: 'dirty'
  String get dirtyTag => 'dirty';

  /// en: 'drill in'
  String get drillInTag => 'drill in';

  /// en: 'renamed'
  String get changeTypeRenamed => 'renamed';

  /// en: 'copied'
  String get changeTypeCopied => 'copied';

  /// en: 'typechange'
  String get changeTypeTypechange => 'typechange';

  /// en: 'conflict'
  String get changeTypeConflict => 'conflict';

  /// en: 'core file'
  String get coreFile => 'core file';

  /// en: 'stale'
  String get staleFile => 'stale';

  /// en: 'filter path'
  String get filterPathHint => 'filter path';

  /// en: 'esc'
  String get escHint => 'esc';
}

// Path: history.worldline
class Translations$history$worldline$en {
  Translations$history$worldline$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Close worldline'
  String get closeWorldline => 'Close worldline';

  /// en: 'Drag to open worldline'
  String get dragToOpenWorldline => 'Drag to open worldline';
}

// Path: history.contextMenu
class Translations$history$contextMenu$en {
  Translations$history$contextMenu$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'current branch'
  String get currentBranchFallback => 'current branch';

  /// en: 'Apply commit's changes onto {branch}'
  String applyCommitOnto({required Object branch}) =>
      'Apply commit\'s changes onto ${branch}';

  /// en: 'Revert commit's changes on {branch}'
  String revertCommitOn({required Object branch}) =>
      'Revert commit\'s changes on ${branch}';
}

// Path: history.cherryPick
class Translations$history$cherryPick$en {
  Translations$history$cherryPick$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Cherry-pick paused. Finish the remaining conflicts on the Changes page.'
  String get paused =>
      'Cherry-pick paused. Finish the remaining conflicts on the Changes page.';

  /// en: 'Cherry-pick failed: {error}'
  String failed({required Object error}) => 'Cherry-pick failed: ${error}';

  /// en: 'Cherry-picked {short} (resolved conflicts)'
  String pickedResolved({required Object short}) =>
      'Cherry-picked ${short} (resolved conflicts)';

  /// en: 'Cherry-picked {short}'
  String picked({required Object short}) => 'Cherry-picked ${short}';
}

// Path: history.revert
class Translations$history$revert$en {
  Translations$history$revert$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Revert paused. Finish the remaining conflicts on the Changes page.'
  String get paused =>
      'Revert paused. Finish the remaining conflicts on the Changes page.';

  /// en: 'Revert failed: {error}'
  String failed({required Object error}) => 'Revert failed: ${error}';

  /// en: 'Reverted {short} (resolved conflicts)'
  String revertedResolved({required Object short}) =>
      'Reverted ${short} (resolved conflicts)';

  /// en: 'Reverted {short}'
  String reverted({required Object short}) => 'Reverted ${short}';
}

// Path: history.reflog
class Translations$history$reflog$en {
  Translations$history$reflog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Create branch from here…'
  String get createBranchFromHere => 'Create branch from here…';

  /// en: 'Copy commit hash'
  String get copyCommitHash => 'Copy commit hash';

  /// en: 'Create branch from reflog entry'
  String get createBranchDialogTitle => 'Create branch from reflog entry';

  /// en: 'Anchor: {short} · {summary}'
  String anchorLine({required Object short, required Object summary}) =>
      'Anchor: ${short}  ·  ${summary}';

  /// en: 'branch name'
  String get branchNameHint => 'branch name';

  /// en: 'Create'
  String get createAction => 'Create';

  /// en: 'Failed to create branch: {error}'
  String createBranchFailed({required Object error}) =>
      'Failed to create branch: ${error}';

  /// en: 'Branch "{name}" created at {short}.'
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branch "${name}" created at ${short}.';
}

// Path: history.rebase
class Translations$history$rebase$en {
  Translations$history$rebase$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'First commit cannot be {action}'
  String firstCommitCannotBe({required Object action}) =>
      'First commit cannot be ${action}';

  /// en: '(one) {Rebase {n} commit} (other) {Rebase {n} commits}'
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Rebase ${n} commit',
        other: 'Rebase ${n} commits',
      );

  /// en: 'reset'
  String get resetLabel => 'reset';

  /// en: 'drag to reorder, pick action per commit'
  String get dragToReorderHint => 'drag to reorder, pick action per commit';

  /// en: 'new message'
  String get newMessageHint => 'new message';

  /// en: '…'
  String get runningEllipsis => '…';

  /// en: 'Start Rebase'
  String get startRebase => 'Start Rebase';
}

// Path: history.inFlight
class Translations$history$inFlight$en {
  Translations$history$inFlight$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'IN FLIGHT'
  String get header => 'IN FLIGHT';

  /// en: 'desk'
  String get deskFallbackLabel => 'desk';
}

// Path: historySurgery.chrome
class Translations$historySurgery$chrome$en {
  Translations$historySurgery$chrome$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'History Surgery'
  String get title => 'History Surgery';

  /// en: 'alpha'
  String get alphaBadge => 'alpha';

  /// en: 'DRY RUN'
  String get dryRunBadge => 'DRY RUN';
}

// Path: historySurgery.select
class Translations$historySurgery$select$en {
  Translations$historySurgery$select$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Select files to remove from history'
  String get prompt => 'Select files to remove from history';

  /// en: '{n} selected'
  String selectedCount({required Object n}) => '${n} selected';

  /// en: 'search...'
  String get searchHint => 'search...';

  /// en: 'reading tree...'
  String get readingTree => 'reading tree...';

  /// en: 'select files to continue'
  String get continueDisabled => 'select files to continue';

  /// en: 'continue →'
  String get continueEnabled => 'continue →';

  /// en: '{n} to purge'
  String toPurgeCount({required Object n}) => '${n} to purge';

  /// en: 'analyzing...'
  String get analyzing => 'analyzing...';

  /// en: 'low risk'
  String get riskLow => 'low risk';

  /// en: 'moderate risk'
  String get riskModerate => 'moderate risk';

  /// en: 'high risk'
  String get riskHigh => 'high risk';

  /// en: 'commits'
  String get impactCommitsLabel => 'commits';

  /// en: 'branches'
  String get impactBranchesLabel => 'branches';

  /// en: 'worktrees'
  String get impactWorktreesLabel => 'worktrees';

  /// en: 'coupling'
  String get impactCouplingLabel => 'coupling';

  /// en: 'island'
  String get impactCouplingIsland => 'island';

  /// en: '{n} neighbors'
  String impactCouplingNeighbors({required Object n}) => '${n} neighbors';

  /// en: '← {path}'
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class Translations$historySurgery$understand$en {
  Translations$historySurgery$understand$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'How this works'
  String get heading => 'How this works';

  /// en: 'Backup'
  String get backupTitle => 'Backup';

  /// en: 'Every branch and tag ref is copied to a backup namespace before anything changes. If something goes wrong, one click restores the original state.'
  String get backupBody =>
      'Every branch and tag ref is copied to a backup namespace before anything changes. If something goes wrong, one click restores the original state.';

  /// en: 'Rewrite'
  String get rewriteTitle => 'Rewrite';

  /// en: 'Each commit is walked from root to tip. For every commit that contains the target files, a new commit is created with those files removed from the tree. Parent chains are remapped to preserve topology. '
  String get rewriteBody =>
      'Each commit is walked from root to tip. For every commit that contains the target files, a new commit is created with those files removed from the tree. Parent chains are remapped to preserve topology. ';

  /// en: '{affected} of {total} commits will be rewritten.'
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} of ${total} commits will be rewritten.';

  /// en: 'Update refs'
  String get updateRefsTitle => 'Update refs';

  /// en: 'Branch and tag pointers are moved to the new commit SHAs. The old objects still exist until garbage collection. '
  String get updateRefsBody =>
      'Branch and tag pointers are moved to the new commit SHAs. The old objects still exist until garbage collection. ';

  /// en: 'Your {n} worktree(s) will need re-checkout.'
  String worktreesNeedRecheckout({required Object n}) =>
      'Your ${n} worktree(s) will need re-checkout.';

  /// en: 'No worktrees are affected.'
  String get noWorktreesAffected => 'No worktrees are affected.';

  /// en: 'Force-push'
  String get forcePushTitle => 'Force-push';

  /// en: 'After verifying the purge, you choose which branches to force-push. Uses --force-with-lease so it fails safely if someone else pushed in the meantime.'
  String get forcePushBody =>
      'After verifying the purge, you choose which branches to force-push. Uses --force-with-lease so it fails safely if someone else pushed in the meantime.';

  /// en: 'Unlike filter-repo or BFG, this runs entirely through git plumbing commands (cat-file, mktree, commit-tree, update-ref). No external dependencies. Rename tracking follows one chain per file — if a file was copied and both copies renamed independently, verify the purge result after execution.'
  String get plumbingNote =>
      'Unlike filter-repo or BFG, this runs entirely through git plumbing commands (cat-file, mktree, commit-tree, update-ref). No external dependencies. Rename tracking follows one chain per file — if a file was copied and both copies renamed independently, verify the purge result after execution.';

  /// en: '← Back'
  String get back => '← Back';

  /// en: 'I understand, continue →'
  String get continueLabel => 'I understand, continue →';
}

// Path: historySurgery.confirm
class Translations$historySurgery$confirm$en {
  Translations$historySurgery$confirm$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{n} commits will be rewritten'
  String commitsRewritten({required Object n}) =>
      '${n} commits will be rewritten';

  /// en: 'Force-push will be required for remote branches'
  String get forcePushRequired =>
      'Force-push will be required for remote branches';

  /// en: '{n} worktrees will need re-checkout'
  String worktreesRecheckout({required Object n}) =>
      '${n} worktrees will need re-checkout';

  /// en: '{n} stashes may become invalid'
  String stashesInvalid({required Object n}) =>
      '${n} stashes may become invalid';

  /// en: 'This operation rewrites git history'
  String get heading => 'This operation rewrites git history';

  /// en: 'It cannot be automatically undone after force-pushing.'
  String get subheading =>
      'It cannot be automatically undone after force-pushing.';

  /// en: 'type {word}'
  String typeHint({required Object word}) => 'type ${word}';

  /// en: 'Go Back'
  String get goBack => 'Go Back';

  /// en: 'Begin Surgery'
  String get begin => 'Begin Surgery';
}

// Path: historySurgery.execute
class Translations$historySurgery$execute$en {
  Translations$historySurgery$execute$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Preparing...'
  String get preparing => 'Preparing...';

  /// en: 'Backing up refs...'
  String get backingUpRefs => 'Backing up refs...';

  /// en: 'Rewriting commits...'
  String get rewritingCommits => 'Rewriting commits...';

  /// en: 'Updating refs...'
  String get updatingRefs => 'Updating refs...';
}

// Path: historySurgery.verify
class Translations$historySurgery$verify$en {
  Translations$historySurgery$verify$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Surgery Complete'
  String get complete => 'Surgery Complete';

  /// en: 'Surgery Failed'
  String get failed => 'Surgery Failed';

  /// en: 'Commits rewritten'
  String get commitsRewrittenLabel => 'Commits rewritten';

  /// en: 'Refs updated'
  String get refsUpdatedLabel => 'Refs updated';

  /// en: 'Old HEAD'
  String get oldHeadLabel => 'Old HEAD';

  /// en: 'New HEAD'
  String get newHeadLabel => 'New HEAD';

  /// en: 'Purge verified'
  String get purgeVerifiedLabel => 'Purge verified';

  /// en: 'clean'
  String get purgeClean => 'clean';

  /// en: 'TRACES REMAIN'
  String get purgeTracesRemain => 'TRACES REMAIN';

  /// en: 'Displaced Worktrees'
  String get displacedWorktrees => 'Displaced Worktrees';

  /// en: 'Undo Surgery'
  String get undoSurgery => 'Undo Surgery';

  /// en: 'Rolled back to backup refs.'
  String get rolledBack => 'Rolled back to backup refs.';

  /// en: 'Done'
  String get done => 'Done';
}

// Path: historySurgery.forcePush
class Translations$historySurgery$forcePush$en {
  Translations$historySurgery$forcePush$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'pushing...'
  String get pushing => 'pushing...';

  /// en: 'Force Push All'
  String get forcePushAll => 'Force Push All';

  /// en: 'confirm push'
  String get confirmPush => 'confirm push';

  /// en: 'cancel'
  String get cancel => 'cancel';
}

// Path: onboarding.nav
class Translations$onboarding$nav$en {
  Translations$onboarding$nav$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Back'
  String get back => 'Back';

  /// en: 'Continue'
  String get continueLabel => 'Continue';

  /// en: 'Let's go'
  String get letsGo => 'Let\'s go';
}

// Path: onboarding.naming
class Translations$onboarding$naming$en {
  Translations$onboarding$naming$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'what is this to you?'
  String get question => 'what is this to you?';

  /// en: 'this'
  String get questionEmphasis => 'this';

  /// en: 'I am '
  String get iAmPrefix => 'I am ';

  /// en: ' , your personal Git Client.'
  String get iAmSuffix => ' , your personal Git Client.';
}

// Path: onboarding.theme
class Translations$onboarding$theme$en {
  Translations$onboarding$theme$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'dress {name} up.'
  String title({required Object name}) => 'dress ${name} up.';

  /// en: 'THEMES'
  String get themesHeader => 'THEMES';

  /// en: 'KEYBINDINGS'
  String get keybindingsHeader => 'KEYBINDINGS';

  /// en: 'preview'
  String get previewBadge => 'preview';

  /// en: 'use defaults'
  String get useDefaults => 'use defaults';
}

// Path: onboarding.repo
class Translations$onboarding$repo$en {
  Translations$onboarding$repo$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'point {name} at something.'
  String title({required Object name}) => 'point ${name} at something.';

  /// en: 'i'll do this later'
  String get later => 'i\'ll do this later';

  late final Translations$onboarding$repo$doors$en doors =
      Translations$onboarding$repo$doors$en.internal(_root);
  late final Translations$onboarding$repo$cloneForm$en cloneForm =
      Translations$onboarding$repo$cloneForm$en.internal(_root);
  late final Translations$onboarding$repo$pickers$en pickers =
      Translations$onboarding$repo$pickers$en.internal(_root);
  late final Translations$onboarding$repo$errors$en errors =
      Translations$onboarding$repo$errors$en.internal(_root);
}

// Path: onboarding.preview
class Translations$onboarding$preview$en {
  Translations$onboarding$preview$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$onboarding$preview$panels$en panels =
      Translations$onboarding$preview$panels$en.internal(_root);
  late final Translations$onboarding$preview$sidebar$en sidebar =
      Translations$onboarding$preview$sidebar$en.internal(_root);
  late final Translations$onboarding$preview$changes$en changes =
      Translations$onboarding$preview$changes$en.internal(_root);
  late final Translations$onboarding$preview$history$en history =
      Translations$onboarding$preview$history$en.internal(_root);
  late final Translations$onboarding$preview$branches$en branches =
      Translations$onboarding$preview$branches$en.internal(_root);
  late final Translations$onboarding$preview$diff$en diff =
      Translations$onboarding$preview$diff$en.internal(_root);
}

// Path: orrery.header
class Translations$orrery$header$en {
  Translations$orrery$header$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Orrery'
  String get title => 'Orrery';

  /// en: 'Scrub'
  String get modeScrub => 'Scrub';

  /// en: 'Compare'
  String get modeCompare => 'Compare';

  /// en: 'Modules'
  String get lodModules => 'Modules';

  /// en: 'Files'
  String get lodFiles => 'Files';
}

// Path: orrery.status
class Translations$orrery$status$en {
  Translations$orrery$status$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Tracing the manifold through history…'
  String get loading => 'Tracing the manifold through history…';

  /// en: 'Could not read this repo’s history.'
  String get loadError => 'Could not read this repo’s history.';

  /// en: 'Not enough history yet to plot a trajectory.'
  String get notEnoughHistory => 'Not enough history yet to plot a trajectory.';

  /// en: 'The Orrery needs a few commits to chart.'
  String get notEnoughHistoryDetail =>
      'The Orrery needs a few commits to chart.';
}

// Path: orrery.legend
class Translations$orrery$legend$en {
  Translations$orrery$legend$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'central'
  String get central => 'central';

  /// en: 'peripheral'
  String get peripheral => 'peripheral';
}

// Path: orrery.node
class Translations$orrery$node$en {
  Translations$orrery$node$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'module'
  String get module => 'module';

  /// en: '{path} · {n} files'
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} files';

  /// en: 'file #{id}'
  String fileFallback({required Object id}) => 'file #${id}';

  /// en: 'node #{id}'
  String nodeFallback({required Object id}) => 'node #${id}';

  /// en: '(root)'
  String get rootModule => '(root)';
}

// Path: orrery.milestone
class Translations$orrery$milestone$en {
  Translations$orrery$milestone$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'genesis'
  String get genesis => 'genesis';

  /// en: 'now'
  String get now => 'now';

  /// en: 'reorganized'
  String get reorganized => 'reorganized';

  /// en: 'became {archetype}'
  String becameArchetype({required Object archetype}) => 'became ${archetype}';

  /// en: 'snapshot'
  String get snapshot => 'snapshot';
}

// Path: orrery.structure
class Translations$orrery$structure$en {
  Translations$orrery$structure$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'forming…'
  String get forming => 'forming…';

  /// en: 'canonical'
  String get canonical => 'canonical';

  /// en: 'connectivity'
  String get connectivity => 'connectivity';

  /// en: 'rigidity'
  String get rigidity => 'rigidity';

  /// en: 'entropy'
  String get entropy => 'entropy';
}

// Path: orrery.rail
class Translations$orrery$rail$en {
  Translations$orrery$rail$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'STRUCTURE'
  String get structureLabel => 'STRUCTURE';

  /// en: 'FIELD'
  String get fieldLabel => 'FIELD';

  /// en: 'FINDINGS'
  String get findingsLabel => 'FINDINGS';

  /// en: 'SELECTED'
  String get selectedLabel => 'SELECTED';

  /// en: 'No structural events detected in this history.'
  String get noFindings => 'No structural events detected in this history.';
}

// Path: orrery.selection
class Translations$orrery$selection$en {
  Translations$orrery$selection$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Not present at this point in history.'
  String get notPresent => 'Not present at this point in history.';

  /// en: 'Coupling-central — changes here ripple across the system.'
  String get roleCentral =>
      'Coupling-central — changes here ripple across the system.';

  /// en: 'Peripheral — loosely coupled, mostly changes on its own.'
  String get rolePeripheral =>
      'Peripheral — loosely coupled, mostly changes on its own.';

  /// en: 'Mid-structure — moderately coupled.'
  String get roleMid => 'Mid-structure — moderately coupled.';

  /// en: ' Drifting outward — decoupling.'
  String get driftOutward => ' Drifting outward — decoupling.';

  /// en: ' Drifting inward — integrating.'
  String get driftInward => ' Drifting inward — integrating.';

  /// en: ' Holding its position.'
  String get driftHolding => ' Holding its position.';
}

// Path: orrery.findingKind
class Translations$orrery$findingKind$en {
  Translations$orrery$findingKind$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'HUB'
  String get hub => 'HUB';

  /// en: 'DRIFTING OUT'
  String get driftOut => 'DRIFTING OUT';

  /// en: 'DRIFTING IN'
  String get driftIn => 'DRIFTING IN';

  /// en: 'TANGLING'
  String get tangle => 'TANGLING';

  /// en: 'CLARIFYING'
  String get clarify => 'CLARIFYING';

  /// en: 'REORG'
  String get regime => 'REORG';

  /// en: 'THRASHING'
  String get thrash => 'THRASHING';

  /// en: 'RESHUFFLE'
  String get reshuffle => 'RESHUFFLE';

  /// en: 'FORECAST'
  String get forecast => 'FORECAST';
}

// Path: orrery.findings
class Translations$orrery$findings$en {
  Translations$orrery$findings$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Connectivity has been falling and is near its lowest — if this holds, the codebase is heading toward splitting into loosely-coupled halves. Decide now whether that’s the intent.'
  String get forecastSplit =>
      'Connectivity has been falling and is near its lowest — if this holds, the codebase is heading toward splitting into loosely-coupled halves. Decide now whether that’s the intent.';

  /// en: 'Connectivity has been climbing toward its peak — if this holds, the codebase is consolidating into one tightly-coupled mass. Watch for it hardening into a monolith.'
  String get forecastConsolidate =>
      'Connectivity has been climbing toward its peak — if this holds, the codebase is consolidating into one tightly-coupled mass. Watch for it hardening into a monolith.';

  /// en: '{name} keeps getting reorganised back and forth — lots of structural churn, little net movement. Settle its coupling or stop touching it.'
  String thrash({required Object name}) =>
      '${name} keeps getting reorganised back and forth — lots of structural churn, little net movement. Settle its coupling or stop touching it.';

  /// en: 'This commit looked routine but quietly moved which files are central — the overall shape held while the structure reshuffled underneath. Review it carefully.'
  String get reshuffle =>
      'This commit looked routine but quietly moved which files are central — the overall shape held while the structure reshuffled underneath. Review it carefully.';

  /// en: '{name} sits at the structural core — the system reorganises around it. Treat changes here as high blast-radius.'
  String hub({required Object name}) =>
      '${name} sits at the structural core — the system reorganises around it. Treat changes here as high blast-radius.';

  /// en: '{name} has drifted from the core toward the edge — it’s decoupling from the system. Either it’s being retired, or it’s quietly rotting.'
  String driftOut({required Object name}) =>
      '${name} has drifted from the core toward the edge — it’s decoupling from the system. Either it’s being retired, or it’s quietly rotting.';

  /// en: '{name} has migrated toward the core — it’s becoming load-bearing. Make sure it’s well-tested before more depends on it.'
  String driftIn({required Object name}) =>
      '${name} has migrated toward the core — it’s becoming load-bearing. Make sure it’s well-tested before more depends on it.';

  /// en: 'The codebase reorganized sharply here — its connectivity jumped. Review what split off or merged.'
  String get regime =>
      'The codebase reorganized sharply here — its connectivity jumped. Review what split off or merged.';

  /// en: 'Over its history the codebase has trended toward a more tangled structure — its connectivity is getting denser and less modular.'
  String get tangleTrend =>
      'Over its history the codebase has trended toward a more tangled structure — its connectivity is getting denser and less modular.';

  /// en: 'Over its history the codebase has trended toward a cleaner structure — it’s separating into clearer modules.'
  String get clarifyTrend =>
      'Over its history the codebase has trended toward a cleaner structure — it’s separating into clearer modules.';
}

// Path: orrery.anchor
class Translations$orrery$anchor$en {
  Translations$orrery$anchor$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'core'
  String get core => 'core';

  /// en: 'drift'
  String get drift => 'drift';

  /// en: 'trend'
  String get trend => 'trend';

  /// en: 'thrash'
  String get thrash => 'thrash';
}

// Path: orrery.compare
class Translations$orrery$compare$en {
  Translations$orrery$compare$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'A → B'
  String get header => 'A → B';

  /// en: 'CHANGE'
  String get change => 'CHANGE';

  /// en: 'MOVERS'
  String get movers => 'MOVERS';

  /// en: 'No files moved between these frames.'
  String get noMovers => 'No files moved between these frames.';

  /// en: 'A'
  String get badgeA => 'A';

  /// en: 'B'
  String get badgeB => 'B';

  /// en: 'files'
  String get deltaFiles => 'files';

  /// en: 'connectivity'
  String get deltaConnectivity => 'connectivity';

  /// en: 'rigidity'
  String get deltaRigidity => 'rigidity';

  /// en: 'entropy'
  String get deltaEntropy => 'entropy';

  /// en: 'outward'
  String get wayOutward => 'outward';

  /// en: 'inward'
  String get wayInward => 'inward';

  /// en: 'shifted'
  String get wayShifted => 'shifted';
}

// Path: palette.prefixes
class Translations$palette$prefixes$en {
  Translations$palette$prefixes$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'ask: [question]'
  String get askHint => 'ask: [question]';

  /// en: 'near: [file]'
  String get nearHint => 'near: [file]';

  /// en: 'who: [file]'
  String get whoHint => 'who: [file]';

  /// en: 'log: [message]'
  String get logHint => 'log: [message]';

  /// en: 'run: [tool]'
  String get runHint => 'run: [tool]';

  /// en: 'Ask {name}: {body}'
  String askLabel({required Object name, required Object body}) =>
      'Ask ${name}: ${body}';

  /// en: '{path} · φ={phi}'
  String nearSubtitle({required Object path, required Object phi}) =>
      '${path} · φ=${phi}';

  /// en: '{name} — {reviewers}'
  String whoReviewersLabel({required Object name, required Object reviewers}) =>
      '${name} — ${reviewers}';

  /// en: '{path} · {count} reviewers · {touches} touches'
  String whoReviewersSubtitle({
    required Object path,
    required Object count,
    required Object touches,
  }) => '${path} · ${count} reviewers · ${touches} touches';

  /// en: '{name} — {touches} touches'
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} touches';

  /// en: '{path} · no reviewers recorded'
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · no reviewers recorded';
}

// Path: palette.chips
class Translations$palette$chips$en {
  Translations$palette$chips$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'AI'
  String get ai => 'AI';

  /// en: 'NEAR'
  String get near => 'NEAR';

  /// en: 'WHO'
  String get who => 'WHO';

  /// en: 'TERM'
  String get term => 'TERM';

  /// en: 'GUI'
  String get gui => 'GUI';

  /// en: 'DEV'
  String get dev => 'DEV';

  /// en: 'DEBUG'
  String get debug => 'DEBUG';

  /// en: 'ALPHA'
  String get alpha => 'ALPHA';

  /// en: 'HOT'
  String get hot => 'HOT';

  /// en: 'KEY'
  String get key => 'KEY';

  /// en: 'WEB'
  String get web => 'WEB';

  /// en: 'SYS'
  String get sys => 'SYS';

  /// en: 'CLIP'
  String get clip => 'CLIP';

  /// en: 'SYNC'
  String get sync => 'SYNC';

  /// en: 'FORCE'
  String get force => 'FORCE';

  /// en: 'PR'
  String get pr => 'PR';

  /// en: 'DRAFT'
  String get draft => 'DRAFT';

  /// en: 'UNDO'
  String get undo => 'UNDO';

  /// en: 'THM'
  String get thm => 'THM';

  /// en: 'VER'
  String get ver => 'VER';

  /// en: 'DESK'
  String get desk => 'DESK';

  /// en: 'DET'
  String get det => 'DET';

  /// en: 'MAIN'
  String get main => 'MAIN';

  /// en: 'HEAD'
  String get head => 'HEAD';

  /// en: 'GONE'
  String get gone => 'GONE';

  /// en: 'REMOTE'
  String get remote => 'REMOTE';

  /// en: 'LOCAL'
  String get local => 'LOCAL';

  /// en: 'AN'
  String get an => 'AN';

  /// en: 'LW'
  String get lw => 'LW';
}

// Path: palette.predictive
class Translations$palette$predictive$en {
  Translations$palette$predictive$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{percent}% momentum'
  String momentumSuffix({required Object percent}) => '${percent}% momentum';
}

// Path: palette.topTouched
class Translations$palette$topTouched$en {
  Translations$palette$topTouched$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{count} touches · {path}'
  String subtitle({required Object count, required Object path}) =>
      '${count} touches · ${path}';
}

// Path: palette.coherence
class Translations$palette$coherence$en {
  Translations$palette$coherence$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Staged coherence: {percent}%'
  String label({required Object percent}) => 'Staged coherence: ${percent}%';

  /// en: '{count} files'
  String subtitle({required Object count}) => '${count} files';
}

// Path: palette.keystone
class Translations$palette$keystone$en {
  Translations$palette$keystone$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{path} · keystone {score}'
  String subtitle({required Object path, required Object score}) =>
      '${path} · keystone ${score}';
}

// Path: palette.repoSub
class Translations$palette$repoSub$en {
  Translations$palette$repoSub$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Changes in {name}'
  String changes({required Object name}) => 'Changes in ${name}';

  /// en: 'History in {name}'
  String history({required Object name}) => 'History in ${name}';

  /// en: 'Branches in {name}'
  String branches({required Object name}) => 'Branches in ${name}';

  /// en: 'Terminal in {name}'
  String terminal({required Object name}) => 'Terminal in ${name}';

  /// en: 'Generate Commit · {name}'
  String generateCommit({required Object name}) => 'Generate Commit · ${name}';

  /// en: 'Review Changes in {name}'
  String reviewChanges({required Object name}) => 'Review Changes in ${name}';

  /// en: 'Muse in {name}'
  String muse({required Object name}) => 'Muse in ${name}';
}

// Path: palette.desks
class Translations$palette$desks$en {
  Translations$palette$desks$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'main worktree'
  String get mainWorktree => 'main worktree';

  /// en: 'detached'
  String get detached => 'detached';

  /// en: '{count} dirty'
  String dirty({required Object count}) => '${count} dirty';
}

// Path: palette.actions
class Translations$palette$actions$en {
  Translations$palette$actions$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Open in Browser'
  String get openInBrowser => 'Open in Browser';

  /// en: 'Terminal'
  String get terminal => 'Terminal';

  /// en: 'Reveal in Files'
  String get revealInFiles => 'Reveal in Files';

  /// en: 'Copy Path'
  String get copyPath => 'Copy Path';

  /// en: 'Copy Branch'
  String get copyBranch => 'Copy Branch';
}

// Path: palette.tools
class Translations$palette$tools$en {
  Translations$palette$tools$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Launch {label}'
  String launch({required Object label}) => 'Launch ${label}';
}

// Path: palette.gitCommands
class Translations$palette$gitCommands$en {
  Translations$palette$gitCommands$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Fetch'
  String get fetch => 'Fetch';

  /// en: 'Pull'
  String get pull => 'Pull';

  /// en: '{count} behind'
  String pullBehind({required Object count}) => '${count} behind';

  /// en: '{behind} {upstream}'
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';

  /// en: 'Push'
  String get push => 'Push';

  /// en: '(one) {{n} commit} (other) {{n} commits}'
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} commit',
        other: '${n} commits',
      );

  /// en: '{commits} to {upstream}'
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} to ${upstream}';

  /// en: 'Force Push'
  String get forcePush => 'Force Push';

  /// en: 'Cannot force-push: no upstream set for {branch}.'
  String forcePushNoUpstream({required Object branch}) =>
      'Cannot force-push: no upstream set for ${branch}.';

  /// en: 'Commit'
  String get commit => 'Commit';

  /// en: 'Stage All'
  String get stageAll => 'Stage All';

  /// en: 'Unstage All'
  String get unstageAll => 'Unstage All';

  /// en: 'Discard All'
  String get discardAll => 'Discard All';

  /// en: 'Create Branch'
  String get createBranch => 'Create Branch';

  /// en: 'Delete Branch'
  String get deleteBranch => 'Delete Branch';

  /// en: 'Rename Branch'
  String get renameBranch => 'Rename Branch';

  /// en: 'Stash'
  String get stash => 'Stash';

  /// en: 'Stash Pop'
  String get stashPop => 'Stash Pop';

  /// en: 'Stash Apply'
  String get stashApply => 'Stash Apply';

  /// en: 'Stash Drop'
  String get stashDrop => 'Stash Drop';

  /// en: 'Create Tag'
  String get createTag => 'Create Tag';

  /// en: 'Cherry-pick'
  String get cherryPick => 'Cherry-pick';

  /// en: 'Revert'
  String get revert => 'Revert';

  /// en: 'Stash applied with conflicts. Resolve them on the Changes page.'
  String get stashConflictMessage =>
      'Stash applied with conflicts. Resolve them on the Changes page.';
}

// Path: palette.pr
class Translations$palette$pr$en {
  Translations$palette$pr$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Create PR'
  String get create => 'Create PR';

  /// en: 'Merge PR'
  String get merge => 'Merge PR';

  /// en: 'Mark PR Ready'
  String get markReady => 'Mark PR Ready';
}

// Path: palette.ai
class Translations$palette$ai$en {
  Translations$palette$ai$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Generate Commit'
  String get generateCommit => 'Generate Commit';

  /// en: 'Review Changes'
  String get reviewChanges => 'Review Changes';

  /// en: 'Run Muse'
  String get runMuse => 'Run Muse';

  /// en: 'Debug {name}'
  String debugRepo({required Object name}) => 'Debug ${name}';

  /// en: 'describe a symptom'
  String get describeSymptom => 'describe a symptom';

  /// en: 'View {kind}'
  String viewResult({required Object kind}) => 'View ${kind}';

  /// en: 'unseen result'
  String get unseenResult => 'unseen result';

  /// en: 'AI: {kind}…'
  String runningResult({required Object kind}) => 'AI: ${kind}…';

  /// en: 'running'
  String get running => 'running';

  /// en: 'Commit Message'
  String get kindCommitMessage => 'Commit Message';

  /// en: 'Code Review'
  String get kindCodeReview => 'Code Review';

  /// en: 'Muse Result'
  String get kindMuseResult => 'Muse Result';

  /// en: 'Presentation'
  String get kindPresentation => 'Presentation';

  /// en: 'Debug Result'
  String get kindDebugResult => 'Debug Result';
}

// Path: palette.undo
class Translations$palette$undo$en {
  Translations$palette$undo$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Cancel: {label}'
  String cancel({required Object label}) => 'Cancel: ${label}';
}

// Path: palette.navigation
class Translations$palette$navigation$en {
  Translations$palette$navigation$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Changes'
  String get changes => 'Changes';

  /// en: 'History'
  String get history => 'History';

  /// en: 'Branches'
  String get branches => 'Branches';

  /// en: 'X-Ray'
  String get xray => 'X-Ray';

  /// en: 'Settings'
  String get settings => 'Settings';

  /// en: 'Refresh'
  String get refresh => 'Refresh';
}

// Path: palette.settings
class Translations$palette$settings$en {
  Translations$palette$settings$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Reduce Motion'
  String get reduceMotion => 'Reduce Motion';

  /// en: 'Animate Logo Unfocused'
  String get animateLogoUnfocused => 'Animate Logo Unfocused';

  /// en: 'Instant Blame Hover'
  String get instantBlameHover => 'Instant Blame Hover';

  /// en: 'Auto-select Changes'
  String get autoSelectChanges => 'Auto-select Changes';

  /// en: 'Fetch Online Issues'
  String get fetchOnlineIssues => 'Fetch Online Issues';

  /// en: 'Remember Work in Progress'
  String get rememberWip => 'Remember Work in Progress';

  /// en: 'Hide AI Features'
  String get hideAiFeatures => 'Hide AI Features';

  /// en: 'Crash Reporting'
  String get crashReporting => 'Crash Reporting';

  /// en: 'AI Read-only'
  String get aiReadOnly => 'AI Read-only';

  /// en: 'Stash Cabinet Expanded'
  String get stashCabinetExpanded => 'Stash Cabinet Expanded';

  /// en: 'File Sort Inverted'
  String get fileSortInverted => 'File Sort Inverted';
}

// Path: palette.info
class Translations$palette$info$en {
  Translations$palette$info$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Manifold {version}'
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class Translations$palette$debug$en {
  Translations$palette$debug$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Engine Status'
  String get engineStatus => 'Engine Status';

  /// en: 'LogosGit spectral engine diagnostics'
  String get engineStatusSubtitle => 'LogosGit spectral engine diagnostics';

  /// en: 'File Coupling'
  String get fileCoupling => 'File Coupling';

  /// en: 'Nearest co-change neighbors for staged files'
  String get fileCouplingSubtitle =>
      'Nearest co-change neighbors for staged files';

  /// en: 'Theme Specimen'
  String get themeSpecimen => 'Theme Specimen';

  /// en: 'All colors, icons, text tiers, and geometry'
  String get themeSpecimenSubtitle =>
      'All colors, icons, text tiers, and geometry';
}

// Path: palette.dev
class Translations$palette$dev$en {
  Translations$palette$dev$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Test Merge Editor'
  String get testMergeEditor => 'Test Merge Editor';

  /// en: 'Test History Surgery'
  String get testHistorySurgery => 'Test History Surgery';

  /// en: 'back'
  String get back => 'back';

  /// en: 'cancel'
  String get cancel => 'cancel';

  /// en: 'building test conflicts from history…'
  String get buildingConflicts => 'building test conflicts from history…';
}

// Path: palette.historySurgery
class Translations$palette$historySurgery$en {
  Translations$palette$historySurgery$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'History Surgery'
  String get label => 'History Surgery';

  /// en: 'Rewrite history to permanently remove files'
  String get subtitle => 'Rewrite history to permanently remove files';
}

// Path: palette.orrery
class Translations$palette$orrery$en {
  Translations$palette$orrery$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Orrery'
  String get label => 'Orrery';

  /// en: 'Scrub the repo’s structural history through the manifold'
  String get subtitle =>
      'Scrub the repo’s structural history through the manifold';
}

// Path: palette.command
class Translations$palette$command$en {
  Translations$palette$command$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{label} complete'
  String complete({required Object label}) => '${label} complete';

  /// en: '{label} failed: {message}'
  String failed({required Object label, required Object message}) =>
      '${label} failed: ${message}';

  /// en: 'Copy'
  String get copy => 'Copy';
}

// Path: palette.search
class Translations$palette$search$en {
  Translations$palette$search$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'search everything...'
  String get hintDefault => 'search everything...';

  /// en: 'elevated — all actions'
  String get hintElevated => 'elevated — all actions';

  /// en: 'type to search'
  String get emptyTypeToSearch => 'type to search';

  /// en: 'no results'
  String get emptyNoResults => 'no results';
}

// Path: palette.wick
class Translations$palette$wick$en {
  Translations$palette$wick$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'wick'
  String get label => 'wick';

  /// en: 'coupled'
  String get coupledFallback => 'coupled';
}

// Path: palette.gitCache
class Translations$palette$gitCache$en {
  Translations$palette$gitCache$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'current'
  String get current => 'current';

  /// en: 'staged'
  String get staged => 'staged';

  /// en: 'modified'
  String get modified => 'modified';
}

// Path: releaseNotes.about
class Translations$releaseNotes$about$en {
  Translations$releaseNotes$about$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$releaseNotes$about$whyFlutter$en whyFlutter =
      Translations$releaseNotes$about$whyFlutter$en.internal(_root);
  late final Translations$releaseNotes$about$spectralEngine$en spectralEngine =
      Translations$releaseNotes$about$spectralEngine$en.internal(_root);
  late final Translations$releaseNotes$about$whereGoing$en whereGoing =
      Translations$releaseNotes$about$whereGoing$en.internal(_root);
}

// Path: releaseNotes.legal
class Translations$releaseNotes$legal$en {
  Translations$releaseNotes$legal$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '© 2026 Woflo Labs'
  String get copyright => '© 2026 Woflo Labs';

  /// en: 'GPL-3.0-or-later · WLCSL community-source research core · no warranty'
  String get license =>
      'GPL-3.0-or-later · WLCSL community-source research core · no warranty';
}

// Path: repoSummary.backbone
class Translations$repoSummary$backbone$en {
  Translations$repoSummary$backbone$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '`{path}` ({lines}) — {region}'
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';

  /// en: '(one) {{n} line} (other) {{n} lines}'
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} line',
        other: '${n} lines',
      );

  /// en: ' · {purpose}'
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class Translations$repoSummary$glance$en {
  Translations$repoSummary$glance$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {{n} file.} (other) {{n} files.}'
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} file.',
        other: '${n} files.',
      );

  /// en: '(one) {{n} line ({bytes}).} (other) {{n} lines ({bytes}).}'
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} line (${bytes}).',
        other: '${n} lines (${bytes}).',
      );

  /// en: 'Roles — {parts}.'
  String roles({required Object parts}) => 'Roles — ${parts}.';

  /// en: 'Showing {active} of {total} files, ranked by structural centrality.'
  String showingNofM({required Object active, required Object total}) =>
      'Showing ${active} of ${total} files, ranked by structural centrality.';
}

// Path: repoSummary.heading
class Translations$repoSummary$heading$en {
  Translations$repoSummary$heading$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'At a glance'
  String get atAGlance => 'At a glance';

  /// en: 'Core'
  String get core => 'Core';

  /// en: 'Getting started'
  String get gettingStarted => 'Getting started';

  /// en: 'Regions'
  String get regions => 'Regions';

  /// en: 'Shape'
  String get shape => 'Shape';
}

// Path: repoSummary.pitch
class Translations$repoSummary$pitch$en {
  Translations$repoSummary$pitch$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'A repository with no readable text files{detail}.'
  String empty({required Object detail}) =>
      'A repository with no readable text files${detail}.';

  /// en: '{n} binary'
  String emptyBinary({required Object n}) => '${n} binary';

  /// en: '{n} unreadable'
  String emptyUnreadable({required Object n}) => '${n} unreadable';

  /// en: '(one) {A repository of {n} active file.} (other) {A repository of {n} active files.}'
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'A repository of ${n} active file.',
        other: 'A repository of ${n} active files.',
      );

  /// en: '(one) {A repository of {n} active file — {regions}.} (other) {A repository of {n} active files — {regions}.}'
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'A repository of ${n} active file — ${regions}.',
        other: 'A repository of ${n} active files — ${regions}.',
      );
}

// Path: repoSummary.region
class Translations$repoSummary$region$en {
  Translations$repoSummary$region$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'All under `{dir}`.'
  String bodyCommonDir({required Object dir}) => 'All under `${dir}`.';

  /// en: ' '
  String get bodyCommonDirSeparator => ' ';

  /// en: '(one) {1 core} (other) {{n} core}'
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '1 core',
        other: '${n} core',
      );

  /// en: ', '
  String get bodyCoreSeparator => ', ';

  /// en: '(one) {One file} (other) {{n} files}'
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'One file',
        other: '${n} files',
      );

  /// en: 'Connects to: {linked}.'
  String connectsTo({required Object linked}) => 'Connects to: ${linked}.';

  /// en: 'Files:'
  String get filesLabel => 'Files:';
}

// Path: repoSummary.shape
class Translations$repoSummary$shape$en {
  Translations$repoSummary$shape$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Densely interconnected codebase: most files participate in one large neighbourhood of shared change.'
  String get bulk =>
      'Densely interconnected codebase: most files participate in one large neighbourhood of shared change.';

  /// en: 'Lattice-shaped codebase: uniform, regular coupling across files with predictable local structure.'
  String get crystalline =>
      'Lattice-shaped codebase: uniform, regular coupling across files with predictable local structure.';

  /// en: 'Richly interconnected codebase: couplings spread across files without a dominant spine.'
  String get goe =>
      'Richly interconnected codebase: couplings spread across files without a dominant spine.';

  /// en: 'Modular codebase: several cohesive regions with limited cross-coupling. Work in one region rarely disturbs another.'
  String get modular =>
      'Modular codebase: several cohesive regions with limited cross-coupling. Work in one region rarely disturbs another.';

  /// en: 'Loosely coupled codebase: files evolve mostly on their own, with occasional shared change.'
  String get poisson =>
      'Loosely coupled codebase: files evolve mostly on their own, with occasional shared change.';

  /// en: 'Tree-shaped codebase: one dominant spine with dependent branches. Change usually propagates outward from the core.'
  String get tree =>
      'Tree-shaped codebase: one dominant spine with dependent branches. Change usually propagates outward from the core.';
}

// Path: settings.language
class Translations$settings$language$en {
  Translations$settings$language$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Language'
  String get title => 'Language';

  /// en: 'UI language for this app. Git output, logs, and diagnostics stay English so bug reports remain searchable.'
  String get summary =>
      'UI language for this app. Git output, logs, and diagnostics stay English so bug reports remain searchable.';

  /// en: 'DISPLAY LANGUAGE'
  String get label => 'DISPLAY LANGUAGE';

  /// en: 'System default'
  String get systemDefault => 'System default';

  /// en: 'Follows your OS language ({resolved})'
  String systemDefaultDetail({required Object resolved}) =>
      'Follows your OS language (${resolved})';

  /// en: 'Source language, written by the developer.'
  String get disclosureSource => 'Source language, written by the developer.';

  /// en: 'Machine translated by {model}, not yet human reviewed. Corrections welcome.'
  String disclosureAi({required Object model}) =>
      'Machine translated by ${model}, not yet human reviewed. Corrections welcome.';

  /// en: 'Machine translated by {model}. {percent}% human reviewed.'
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Machine translated by ${model}. ${percent}% human reviewed.';

  /// en: 'Human translation, maintained by the community.'
  String get disclosureHuman =>
      'Human translation, maintained by the community.';

  /// en: 'Reviewed by {names}.'
  String reviewedBy({required Object names}) => 'Reviewed by ${names}.';
}

// Path: settings.sectionLabels
class Translations$settings$sectionLabels$en {
  Translations$settings$sectionLabels$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Preferences'
  String get preferences => 'Preferences';

  /// en: 'Shortcuts'
  String get shortcuts => 'Shortcuts';

  /// en: 'Behaviour'
  String get behaviour => 'Behaviour';

  /// en: 'AI Providers'
  String get aiProviders => 'AI Providers';

  /// en: 'Model Slots'
  String get modelSlots => 'Model Slots';

  /// en: 'Tools'
  String get tools => 'Tools';

  /// en: 'Diagnostics'
  String get diagnostics => 'Diagnostics';

  /// en: 'Offenders'
  String get offenders => 'Offenders';

  /// en: 'Release'
  String get release => 'Release';
}

// Path: settings.errors
class Translations$settings$errors$en {
  Translations$settings$errors$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Failed to save guardrail profile.'
  String get saveGuardrailProfile => 'Failed to save guardrail profile.';

  /// en: 'Failed to save retention policy.'
  String get saveRetentionPolicy => 'Failed to save retention policy.';

  /// en: 'Failed to save update channel.'
  String get saveUpdateChannel => 'Failed to save update channel.';

  /// en: 'Failed to save AI model selection.'
  String get saveModelSelection => 'Failed to save AI model selection.';

  /// en: 'Failed to save model alias.'
  String get saveModelAlias => 'Failed to save model alias.';

  /// en: 'Failed to save commit message model slot.'
  String get saveCommitMessageModelSlot =>
      'Failed to save commit message model slot.';

  /// en: 'Failed to save review model slot.'
  String get saveReviewModelSlot => 'Failed to save review model slot.';

  /// en: 'Failed to save commit message custom prompt.'
  String get saveCommitMessageCustomPrompt =>
      'Failed to save commit message custom prompt.';

  /// en: 'Failed to save review guide.'
  String get saveReviewGuide => 'Failed to save review guide.';

  /// en: 'Failed to save muse notes.'
  String get saveMuseNotes => 'Failed to save muse notes.';

  /// en: 'Failed to save review double-check mode.'
  String get saveReviewDoubleCheck =>
      'Failed to save review double-check mode.';

  /// en: 'Failed to save API piggyback CLI.'
  String get saveApiPiggybackCli => 'Failed to save API piggyback CLI.';

  /// en: 'Failed to save CLI timeout.'
  String get saveCliTimeout => 'Failed to save CLI timeout.';

  /// en: 'Could not stop the running CLI sessions.'
  String get stopAllCli => 'Could not stop the running CLI sessions.';

  /// en: 'Could not clear local data: {error}'
  String clearLocalData({required Object error}) =>
      'Could not clear local data: ${error}';
}

// Path: settings.promptStatus
class Translations$settings$promptStatus$en {
  Translations$settings$promptStatus$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Editing'
  String get editing => 'Editing';

  /// en: 'Saving'
  String get saving => 'Saving';

  /// en: 'Save failed'
  String get saveFailed => 'Save failed';
}

// Path: settings.clearData
class Translations$settings$clearData$en {
  Translations$settings$clearData$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Clear local data'
  String get dialogTitle => 'Clear local data';

  /// en: 'Clear'
  String get clear => 'Clear';

  /// en: 'Clear local diagnostics samples and performance timings?'
  String get confirmDiagnostics =>
      'Clear local diagnostics samples and performance timings?';

  /// en: 'Clear local AI audit metadata records?'
  String get confirmAudit => 'Clear local AI audit metadata records?';

  /// en: 'Clear all local diagnostics samples and AI audit metadata records?'
  String get confirmAll =>
      'Clear all local diagnostics samples and AI audit metadata records?';

  /// en: 'Wipe all local app data — including the recent repos list — and quit? Your actual git repos on disk are not touched.'
  String get confirmWipeAll =>
      'Wipe all local app data — including the recent repos list — and quit? Your actual git repos on disk are not touched.';

  /// en: 'Reset local app data and quit? Settings, theme, onboarding, AI preferences, telemetry, and engram caches are cleared. Your recent repos list survives.'
  String get confirmReset =>
      'Reset local app data and quit?\n\nSettings, theme, onboarding, AI preferences, telemetry, and engram caches are cleared. Your recent repos list survives.';
}

// Path: settings.guardrailMacro
class Translations$settings$guardrailMacro$en {
  Translations$settings$guardrailMacro$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'loose'
  String get loose => 'loose';

  /// en: 'balanced'
  String get balanced => 'balanced';

  /// en: 'strict'
  String get strict => 'strict';

  /// en: 'paranoid'
  String get paranoid => 'paranoid';
}

// Path: settings.guardrails
class Translations$settings$guardrails$en {
  Translations$settings$guardrails$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Guardrails'
  String get title => 'Guardrails';

  /// en: 'How attentive automation is across the whole experience.'
  String get summary =>
      'How attentive automation is across the whole experience.';
}

// Path: settings.appearance
class Translations$settings$appearance$en {
  Translations$settings$appearance$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Appearance'
  String get title => 'Appearance';

  /// en: 'Global interface mood and atmosphere.'
  String get summary => 'Global interface mood and atmosphere.';
}

// Path: settings.retention
class Translations$settings$retention$en {
  Translations$settings$retention$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Local Data Retention'
  String get title => 'Local Data Retention';

  /// en: 'Diagnostic retention policy.'
  String get summaryDiagnostics => 'Diagnostic retention policy.';

  /// en: 'Diagnostic and AI audit retention policy.'
  String get summaryWithAudit => 'Diagnostic and AI audit retention policy.';

  /// en: 'days'
  String get unitDays => 'days';

  /// en: 'MB'
  String get unitMb => 'MB';

  /// en: 'Includes diagnostics, performance timings, and metadata.'
  String get includesNote =>
      'Includes diagnostics, performance timings, and metadata.';
}

// Path: settings.navigation
class Translations$settings$navigation$en {
  Translations$settings$navigation$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Navigation and Dynamics'
  String get title => 'Navigation and Dynamics';

  /// en: 'Shortcuts and interface behavior.'
  String get summaryShortcuts => 'Shortcuts and interface behavior.';

  /// en: 'Shortcuts, interface behavior, and AI routing.'
  String get summaryWithAi => 'Shortcuts, interface behavior, and AI routing.';
}

// Path: settings.behaviour
class Translations$settings$behaviour$en {
  Translations$settings$behaviour$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Behavioural Dynamics'
  String get title => 'Behavioural Dynamics';
}

// Path: settings.retentionClear
class Translations$settings$retentionClear$en {
  Translations$settings$retentionClear$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Diag'
  String get diag => 'Diag';

  /// en: 'Audit'
  String get audit => 'Audit';

  /// en: 'All'
  String get all => 'All';

  /// en: '<-- clears'
  String get clearsHint => '<-- clears';
}

// Path: settings.channels
class Translations$settings$channels$en {
  Translations$settings$channels$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'STABLE'
  String get stable => 'STABLE';

  /// en: 'BETA'
  String get beta => 'BETA';

  /// en: 'DEV'
  String get dev => 'DEV';
}

// Path: settings.pollResult
class Translations$settings$pollResult$en {
  Translations$settings$pollResult$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'up to date'
  String get upToDate => 'up to date';

  /// en: '{version} available'
  String updateAvailable({required Object version}) => '${version} available';

  /// en: 'no update server'
  String get notConfigured => 'no update server';

  /// en: 'no {channel} releases'
  String notFound({required Object channel}) => 'no ${channel} releases';

  /// en: 'unreachable'
  String get unreachable => 'unreachable';

  /// en: 'bad manifest'
  String get badManifest => 'bad manifest';
}

// Path: settings.keybindingProfile
class Translations$settings$keybindingProfile$en {
  Translations$settings$keybindingProfile$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Keybinding profile'
  String get label => 'Keybinding profile';

  /// en: 'Porcelain'
  String get porcelain => 'Porcelain';

  /// en: 'Numeric'
  String get numeric => 'Numeric';

  /// en: 'Chorded shortcuts (G then C, H, B…).'
  String get porcelainDescription => 'Chorded shortcuts (G then C, H, B…).';

  /// en: 'Single-key numeric shortcuts (1, 2, 3…).'
  String get numericDescription => 'Single-key numeric shortcuts (1, 2, 3…).';
}

// Path: settings.apiKeys
class Translations$settings$apiKeys$en {
  Translations$settings$apiKeys$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'api key'
  String get keyHintDefault => 'api key';

  /// en: 'endpoint'
  String get endpointHint => 'endpoint';

  /// en: 'Test'
  String get test => 'Test';

  /// en: 'Hide'
  String get hide => 'Hide';

  /// en: 'Show'
  String get show => 'Show';
}

// Path: settings.shortcuts
class Translations$settings$shortcuts$en {
  Translations$settings$shortcuts$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'navigate'
  String get navigate => 'navigate';

  /// en: 'staging'
  String get staging => 'staging';

  /// en: 'branches & PRs'
  String get branchesPrs => 'branches & PRs';

  /// en: 'modifiers'
  String get modifiers => 'modifiers';

  /// en: 'Changes'
  String get changes => 'Changes';

  /// en: 'History'
  String get history => 'History';

  /// en: 'Branches'
  String get branches => 'Branches';

  /// en: 'X-Ray'
  String get xray => 'X-Ray';

  /// en: 'Switch (always)'
  String get switchAlways => 'Switch (always)';

  /// en: 'Search'
  String get search => 'Search';

  /// en: 'Dismiss'
  String get dismiss => 'Dismiss';

  /// en: 'Refresh'
  String get refresh => 'Refresh';

  /// en: 'Shortcuts'
  String get shortcuts => 'Shortcuts';

  /// en: 'Next change'
  String get nextChange => 'Next change';

  /// en: 'Prev change'
  String get prevChange => 'Prev change';

  /// en: 'Toggle line'
  String get toggleLine => 'Toggle line';

  /// en: 'Toggle hunk'
  String get toggleHunk => 'Toggle hunk';

  /// en: 'Toggle file'
  String get toggleFile => 'Toggle file';

  /// en: 'Pin context'
  String get pinContext => 'Pin context';

  /// en: 'Commit'
  String get commit => 'Commit';

  /// en: 'Accept hint'
  String get acceptHint => 'Accept hint';

  /// en: 'Undo'
  String get undo => 'Undo';

  /// en: 'Navigate'
  String get navigateRow => 'Navigate';

  /// en: 'Expand'
  String get expand => 'Expand';

  /// en: 'Checkout'
  String get checkout => 'Checkout';

  /// en: 'Approve'
  String get approve => 'Approve';

  /// en: 'Request changes'
  String get requestChanges => 'Request changes';

  /// en: 'Select range'
  String get selectRange => 'Select range';

  /// en: 'Extended menu'
  String get extendedMenu => 'Extended menu';
}

// Path: settings.toggles
class Translations$settings$toggles$en {
  Translations$settings$toggles$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'AI read-only mode'
  String get aiReadOnlyLabel => 'AI read-only mode';

  /// en: 'Prevents AI from writing or staging changes automatically.'
  String get aiReadOnlyDescription =>
      'Prevents AI from writing or staging changes automatically.';

  /// en: 'Logo animates when tabbed out'
  String get logoMotionLabel => 'Logo animates when tabbed out';

  /// en: 'It's designed to be efficient, don't hurt its feelings'
  String get logoMotionDescriptionEnabled =>
      'It\'s designed to be efficient, don\'t hurt its feelings';

  /// en: ':('
  String get logoMotionDescriptionDisabled => ':(';

  /// en: 'Remember work in progress'
  String get rememberWipLabel => 'Remember work in progress';

  /// en: 'Keep your commit drafts and file selection between sessions.'
  String get rememberWipDescription =>
      'Keep your commit drafts and file selection between sessions.';

  /// en: 'Stash cabinet starts expanded'
  String get stashCabinetLabel => 'Stash cabinet starts expanded';

  /// en: 'Show the filing-cabinet drawer open by default when a repo has shelves.'
  String get stashCabinetDescription =>
      'Show the filing-cabinet drawer open by default when a repo has shelves.';

  /// en: 'Instant blame hover'
  String get instantBlameLabel => 'Instant blame hover';

  /// en: 'Skip the 180ms delay before blame info reveals on a diff line.'
  String get instantBlameDescription =>
      'Skip the 180ms delay before blame info reveals on a diff line.';

  /// en: 'Auto select new changes'
  String get autoSelectLabel => 'Auto select new changes';

  /// en: 'Newly tracked or changed files are added to the commit selection automatically.'
  String get autoSelectDescription =>
      'Newly tracked or changed files are added to the commit selection automatically.';

  /// en: 'Write change-id headers'
  String get changeIdLabel => 'Write change-id headers';

  /// en: 'Stamp new commits with a change-id identity header (the Jujutsu, GitButler, and Gerrit convention). Each commit is rewritten once, right after it lands.'
  String get changeIdDescription =>
      'Stamp new commits with a change-id identity header (the Jujutsu, GitButler, and Gerrit convention). Each commit is rewritten once, right after it lands.';

  /// en: 'Fetch online issues on branch load'
  String get fetchIssuesLabel => 'Fetch online issues on branch load';

  /// en: 'Pull PR and issue details from your git provider in the background when the branches page opens.'
  String get fetchIssuesDescription =>
      'Pull PR and issue details from your git provider in the background when the branches page opens.';

  /// en: 'I hate AI'
  String get hateAiLabel => 'I hate AI';

  /// en: 'Banish all LLM-backed features. Logos keeps running because it's just spectral math.'
  String get hateAiDescription =>
      'Banish all LLM-backed features. Logos keeps running because it\'s just spectral math.';
}

// Path: settings.diffDiffability
class Translations$settings$diffDiffability$en {
  Translations$settings$diffDiffability$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'diff diff-ability'
  String get title => 'diff diff-ability';
}

// Path: settings.modelSlots
class Translations$settings$modelSlots$en {
  Translations$settings$modelSlots$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Loading providers...'
  String get loadingProviders => 'Loading providers...';

  /// en: 'Refreshing provider diagnostics...'
  String get refreshingProviders => 'Refreshing provider diagnostics...';

  /// en: 'Rename and route configurations to any detected provider model.'
  String get routeDescription =>
      'Rename and route configurations to any detected provider model.';

  /// en: 'Loading model categories...'
  String get loadingCategories => 'Loading model categories...';

  /// en: 'No model options are available yet. Detect a compatible local AI CLI first.'
  String get noOptions =>
      'No model options are available yet. Detect a compatible local AI CLI first.';

  /// en: 'Model-slot settings will appear here once provider models are available.'
  String get slotsAppearWhenAvailable =>
      'Model-slot settings will appear here once provider models are available.';

  /// en: 'default'
  String get effortDefault => 'default';

  /// en: 'No models detected for this slot.'
  String get noModelsForSlot => 'No models detected for this slot.';

  /// en: 'via {provider}'
  String viaProvider({required Object provider}) => 'via ${provider}';

  /// en: 'custom model id'
  String get customModelId => 'custom model id';
}

// Path: settings.modelPicker
class Translations$settings$modelPicker$en {
  Translations$settings$modelPicker$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'no models match "{query}"'
  String noMatch({required Object query}) => 'no models match "${query}"';

  /// en: 'no models available'
  String get noModels => 'no models available';

  /// en: 'filter models...'
  String get filterHint => 'filter models...';

  /// en: 'warming…'
  String get warming => 'warming…';

  /// en: 'details unavailable'
  String get detailsUnavailable => 'details unavailable';

  /// en: 'free'
  String get free => 'free';
}

// Path: settings.aiFeatures
class Translations$settings$aiFeatures$en {
  Translations$settings$aiFeatures$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Draft commit messages from staged changes using your structure, voice, and coverage preferences.'
  String get commitDescription =>
      'Draft commit messages from staged changes using your structure, voice, and coverage preferences.';

  /// en: 'Review the current commit scope before you commit.'
  String get reviewDescription =>
      'Review the current commit scope before you commit.';

  /// en: 'Three-phase oracle that brainstorms then synthesizes a forward direction for the diff.'
  String get museDescription =>
      'Three-phase oracle that brainstorms then synthesizes a forward direction for the diff.';
}

// Path: settings.commitEditor
class Translations$settings$commitEditor$en {
  Translations$settings$commitEditor$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Style Guide'
  String get styleGuide => 'Style Guide';

  /// en: 'Optional. Voice / tone / bans. The format above handles skeleton.'
  String get styleGuideHint =>
      'Optional. Voice / tone / bans. The format above handles skeleton.';
}

// Path: settings.review
class Translations$settings$review$en {
  Translations$settings$review$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Additional notes to review with'
  String get additionalNotes => 'Additional notes to review with';

  /// en: 'Double-check review'
  String get doubleCheckLabel => 'Double-check review';

  /// en: 'Run a second verification pass before showing the final report.'
  String get doubleCheckDescription =>
      'Run a second verification pass before showing the final report.';
}

// Path: settings.museHint
class Translations$settings$museHint$en {
  Translations$settings$museHint$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'anything to gently steer toward? mood is kind today.'
  String get loose => 'anything to gently steer toward? mood is kind today.';

  /// en: 'what to dwell on, what to skip. honest, not harsh.'
  String get balanced => 'what to dwell on, what to skip. honest, not harsh.';

  /// en: 'the standards. the bans. what the muse won't let slide.'
  String get strict =>
      'the standards. the bans. what the muse won\'t let slide.';

  /// en: 'tune the lens. what frequencies should the manifold hum at?'
  String get paranoid =>
      'tune the lens. what frequencies should the manifold hum at?';
}

// Path: settings.museEditor
class Translations$settings$museEditor$en {
  Translations$settings$museEditor$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Additional notes for the muse'
  String get additionalNotes => 'Additional notes for the muse';
}

// Path: settings.museStage
class Translations$settings$museStage$en {
  Translations$settings$museStage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'BRAINSTORM'
  String get brainstorm => 'BRAINSTORM';

  /// en: 'SYNTHESIZE'
  String get synthesize => 'SYNTHESIZE';

  /// en: 'slot'
  String get slot => 'slot';

  /// en: '~12 ideas'
  String get ideaCountLoose => '~12 ideas';

  /// en: '~16 ideas'
  String get ideaCountBalanced => '~16 ideas';

  /// en: '~20 ideas'
  String get ideaCountStrict => '~20 ideas';

  /// en: '~24 ideas'
  String get ideaCountParanoid => '~24 ideas';

  /// en: '{ideas} · guardrail: {macro}'
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  guardrail: ${macro}';
}

// Path: settings.lensAxis
class Translations$settings$lensAxis$en {
  Translations$settings$lensAxis$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'FOLDER'
  String get folder => 'FOLDER';

  /// en: 'HISTORY'
  String get history => 'HISTORY';

  /// en: 'FAR'
  String get far => 'FAR';

  /// en: 'NEAR'
  String get near => 'NEAR';
}

// Path: settings.logosLens
class Translations$settings$logosLens$en {
  Translations$settings$logosLens$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'module map'
  String get moduleMap => 'module map';

  /// en: 'repo centers'
  String get repoCenters => 'repo centers';

  /// en: 'neighbors'
  String get neighbors => 'neighbors';

  /// en: 'what to touch next'
  String get toTouch => 'what to touch next';

  /// en: 'relevance engine'
  String get relevanceEngine => 'relevance engine';

  /// en: 'reads how files move together across structure, history, and rhythm, so Manifold knows what matters, not just what changed.'
  String get description =>
      'reads how files move together across structure, history, and rhythm, so Manifold knows what matters, not just what changed.';

  /// en: 'within reach'
  String get withinReach => 'within reach';

  /// en: 'gate'
  String get gate => 'gate';

  /// en: 'nearest'
  String get nearest => 'nearest';

  /// en: 'warming'
  String get warming => 'warming';

  /// en: 'open a repo to see the lens live'
  String get emptyOpenRepo => 'open a repo to\nsee the lens live';

  /// en: 'no files within reach — drag toward HISTORY'
  String get emptyNoFiles => 'no files within\nreach — drag\ntoward HISTORY';
}

// Path: settings.sortGuide
class Translations$settings$sortGuide$en {
  Translations$settings$sortGuide$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Change sort guide'
  String get title => 'Change sort guide';

  /// en: 'Files that change together cluster together. The concern comes first; context follows.'
  String get related =>
      'Files that change together cluster together. The concern comes first; context follows.';

  /// en: 'Isolated changes come first. Tightly-coupled clusters sink to the bottom.'
  String get relatedInverted =>
      'Isolated changes come first. Tightly-coupled clusters sink to the bottom.';

  /// en: 'Plain A → Z by path. Case-insensitive, numbers ordered naturally.'
  String get alphabetical =>
      'Plain A → Z by path. Case-insensitive, numbers ordered naturally.';

  /// en: 'Plain Z → A by path. Case-insensitive, numbers ordered naturally.'
  String get alphabeticalInverted =>
      'Plain Z → A by path. Case-insensitive, numbers ordered naturally.';

  /// en: 'Heaviest changes surface first. Churn is weighted; binaries and new files get boosted.'
  String get impact =>
      'Heaviest changes surface first. Churn is weighted; binaries and new files get boosted.';

  /// en: 'Lightest changes surface first. Quick wins on top; the heavy lifts wait.'
  String get impactInverted =>
      'Lightest changes surface first. Quick wins on top; the heavy lifts wait.';

  /// en: 'near related'
  String get nearRelated => 'near related';

  /// en: 'alphabetical'
  String get alphabeticalShort => 'alphabetical';

  /// en: 'by impact'
  String get byImpact => 'by impact';

  /// en: 'flipped'
  String get flipped => 'flipped';

  /// en: 'peek'
  String get peek => 'peek';
}

// Path: settings.piggyback
class Translations$settings$piggyback$en {
  Translations$settings$piggyback$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'API models use'
  String get apiModelsUse => 'API models use';

  /// en: 'codex not detected'
  String get codexNotDetected => 'codex not detected';

  /// en: 'DORMANT'
  String get dormant => 'DORMANT';
}

// Path: settings.diffStage
class Translations$settings$diffStage$en {
  Translations$settings$diffStage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'viewer'
  String get viewer => 'viewer';

  /// en: 'media'
  String get media => 'media';

  /// en: 'binary'
  String get binary => 'binary';

  /// en: 'hidden'
  String get hidden => 'hidden';
}

// Path: settings.undoScope
class Translations$settings$undoScope$en {
  Translations$settings$undoScope$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'destructive actions'
  String get destructiveActions => 'destructive actions';

  /// en: 'discards'
  String get discards => 'discards';

  /// en: 'commits'
  String get commits => 'commits';

  /// en: 'commit + push'
  String get commitPush => 'commit + push';

  /// en: 'all'
  String get all => 'all';
}

// Path: settings.undoWindow
class Translations$settings$undoWindow$en {
  Translations$settings$undoWindow$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Undo window'
  String get label => 'Undo window';

  /// en: 'Off'
  String get off => 'Off';

  /// en: '{scope} finalize instantly.'
  String descriptionInstant({required Object scope}) =>
      '${scope} finalize instantly.';

  /// en: '{seconds}s before {scope} finalize.'
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s before ${scope} finalize.';

  /// en: 'Click to cycle scope · drag up/down on the slider too'
  String get cycleScopeTooltip =>
      'Click to cycle scope · drag up/down on the slider too';

  /// en: 'Reset every action to use the default window'
  String get resetTooltip => 'Reset every action to use the default window';
}

// Path: settings.guardrailPhrase
class Translations$settings$guardrailPhrase$en {
  Translations$settings$guardrailPhrase$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Probably fine means fine'
  String get probablyFine => 'Probably fine means fine';

  /// en: 'A proper read, logic, integration, patterns'
  String get proper => 'A proper read, logic, integration, patterns';

  /// en: 'Look again. Something might be hiding'
  String get lookAgain => 'Look again. Something might be hiding';

  /// en: 'Assume something is wrong. Find it'
  String get assumeWrong => 'Assume something is wrong. Find it';
}

// Path: settings.reviewGuideHint
class Translations$settings$reviewGuideHint$en {
  Translations$settings$reviewGuideHint$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'e.g. Focus on high-level logic and major bugs. Be brief and forgiving.'
  String get focusHigh =>
      'e.g. Focus on high-level logic and major bugs. Be brief and forgiving.';

  /// en: 'e.g. Surface potential bugs, architectural inconsistencies, and edge case failures.'
  String get surfaceBugs =>
      'e.g. Surface potential bugs, architectural inconsistencies, and edge case failures.';

  /// en: 'e.g. Scrutinize every line for optimization, security, and pattern compliance.'
  String get scrutinize =>
      'e.g. Scrutinize every line for optimization, security, and pattern compliance.';

  /// en: 'e.g. Trust nothing. Question every side effect. Treat every line as a potential failure.'
  String get trustNothing =>
      'e.g. Trust nothing. Question every side effect. Treat every line as a potential failure.';

  /// en: 'Optional guidance for what the review should care about.'
  String get optional =>
      'Optional guidance for what the review should care about.';
}

// Path: settings.commitFormat
class Translations$settings$commitFormat$en {
  Translations$settings$commitFormat$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Format'
  String get title => 'Format';

  /// en: 'peek'
  String get peek => 'peek';

  /// en: 'Structure'
  String get structure => 'Structure';

  /// en: 'Voice'
  String get voice => 'Voice';

  /// en: 'Coverage'
  String get coverage => 'Coverage';

  /// en: 'title + body'
  String get structureTitleBody => 'title + body';

  /// en: 'title only'
  String get structureTitleOnly => 'title only';

  /// en: 'freeform'
  String get structureFreeform => 'freeform';

  /// en: 'action orientated'
  String get voiceVerbLed => 'action orientated';

  /// en: 'descriptive'
  String get voiceDescriptive => 'descriptive';

  /// en: 'narrative'
  String get voiceNarrative => 'narrative';

  /// en: 'essentials'
  String get coverageEssentials => 'essentials';

  /// en: 'balanced'
  String get coverageBalanced => 'balanced';

  /// en: 'everything'
  String get coverageEverything => 'everything';
}

// Path: settings.commitPreview
class Translations$settings$commitPreview$en {
  Translations$settings$commitPreview$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$settings$commitPreview$title$en title =
      Translations$settings$commitPreview$title$en.internal(_root);
  late final Translations$settings$commitPreview$base$en base =
      Translations$settings$commitPreview$base$en.internal(_root);
  late final Translations$settings$commitPreview$balancedSuffix$en
  balancedSuffix =
      Translations$settings$commitPreview$balancedSuffix$en.internal(_root);
  late final Translations$settings$commitPreview$everythingSuffix$en
  everythingSuffix =
      Translations$settings$commitPreview$everythingSuffix$en.internal(_root);
}

// Path: settings.externalTools
class Translations$settings$externalTools$en {
  Translations$settings$externalTools$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'External Tools'
  String get title => 'External Tools';

  /// en: 'Right-click a project in the sidebar to open it with one of these. Args use \{path} for the project folder.'
  String get summary =>
      'Right-click a project in the sidebar to open it with one of these. Args use {path} for the project folder.';

  /// en: 'Detecting installed tools…'
  String get detecting => 'Detecting installed tools…';

  /// en: 'All known presets are already added. Use “+ Custom” to add more.'
  String get allPresetsAdded =>
      'All known presets are already added. Use “+ Custom” to add more.';

  /// en: 'No tools configured yet. Add one above.'
  String get noToolsConfigured => 'No tools configured yet. Add one above.';

  /// en: 'ai'
  String get categoryAi => 'ai';

  /// en: 'editors'
  String get categoryEditors => 'editors';

  /// en: 'explore'
  String get categoryExplore => 'explore';

  /// en: 'ops'
  String get categoryOps => 'ops';

  /// en: 'git ops'
  String get categoryGitOps => 'git ops';

  /// en: 'Name'
  String get nameHint => 'Name';

  /// en: 'command'
  String get commandHint => 'command';

  /// en: 'test'
  String get test => 'test';

  /// en: 'Remove tool'
  String get removeTool => 'Remove tool';

  /// en: 'terminal'
  String get modeTerminal => 'terminal';

  /// en: 'detached'
  String get modeDetached => 'detached';
}

// Path: settings.apiUsage
class Translations$settings$apiUsage$en {
  Translations$settings$apiUsage$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{used}{limit} this month'
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} this month';
}

// Path: settings.gitea
class Translations$settings$gitea$en {
  Translations$settings$gitea$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Gitea tokens'
  String get title => 'Gitea tokens';

  /// en: 'host'
  String get hostHint => 'host';

  /// en: 'token'
  String get tokenHint => 'token';

  /// en: 'save'
  String get save => 'save';
}

// Path: settings.wick
class Translations$settings$wick$en {
  Translations$settings$wick$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Select wick executable'
  String get selectExecutable => 'Select wick executable';

  /// en: 'wick · connected'
  String get connected => 'wick · connected';

  /// en: 'wick · path to executable'
  String get pathToExecutable => 'wick · path to executable';

  /// en: 'off'
  String get off => 'off';

  /// en: 'Turn the wick integration off'
  String get disableHint => 'Turn the wick integration off';

  /// en: 'Turn the wick integration on'
  String get enableHint => 'Turn the wick integration on';
}

// Path: settings.integrations
class Translations$settings$integrations$en {
  Translations$settings$integrations$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '& Integrations'
  String get title => '& Integrations';

  /// en: 'alpha'
  String get alpha => 'alpha';

  /// en: 'planned'
  String get planned => 'planned';

  /// en: 'lsp · coming soon'
  String get lspComingSoon => 'lsp · coming soon';

  /// en: 'alpha-math · connected'
  String get alphaMathConnected => 'alpha-math · connected';

  /// en: 'alpha-math · coming soon'
  String get alphaMathComingSoon => 'alpha-math · coming soon';
}

// Path: settings.reduceMotion
class Translations$settings$reduceMotion$en {
  Translations$settings$reduceMotion$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Reduce motion'
  String get label => 'Reduce motion';

  /// en: 'Still… like ice?'
  String get subtitleStill => 'Still… like ice?';

  /// en: 'Flow like water.'
  String get subtitleFlow => 'Flow like water.';
}

// Path: settings.resetQuit
class Translations$settings$resetQuit$en {
  Translations$settings$resetQuit$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'RESET & QUIT'
  String get resetAndQuit => 'RESET & QUIT';

  /// en: 'KEEP REPOS'
  String get keepRepos => 'KEEP REPOS';

  /// en: 'WIPE ALL'
  String get wipeAll => 'WIPE ALL';
}

// Path: settings.diagnostics
class Translations$settings$diagnostics$en {
  Translations$settings$diagnostics$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Command Diagnostics'
  String get commandDiagnostics => 'Command Diagnostics';

  /// en: 'Network Flow Telemetry'
  String get networkFlowTelemetry => 'Network Flow Telemetry';

  /// en: 'Clear Samples'
  String get clearSamples => 'Clear Samples';

  /// en: 'Clear Metrics'
  String get clearMetrics => 'Clear Metrics';

  /// en: 'Clear Timings'
  String get clearTimings => 'Clear Timings';

  /// en: 'RECALIBRATE'
  String get recalibrate => 'RECALIBRATE';

  /// en: 'ok'
  String get ok => 'ok';

  /// en: 'No command timings captured yet. Run normal actions to populate diagnostics.'
  String get noCommandTimings =>
      'No command timings captured yet. Run normal actions to populate diagnostics.';

  /// en: 'No backend command samples captured yet. Run git and settings actions to populate this log.'
  String get noBackendSamples =>
      'No backend command samples captured yet. Run git and settings actions to populate this log.';

  /// en: 'No diff render sessions captured yet. Open and scroll file diffs to populate this panel.'
  String get noDiffSessions =>
      'No diff render sessions captured yet. Open and scroll file diffs to populate this panel.';

  /// en: 'No UI timing sessions captured yet. Open panels and navigate routes to populate this panel.'
  String get noUiSessions =>
      'No UI timing sessions captured yet. Open panels and navigate routes to populate this panel.';

  /// en: 'Recent Operations'
  String get recentOperations => 'Recent Operations';

  /// en: 'Recent Backend Operations'
  String get recentBackendOperations => 'Recent Backend Operations';

  /// en: 'Recent Diff Sessions'
  String get recentDiffSessions => 'Recent Diff Sessions';

  /// en: 'Recent UI Timings'
  String get recentUiTimings => 'Recent UI Timings';

  /// en: '(one) {{n} unique command} (other) {{n} unique commands}'
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} unique command',
        other: '${n} unique commands',
      );

  /// en: '(one) {{n} scoped command} (other) {{n} scoped commands}'
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} scoped command',
        other: '${n} scoped commands',
      );

  /// en: '(one) {{n} instrumented event} (other) {{n} instrumented events}'
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} instrumented event',
        other: '${n} instrumented events',
      );

  /// en: '{samples} | {commands}'
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';

  /// en: '{samples} | {commands}'
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';

  /// en: '{sessions} | jank {jank}%'
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | jank ${jank}%';

  /// en: '{samples} | {events}'
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';

  List<String> get headersCommand => ['command', 'p50', 'reliability', 'range'];
  List<String> get headersBackend => ['scope', 'p50', 'p95', 'failures'];
  List<String> get headersDiff => [
    'renderer',
    'first paint',
    'frame p95',
    'raster p95',
    'jank',
  ];
  List<String> get headersUi => ['event', 'p50', 'failures', 'range'];
}

// Path: settings.telemetry
class Translations$settings$telemetry$en {
  Translations$settings$telemetry$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {{n} sample} (other) {{n} samples}'
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} sample',
        other: '${n} samples',
      );

  /// en: '(one) {{n} command} (other) {{n} commands}'
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} command',
        other: '${n} commands',
      );

  /// en: '(one) {{n} session} (other) {{n} sessions}'
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} session',
        other: '${n} sessions',
      );

  /// en: '(one) {{n} event} (other) {{n} events}'
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} event',
        other: '${n} events',
      );

  /// en: '{pct}% stability'
  String stability({required Object pct}) => '${pct}% stability';

  /// en: '{samples} | {commands}'
  String metaCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';

  /// en: '{sessions} | {stability}'
  String metaDiff({required Object sessions, required Object stability}) =>
      '${sessions} | ${stability}';

  /// en: '{samples} | {events}'
  String metaUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
}

// Path: settings.flowEngine
class Translations$settings$flowEngine$en {
  Translations$settings$flowEngine$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'execution-flow'
  String get executionFlow => 'execution-flow';

  /// en: 'simulate oscillators on code. surfacing fragile execution paths before they crystalize as bugs.'
  String get description =>
      'simulate oscillators on code. surfacing fragile execution paths before they crystalize as bugs.';

  /// en: 'idle'
  String get idle => 'idle';

  /// en: 'open a repo to see flow analysis'
  String get emptyOpenRepo => 'open a repo to\nsee flow analysis';

  /// en: 'scanning'
  String get scanning => 'scanning';

  /// en: 'analysing files in the lens…'
  String get analysing => 'analysing files\nin the lens…';

  /// en: 'fragility'
  String get fragility => 'fragility';

  /// en: 'findings'
  String get findings => 'findings';

  /// en: 'gap'
  String get gap => 'gap';

  /// en: 'clean'
  String get clean => 'clean';

  /// en: 'severity'
  String get severity => 'severity';

  /// en: 'critical'
  String get critical => 'critical';

  /// en: 'warn'
  String get warn => 'warn';

  /// en: 'info'
  String get info => 'info';
}

// Path: settings.museStrands
class Translations$settings$museStrands$en {
  Translations$settings$museStrands$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'spark of inspiration · the immediately next step'
  String get spark => 'spark of inspiration · the immediately next step';

  /// en: 'current in the water · present-tense extensions'
  String get current => 'current in the water · present-tense extensions';

  /// en: 'look over the horizon · reaching directions'
  String get horizon => 'look over the horizon · reaching directions';

  /// en: 'wake from a fever dream · provocations'
  String get fever => 'wake from a fever dream · provocations';

  /// en: 'an echo across the canyon · analogues elsewhere'
  String get echo => 'an echo across the canyon · analogues elsewhere';

  /// en: 'vertigo at the cliff edge · adjacent risks'
  String get vertigo => 'vertigo at the cliff edge · adjacent risks';

  /// en: 'the ghost of what was · historical context'
  String get ghost => 'the ghost of what was · historical context';

  /// en: 'a mirror on still water · inversions'
  String get mirror => 'a mirror on still water · inversions';
}

// Path: settings.cliPiggyback
class Translations$settings$cliPiggyback$en {
  Translations$settings$cliPiggyback$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'CLI Piggybacking'
  String get title => 'CLI Piggybacking';

  /// en: 'Clear cache'
  String get clearCacheLabel => 'Clear cache';

  /// en: 'Wipe cached models and re-probe. Clears out ones a provider dropped.'
  String get clearCacheTooltip =>
      'Wipe cached models and re-probe. Clears out ones a provider dropped.';

  /// en: 'Refresh providers'
  String get refreshLabel => 'Refresh providers';

  /// en: 'Re-probe every provider now.'
  String get refreshTooltip => 'Re-probe every provider now.';

  /// en: 'Directly pipe interface messages to local provider binaries.'
  String get body =>
      'Directly pipe interface messages to local provider binaries.';

  /// en: 'Timeout per run'
  String get cliTimeoutLabel => 'Timeout per run';

  /// en: 'minute'
  String get cliTimeoutUnitMinute => 'minute';

  /// en: 'minutes'
  String get cliTimeoutUnitMinutes => 'minutes';

  /// en: 'Stop all sessions'
  String get forceStopLabel => 'Stop all sessions';

  /// en: 'Force-quit every CLI run in progress.'
  String get forceStopTooltip => 'Force-quit every CLI run in progress.';

  /// en: 'Stop running CLI sessions?'
  String get forceStopConfirmTitle => 'Stop running CLI sessions?';

  /// en: 'This force-quits {count} CLI run(s) in progress. Their output will be lost.'
  String forceStopConfirmBody({required Object count}) =>
      'This force-quits ${count} CLI run(s) in progress. Their output will be lost.';

  /// en: 'Stop all'
  String get forceStopConfirmAction => 'Stop all';

  /// en: 'No CLI sessions running'
  String get forceStopNoneRunning => 'No CLI sessions running';

  /// en: 'Stopped — CLI sessions were force-quit.'
  String get forceStopRecordError => 'Stopped — CLI sessions were force-quit.';
}

// Path: settings.header
class Translations$settings$header$en {
  Translations$settings$header$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Workspace Preferences'
  String get title => 'Workspace Preferences';

  /// en: 'Configure global aesthetics, interface dynamics, and core operational safeguards for the entire workspace.'
  String get subtitle =>
      'Configure global aesthetics, interface dynamics, and core operational safeguards for the entire workspace.';

  /// en: 'Release notes'
  String get releaseNotesTooltip => 'Release notes';

  /// en: 'Replay onboarding'
  String get replayOnboardingTooltip => 'Replay onboarding';
}

// Path: settings.diagnosticsPanel
class Translations$settings$diagnosticsPanel$en {
  Translations$settings$diagnosticsPanel$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Performance Diagnostics'
  String get title => 'Performance Diagnostics';

  /// en: 'Copy Trace'
  String get copyTrace => 'Copy Trace';

  /// en: 'Offender Ranking'
  String get offenderRanking => 'Offender Ranking';

  /// en: 'Latency drivers across streams.'
  String get offenderRankingSubtitle => 'Latency drivers across streams.';

  /// en: 'No offender ranking yet. Capture diagnostic activity to populate this list.'
  String get noOffenders =>
      'No offender ranking yet. Capture diagnostic activity to populate this list.';
}

// Path: settings.release
class Translations$settings$release$en {
  Translations$settings$release$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Release Deployment'
  String get title => 'Release Deployment';

  /// en: 'Update related settings.'
  String get summary => 'Update related settings.';

  /// en: 'DEPLOYMENT CHANNEL'
  String get deploymentChannel => 'DEPLOYMENT CHANNEL';

  /// en: 'Capture crash diagnostics'
  String get captureCrashDiagnostics => 'Capture crash diagnostics';

  /// en: 'Coming soon.'
  String get comingSoon => 'Coming soon.';

  /// en: 'CHECKING…'
  String get checking => 'CHECKING…';

  /// en: 'POLL FOR UPDATES'
  String get pollForUpdates => 'POLL FOR UPDATES';
}

// Path: settings.providerStatus
class Translations$settings$providerStatus$en {
  Translations$settings$providerStatus$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Detecting...'
  String get detecting => 'Detecting...';

  /// en: 'Ready'
  String get ready => 'Ready';

  /// en: 'Not detected'
  String get notDetected => 'Not detected';

  /// en: '{count} configured'
  String configured({required Object count}) => '${count} configured';

  /// en: 'Not configured'
  String get notConfigured => 'Not configured';

  /// en: 'CLI-managed'
  String get cliManaged => 'CLI-managed';

  /// en: 'Connected'
  String get connected => 'Connected';

  /// en: '(one) {{n} model} (other) {{n} models}'
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} model',
        other: '${n} models',
      );

  /// en: '(one) {{n} provider} (other) {{n} providers}'
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} provider',
        other: '${n} providers',
      );
}

// Path: settings.meridiem
class Translations$settings$meridiem$en {
  Translations$settings$meridiem$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'AM'
  String get am => 'AM';

  /// en: 'PM'
  String get pm => 'PM';
}

// Path: settings.offenders
class Translations$settings$offenders$en {
  Translations$settings$offenders$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Command'
  String get commandStream => 'Command';

  /// en: 'Diff Render'
  String get diffStream => 'Diff Render';

  /// en: 'UI Timing'
  String get uiStream => 'UI Timing';

  /// en: '{mode} renderer'
  String rendererName({required Object mode}) => '${mode} renderer';

  /// en: '{p95}ms p95 | {fail}% fail'
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% fail';

  /// en: '{jank}% jank | {frame}ms frame p95'
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame}ms frame p95';

  /// en: 'in {stream}'
  String inStream({required Object stream}) => 'in ${stream}';
}

// Path: sync.actions
class Translations$sync$actions$en {
  Translations$sync$actions$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Sync'
  String get syncLabel => 'Sync';

  /// en: 'Open a repository to manage push and pull operations.'
  String get syncOpenRepoDetail =>
      'Open a repository to manage push and pull operations.';

  /// en: 'Detached HEAD'
  String get detachedHeadLabel => 'Detached HEAD';

  /// en: 'Check out a branch before pushing or pulling.'
  String get detachedHeadDetail =>
      'Check out a branch before pushing or pulling.';

  /// en: 'Publish branch'
  String get publishBranchLabel => 'Publish branch';

  /// en: 'Push {branch} and set its upstream tracking branch.'
  String publishBranchDetail({required Object branch}) =>
      'Push ${branch} and set its upstream tracking branch.';

  /// en: 'Publish'
  String get publishButtonLabel => 'Publish';

  /// en: 'Sync branch'
  String get syncBranchLabel => 'Sync branch';

  /// en: 'Pull {behindCount} with rebase, then push {aheadCount}.'
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Pull ${behindCount} with rebase, then push ${aheadCount}.';

  /// en: 'Pull (rebase) then push'
  String get syncBranchButtonLabel => 'Pull (rebase) then push';

  /// en: 'Push branch'
  String get pushBranchLabel => 'Push branch';

  /// en: 'Push {count} to {upstream}.'
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Push ${count} to ${upstream}.';

  /// en: 'Push commits'
  String get pushBranchButtonLabel => 'Push commits';

  /// en: 'Pull updates'
  String get pullUpdatesLabel => 'Pull updates';

  /// en: 'Pull {count} from {upstream}.'
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Pull ${count} from ${upstream}.';

  /// en: 'Fetch from {upstream} and refresh upstream status.'
  String syncUpToDateDetail({required Object upstream}) =>
      'Fetch from ${upstream} and refresh upstream status.';
}

// Path: sync.panel
class Translations$sync$panel$en {
  Translations$sync$panel$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Loading remote status'
  String get loadingTitle => 'Loading remote status';

  /// en: 'Checking branch tracking information.'
  String get loadingMessage => 'Checking branch tracking information.';

  /// en: 'Remote status unavailable'
  String get remoteStatusUnavailable => 'Remote status unavailable';

  /// en: 'no upstream'
  String get noUpstream => 'no upstream';

  /// en: 'Ahead'
  String get aheadLabel => 'Ahead';

  /// en: 'Behind'
  String get behindLabel => 'Behind';

  /// en: 'Tree'
  String get treeLabel => 'Tree';

  /// en: 'Running sync…'
  String get runningSync => 'Running sync…';

  /// en: 'Fetching…'
  String get fetching => 'Fetching…';

  /// en: 'Fetch only'
  String get fetchOnly => 'Fetch only';

  /// en: 'Sync failed'
  String get syncFailed => 'Sync failed';

  /// en: 'Force push (with lease)'
  String get forcePushRecoveryLabel => 'Force push (with lease)';

  /// en: 'Conflicts to resolve'
  String get conflictsToResolveTitle => 'Conflicts to resolve';

  /// en: '{count} need resolving: {list}'
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} need resolving: ${list}';

  /// en: 'Resolve conflicts'
  String get resolveConflicts => 'Resolve conflicts';

  /// en: 'Working…'
  String get workingEllipsis => 'Working…';

  /// en: 'Last activity: {operation}'
  String lastActivity({required Object operation}) =>
      'Last activity: ${operation}';

  /// en: 'No output.'
  String get noOutput => 'No output.';

  /// en: 'Resolved {count}.'
  String resolvedConflicts({required Object count}) => 'Resolved ${count}.';

  /// en: 'Cancelled, working tree unchanged.'
  String get cancelledUnchanged => 'Cancelled, working tree unchanged.';

  /// en: '{count} have uncommitted edits, commit them first to rebase-sync ({list}).'
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} have uncommitted edits, commit them first to rebase-sync (${list}).';

  /// en: 'Cannot force-push: no upstream is configured for "{branch}".'
  String noUpstreamForForcePush({required Object branch}) =>
      'Cannot force-push: no upstream is configured for "${branch}".';
}

// Path: sync.forcePush
class Translations$sync$forcePush$en {
  Translations$sync$forcePush$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Force push (with lease)?'
  String get confirmTitle => 'Force push (with lease)?';

  /// en: 'Target: {remote}/{branch}'
  String target({required Object remote, required Object branch}) =>
      'Target: ${remote}/${branch}';

  /// en: 'This rewrites the remote branch with your local history. With lease aborts if someone pushed to the remote after your last fetch, but already-fetched changes will still be overwritten. Use only when you intended a rebase or amend that diverged the branch.'
  String get warning =>
      'This rewrites the remote branch with your local history. With lease aborts if someone pushed to the remote after your last fetch, but already-fetched changes will still be overwritten. Use only when you intended a rebase or amend that diverged the branch.';

  /// en: 'Force push'
  String get confirmButton => 'Force push';
}

// Path: xray.board
class Translations$xray$board$en {
  Translations$xray$board$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'moves with another module'
  String get movesWithModule => 'moves with another module';

  /// en: '(one) {{n} reviewer} (other) {{n} reviewers}'
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} reviewer',
        other: '${n} reviewers',
      );

  /// en: 'Territory'
  String get territory => 'Territory';

  /// en: 'unreviewed'
  String get unreviewed => 'unreviewed';
}

// Path: xray.cadence
class Translations$xray$cadence$en {
  Translations$xray$cadence$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{sum} commits · {days} days {lines}'
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commits · ${days} days\n${lines}';

  /// en: '{n} commits on {label}'
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commits on ${label}';

  /// en: '{n}-day gap · {label}'
  String gapTooltip({required Object n, required Object label}) =>
      '${n}-day gap · ${label}';

  /// en: '{n} reflog events on {label}'
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} reflog events on ${label}';
}

// Path: xray.cards
class Translations$xray$cards$en {
  Translations$xray$cards$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$xray$cards$branchModel$en branchModel =
      Translations$xray$cards$branchModel$en.internal(_root);
  late final Translations$xray$cards$bursty$en bursty =
      Translations$xray$cards$bursty$en.internal(_root);
  late final Translations$xray$cards$hiddenRefs$en hiddenRefs =
      Translations$xray$cards$hiddenRefs$en.internal(_root);
  late final Translations$xray$cards$keystone$en keystone =
      Translations$xray$cards$keystone$en.internal(_root);
  late final Translations$xray$cards$machineHistory$en machineHistory =
      Translations$xray$cards$machineHistory$en.internal(_root);
  late final Translations$xray$cards$migration$en migration =
      Translations$xray$cards$migration$en.internal(_root);
  late final Translations$xray$cards$narrowHotspot$en narrowHotspot =
      Translations$xray$cards$narrowHotspot$en.internal(_root);
  late final Translations$xray$cards$noTags$en noTags =
      Translations$xray$cards$noTags$en.internal(_root);
  late final Translations$xray$cards$reflog$en reflog =
      Translations$xray$cards$reflog$en.internal(_root);
  late final Translations$xray$cards$singleOwner$en singleOwner =
      Translations$xray$cards$singleOwner$en.internal(_root);
}

// Path: xray.cardTitle
class Translations$xray$cardTitle$en {
  Translations$xray$cardTitle$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'branches'
  String get branches => 'branches';

  /// en: 'bursty'
  String get bursty => 'bursty';

  /// en: 'hidden refs'
  String get hiddenRefs => 'hidden refs';

  /// en: 'machine-heavy'
  String get machineHeavy => 'machine-heavy';

  /// en: 'migration'
  String get migration => 'migration';

  /// en: 'narrow hotspot'
  String get narrowHotspot => 'narrow hotspot';

  /// en: 'no tags'
  String get noTags => 'no tags';

  /// en: 'reflog'
  String get reflog => 'reflog';

  /// en: 'single-owner'
  String get singleOwner => 'single-owner';
}

// Path: xray.grain
class Translations$xray$grain$en {
  Translations$xray$grain$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'coarsest — top-level modules'
  String get coarsest => 'coarsest — top-level modules';

  /// en: 'finest grain'
  String get finest => 'finest grain';

  /// en: 'mid grain'
  String get mid => 'mid grain';

  /// en: 'one characteristic scale'
  String get oneCharacteristic => 'one characteristic scale';
}

// Path: xray.header
class Translations$xray$header$en {
  Translations$xray$header$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'dirty'
  String get dirtyBadge => 'dirty';

  /// en: 'machine'
  String get machineChip => 'machine';

  /// en: 'Refresh'
  String get refresh => 'Refresh';

  /// en: 'Refreshing...'
  String get refreshing => 'Refreshing...';

  /// en: 'Repo X-Ray'
  String get title => 'Repo X-Ray';
}

// Path: xray.hotspot
class Translations$xray$hotspot$en {
  Translations$xray$hotspot$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'cluster peers'
  String get clusterPeers => 'cluster peers';

  /// en: 'co-changers'
  String get coChangers => 'co-changers';

  /// en: 'keystone'
  String get keystone => 'keystone';

  /// en: 'keystone φ={score}'
  String keystoneScore({required Object score}) => 'keystone  φ=${score}';
}

// Path: xray.inspector
class Translations$xray$inspector$en {
  Translations$xray$inspector$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'branch'
  String get branchLabel => 'branch';

  /// en: 'human · {n} machine'
  String commitsHumanMachine({required Object n}) => 'human · ${n} machine';

  /// en: 'commits'
  String get commitsLabel => 'commits';

  /// en: 'confidence'
  String get confidenceLabel => 'confidence';

  /// en: 'curl'
  String get curlLabel => 'curl';

  /// en: 'engine'
  String get engineSection => 'engine';

  /// en: 'gradient'
  String get gradientLabel => 'gradient';

  /// en: 'harmonic'
  String get harmonicLabel => 'harmonic';

  /// en: 'head'
  String get headLabel => 'head';

  /// en: 'hidden refs'
  String get hiddenRefsLabel => 'hidden refs';

  /// en: '(one) {{n} merge} (other) {{n} merges}'
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} merge',
        other: '${n} merges',
      );

  /// en: 'no tags'
  String get noTags => 'no tags';

  /// en: 'notes'
  String get notesLabel => 'notes';

  /// en: 'Open commit'
  String get openCommit => 'Open commit';

  /// en: 'path'
  String get pathLabel => 'path';

  /// en: '{n} remote'
  String remoteCount({required Object n}) => '${n} remote';

  /// en: 'renames'
  String get renamesLabel => 'renames';

  /// en: 'scanned {time}'
  String scannedAt({required Object time}) => 'scanned ${time}';

  /// en: '{n} selected'
  String selectedCount({required Object n}) => '${n} selected';

  /// en: 'linear'
  String get shapeLinear => 'linear';

  /// en: 'merge-heavy'
  String get shapeMergeHeavy => 'merge-heavy';

  /// en: 'mostly linear'
  String get shapeMostlyLinear => 'mostly linear';

  /// en: '(one) {{n} stash} (other) {{n} stashes}'
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} stash',
        other: '${n} stashes',
      );

  /// en: 'stress'
  String get stressLabel => 'stress';

  /// en: '(one) {{n} tag} (other) {{n} tags}'
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} tag',
        other: '${n} tags',
      );

  /// en: '(one) {{n} worktree} (other) {{n} worktrees}'
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} worktree',
        other: '${n} worktrees',
      );
}

// Path: xray.loadingCard
class Translations$xray$loadingCard$en {
  Translations$xray$loadingCard$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Probing Git history, refs, cadence, and hotspots.'
  String get buildingMessage =>
      'Probing Git history, refs, cadence, and hotspots.';

  /// en: 'Building Repo X-Ray'
  String get buildingTitle => 'Building Repo X-Ray';

  /// en: 'Open the panel again to probe the current repository.'
  String get idleMessage =>
      'Open the panel again to probe the current repository.';

  /// en: 'Repo X-Ray'
  String get idleTitle => 'Repo X-Ray';

  /// en: 'Repo X-Ray unavailable'
  String get unavailableTitle => 'Repo X-Ray unavailable';
}

// Path: xray.metabolism
class Translations$xray$metabolism$en {
  Translations$xray$metabolism$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{n}d half-life'
  String halfLife({required Object n}) => '${n}d half-life';
}

// Path: xray.multi
class Translations$xray$multi$en {
  Translations$xray$multi$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {{n} cluster} (other) {{n} clusters}'
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} cluster',
        other: '${n} clusters',
      );

  /// en: 'cluster {id}'
  String clusterSingle({required Object id}) => 'cluster ${id}';

  /// en: '{parts} coupling'
  String couplingSuffix({required Object parts}) => '${parts} coupling';

  /// en: '{n} external'
  String externalCount({required Object n}) => '${n} external';

  /// en: '{n} mutual'
  String mutualCount({required Object n}) => '${n} mutual';
}

// Path: xray.recency
class Translations$xray$recency$en {
  Translations$xray$recency$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{n}d'
  String days({required Object n}) => '${n}d';

  /// en: '{n}mo'
  String months({required Object n}) => '${n}mo';

  /// en: 'today'
  String get today => 'today';

  /// en: '{n}w'
  String weeks({required Object n}) => '${n}w';

  /// en: '(one) {{n}y} (other) {{n}y}'
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n}y',
        other: '${n}y',
      );
}

// Path: xray.rings
class Translations$xray$rings$en {
  Translations$xray$rings$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'one blended structure'
  String get hintOneBlended => 'one blended structure';

  /// en: 'self-similar'
  String get hintSelfSimilar => 'self-similar';

  /// en: 'One blended structure — no separable module scales resolve yet.'
  String get oneBlendedBody =>
      'One blended structure — no separable module scales resolve yet.';

  /// en: 'Over history'
  String get overHistory => 'Over history';

  /// en: 'parts'
  String get parts => 'parts';

  /// en: 'reading structure…'
  String get readingHint => 'reading structure…';

  /// en: '(one) {{n} scale} (other) {{n} scales}'
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} scale',
        other: '${n} scales',
      );

  /// en: 'a structural scale dissolved'
  String get scaleDissolved => 'a structural scale dissolved';

  /// en: 'a structural scale emerged'
  String get scaleEmerged => 'a structural scale emerged';

  /// en: 'scale spectrum'
  String get scaleSpectrum => 'scale spectrum';

  /// en: 'Self-similar — structure repeats across scales, with no single characteristic level.'
  String get selfSimilarBody =>
      'Self-similar — structure repeats across scales, with no single characteristic level.';

  /// en: '(one) {{n} shift in history} (other) {{n} shifts in history}'
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} shift in history',
        other: '${n} shifts in history',
      );

  /// en: '(one) {{n} structural shift} (other) {{n} structural shifts}'
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} structural shift',
        other: '${n} structural shifts',
      );

  /// en: 'Growth rings'
  String get title => 'Growth rings';

  /// en: 'unavailable'
  String get unavailable => 'unavailable';
}

// Path: xray.stats
class Translations$xray$stats$en {
  Translations$xray$stats$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'alive'
  String get alive => 'alive';

  /// en: 'files'
  String get files => 'files';

  /// en: 'last touched'
  String get lastTouched => 'last touched';

  /// en: '(one) {owner} (other) {owners}'
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'owner',
        other: 'owners',
      );

  /// en: 'touches'
  String get touches => 'touches';
}

// Path: xray.stratumLabel
class Translations$xray$stratumLabel$en {
  Translations$xray$stratumLabel$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'current'
  String get current => 'current';

  /// en: 'legacy'
  String get legacy => 'legacy';

  /// en: 'repo zone'
  String get zone => 'repo zone';
}

// Path: xray.summary
class Translations$xray$summary$en {
  Translations$xray$summary$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Analysis failed: {error}'
  String analysisFailed({required Object error}) => 'Analysis failed: ${error}';

  /// en: 'Analyze'
  String get analyze => 'Analyze';

  /// en: 'Summary copied to clipboard.'
  String get copied => 'Summary copied to clipboard.';

  /// en: 'direction'
  String get directionHint => 'direction';

  /// en: 'Download'
  String get download => 'Download';

  /// en: 'Run Logos analysis to map this repository's structure and regions. (tw: slop rn)'
  String get emptyState =>
      'Run Logos analysis to map this repository\'s structure and regions.\n(tw: slop rn)';

  /// en: 'Exit'
  String get exit => 'Exit';

  /// en: 'Reading the repo and clustering features…'
  String get generating => 'Reading the repo and clustering features…';

  /// en: 'No AI model configured.'
  String get noModel => 'No AI model configured.';

  /// en: 'no AI model configured'
  String get noModelConfigured => 'no AI model configured';

  /// en: 'present with {label}'
  String presentWith({required Object label}) => 'present with ${label}';

  /// en: 'presenting with {label}…'
  String presentingWith({required Object label}) => 'presenting with ${label}…';

  /// en: 'Re-analyze'
  String get reanalyze => 'Re-analyze';

  /// en: 'Save repository summary'
  String get saveDialogTitle => 'Save repository summary';

  /// en: 'Save failed: {error}'
  String saveFailed({required Object error}) => 'Save failed: ${error}';

  /// en: 'Save presentation'
  String get savePresentationDialogTitle => 'Save presentation';

  /// en: 'Saved to {path}'
  String savedTo({required Object path}) => 'Saved to ${path}';
}

// Path: xray.tabs
class Translations$xray$tabs$en {
  Translations$xray$tabs$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Map'
  String get map => 'Map';

  /// en: 'Signals'
  String get signals => 'Signals';

  /// en: 'Summary'
  String get summary => 'Summary';

  /// en: 'Time'
  String get time => 'Time';
}

// Path: xray.trajectory
class Translations$xray$trajectory$en {
  Translations$xray$trajectory$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'connectivity'
  String get connectivity => 'connectivity';

  /// en: '{n} events'
  String events({required Object n}) => '${n} events';

  /// en: 'Open in Orrery'
  String get openInOrrery => 'Open in Orrery';

  /// en: 'reading history…'
  String get readingHint => 'reading history…';

  /// en: '{n} snapshots'
  String snapshots({required Object n}) => '${n} snapshots';

  /// en: 'Steady — no structural events in this window.'
  String get steady => 'Steady — no structural events in this window.';

  /// en: 'Structural trajectory'
  String get title => 'Structural trajectory';
}

// Path: xray.verdict
class Translations$xray$verdict$en {
  Translations$xray$verdict$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{pct}% canonical'
  String canonical({required Object pct}) => '${pct}% canonical';

  /// en: '{archetype} · {canonical}% canonical · {decisive}% decisive'
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% canonical · ${decisive}% decisive';
}

// Path: changes.mergeEditor.trust
class Translations$changes$mergeEditor$trust$en {
  Translations$changes$mergeEditor$trust$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'manual'
  String get manual => 'manual';

  /// en: 'safe'
  String get safe => 'safe';

  /// en: 'guided'
  String get guided => 'guided';

  /// en: 'assisted'
  String get assisted => 'assisted';

  /// en: 'full'
  String get full => 'full';

  /// en: 'trust: {label}'
  String label({required Object label}) => 'trust: ${label}';
}

// Path: changes.mergeEditor.keyHints
class Translations$changes$mergeEditor$keyHints$en {
  Translations$changes$mergeEditor$keyHints$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'accept'
  String get accept => 'accept';

  /// en: 'other'
  String get other => 'other';

  /// en: 'both'
  String get both => 'both';

  /// en: 'navigate'
  String get navigate => 'navigate';

  /// en: 'jump next'
  String get jumpNext => 'jump next';
}

// Path: changes.mergeFlow.op
class Translations$changes$mergeFlow$op$en {
  Translations$changes$mergeFlow$op$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'merge'
  String get merge => 'merge';

  /// en: 'cherry-pick'
  String get cherryPick => 'cherry-pick';

  /// en: 'revert'
  String get revert => 'revert';

  /// en: 'resolve'
  String get resolve => 'resolve';

  /// en: 'switch'
  String get switchOp => 'switch';

  /// en: 'pull'
  String get pull => 'pull';

  /// en: 'rebase'
  String get rebase => 'rebase';

  /// en: 'rebase {branch} onto {base}'
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebase ${branch} onto ${base}';
}

// Path: diff.pinned.tempo
class Translations$diff$pinned$tempo$en {
  Translations$diff$pinned$tempo$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Recent movement with one strong owner nearby.'
  String get hotOwnerLane => 'Recent movement with one strong owner nearby.';

  /// en: 'Recent movement from multiple hands nearby.'
  String get activeSeam => 'Recent movement from multiple hands nearby.';

  /// en: 'Long-lived lane with one dominant owner.'
  String get stableOwnerLane => 'Long-lived lane with one dominant owner.';

  /// en: 'Shared seam that has accumulated over time.'
  String get sharedLongLivedSeam =>
      'Shared seam that has accumulated over time.';

  /// en: 'Shared lane with no single dominant owner.'
  String get sharedLane => 'Shared lane with no single dominant owner.';

  /// en: 'History is still resolving around this line.'
  String get resolving => 'History is still resolving around this line.';
}

// Path: diff.pinned.tone
class Translations$diff$pinned$tone$en {
  Translations$diff$pinned$tone$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Hot'
  String get hot => 'Hot';

  /// en: 'Novel'
  String get novel => 'Novel';

  /// en: 'Contested'
  String get contested => 'Contested';

  /// en: 'Spreading'
  String get spreading => 'Spreading';

  /// en: 'Stable'
  String get stable => 'Stable';
}

// Path: diff.pinned.summary
class Translations$diff$pinned$summary$en {
  Translations$diff$pinned$summary$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Lives in {concept}'
  String livesIn({required Object concept}) => 'Lives in ${concept}';

  /// en: 'Sits in a local seam'
  String get sitsInLocalSeam => 'Sits in a local seam';

  /// en: 'worked mostly by {owner} nearby'
  String workedMostlyBy({required Object owner}) =>
      'worked mostly by ${owner} nearby';

  /// en: '(one) {echoes in {n} other spot} (other) {echoes in {n} other spots}'
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'echoes in ${n} other spot',
        other: 'echoes in ${n} other spots',
      );

  /// en: 'inspect {path} next{detail}'
  String inspectNext({required Object path, required Object detail}) =>
      'inspect ${path} next${detail}';

  /// en: ' ({reason})'
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class Translations$diff$pinned$tightness$en {
  Translations$diff$pinned$tightness$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'tight fit'
  String get tight => 'tight fit';

  /// en: 'close fit'
  String get close => 'close fit';

  /// en: 'loose fit'
  String get loose => 'loose fit';
}

// Path: diff.pinned.witness
class Translations$diff$pinned$witness$en {
  Translations$diff$pinned$witness$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Nearby support · {label}'
  String nearbySupport({required Object label}) => 'Nearby support · ${label}';

  /// en: 'Localized move · {label}'
  String localizedMove({required Object label}) => 'Localized move · ${label}';

  /// en: 'Surprising move · {label}'
  String surprisingMove({required Object label}) =>
      'Surprising move · ${label}';
}

// Path: diff.pinned.integrity
class Translations$diff$pinned$integrity$en {
  Translations$diff$pinned$integrity$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Stable structure'
  String get stableStructure => 'Stable structure';

  /// en: 'Conflicting signals'
  String get conflictingSignals => 'Conflicting signals';

  /// en: 'Novel shape'
  String get novelShape => 'Novel shape';
}

// Path: diff.pinned.related
class Translations$diff$pinned$related$en {
  Translations$diff$pinned$related$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Test mirror'
  String get testMirror => 'Test mirror';

  /// en: 'Semantic + history sibling'
  String get semanticHistorySibling => 'Semantic + history sibling';

  /// en: 'Recent co-change'
  String get recentCoChange => 'Recent co-change';

  /// en: 'Semantic sibling'
  String get semanticSibling => 'Semantic sibling';

  /// en: 'Related structure'
  String get relatedStructure => 'Related structure';

  /// en: 'tightly bound'
  String get tightlyBound => 'tightly bound';

  /// en: 'orbiting'
  String get orbiting => 'orbiting';

  /// en: 'weakly coupled'
  String get weaklyCoupled => 'weakly coupled';

  /// en: '{base} · {tier}'
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class Translations$diff$pinned$axis$en {
  Translations$diff$pinned$axis$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'history trail'
  String get historyTrail => 'history trail';

  /// en: 'test mirror lane'
  String get testMirrorLane => 'test mirror lane';

  /// en: 'structural lane'
  String get structuralLane => 'structural lane';

  /// en: 'semantic neighbourhood'
  String get semanticNeighbourhood => 'semantic neighbourhood';
}

// Path: history.commitLede.semantics
class Translations$history$commitLede$semantics$en {
  Translations$history$commitLede$semantics$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'high importance'
  String get importanceHigh => 'high importance';

  /// en: 'moderate importance'
  String get importanceModerate => 'moderate importance';

  /// en: 'mostly additions'
  String get mostlyAdditions => 'mostly additions';

  /// en: 'mostly deletions'
  String get mostlyDeletions => 'mostly deletions';

  /// en: 'tightly coupled files'
  String get tightlyCoupled => 'tightly coupled files';

  /// en: 'overlaps your working tree'
  String get overlapsWorkingTree => 'overlaps your working tree';
}

// Path: onboarding.repo.doors
class Translations$onboarding$repo$doors$en {
  Translations$onboarding$repo$doors$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$onboarding$repo$doors$open$en open =
      Translations$onboarding$repo$doors$open$en.internal(_root);
  late final Translations$onboarding$repo$doors$clone$en clone =
      Translations$onboarding$repo$doors$clone$en.internal(_root);
  late final Translations$onboarding$repo$doors$create$en create =
      Translations$onboarding$repo$doors$create$en.internal(_root);
}

// Path: onboarding.repo.cloneForm
class Translations$onboarding$repo$cloneForm$en {
  Translations$onboarding$repo$cloneForm$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Clone from URL'
  String get title => 'Clone from URL';

  /// en: 'Repository URL'
  String get urlLabel => 'Repository URL';

  /// en: 'Target folder'
  String get targetLabel => 'Target folder';

  /// en: 'Browse…'
  String get browse => 'Browse…';

  /// en: 'Clone'
  String get clone => 'Clone';

  /// en: 'Cloning…'
  String get cloning => 'Cloning…';
}

// Path: onboarding.repo.pickers
class Translations$onboarding$repo$pickers$en {
  Translations$onboarding$repo$pickers$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Open Repository'
  String get openRepository => 'Open Repository';

  /// en: 'Create Repository'
  String get createRepository => 'Create Repository';

  /// en: 'Clone Target'
  String get cloneTarget => 'Clone Target';
}

// Path: onboarding.repo.errors
class Translations$onboarding$repo$errors$en {
  Translations$onboarding$repo$errors$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'URL and target path required.'
  String get urlAndTargetRequired => 'URL and target path required.';

  /// en: 'Failed to create repository.'
  String get createFailed => 'Failed to create repository.';

  /// en: 'Failed to clone repository.'
  String get cloneFailed => 'Failed to clone repository.';
}

// Path: onboarding.preview.panels
class Translations$onboarding$preview$panels$en {
  Translations$onboarding$preview$panels$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'repo x-ray'
  String get xray => 'repo x-ray';

  /// en: 'settings'
  String get settings => 'settings';
}

// Path: onboarding.preview.sidebar
class Translations$onboarding$preview$sidebar$en {
  Translations$onboarding$preview$sidebar$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Projects'
  String get projectsHeader => 'Projects';
}

// Path: onboarding.preview.changes
class Translations$onboarding$preview$changes$en {
  Translations$onboarding$preview$changes$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{staged} of {total} files'
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} of ${total} files';

  /// en: '{n} staged'
  String stagedCount({required Object n}) => '${n} staged';

  /// en: 'Commit message…'
  String get commitMessageHint => 'Commit message…';

  /// en: 'Commit & push'
  String get commitAndPush => 'Commit & push';
}

// Path: onboarding.preview.history
class Translations$onboarding$preview$history$en {
  Translations$onboarding$preview$history$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'History'
  String get header => 'History';

  /// en: 'viewing last 20 commits'
  String get viewingLast => 'viewing last 20 commits';

  /// en: 'IN FLIGHT'
  String get inFlight => 'IN FLIGHT';

  /// en: 'you'
  String get you => 'you';

  /// en: 'teach fox to sniff before swallowing'
  String get commit1 => 'teach fox to sniff before swallowing';

  /// en: 'amber: hold scent overnight'
  String get commit2 => 'amber: hold scent overnight';

  /// en: 'retire cabbage in favor of amber + thorn'
  String get commit3 => 'retire cabbage in favor of amber + thorn';

  /// en: 'thorn guards the gate'
  String get commit4 => 'thorn guards the gate';
}

// Path: onboarding.preview.branches
class Translations$onboarding$preview$branches$en {
  Translations$onboarding$preview$branches$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'BRANCHES'
  String get lensBranches => 'BRANCHES';

  /// en: 'PRs'
  String get lensPRs => 'PRs';

  /// en: 'absorbed'
  String get absorbed => 'absorbed';

  /// en: 'desk'
  String get desk => 'desk';

  /// en: 'HEAD'
  String get head => 'HEAD';

  /// en: '→ tracking: {ref}'
  String tracking({required Object ref}) => '→ tracking: ${ref}';
}

// Path: onboarding.preview.diff
class Translations$onboarding$preview$diff$en {
  Translations$onboarding$preview$diff$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Your personal Git client.'
  String get readmeTagline => 'Your personal Git client.';
}

// Path: releaseNotes.about.whyFlutter
class Translations$releaseNotes$about$whyFlutter$en {
  Translations$releaseNotes$about$whyFlutter$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'WHY FLUTTER?'
  String get question => 'WHY FLUTTER?';

  /// en: 'The first version of this was a Tauri app (Rust + TypeScript). I already knew it felt slow. Then I caught a streamer saying the same thing on a stream I don't usually watch, and that was the nudge to finally swap. He didn't suggest Flutter; far from it. I found Dart on my own, threw together a prototype, and startup went from about 15 seconds to under a second. Night and day. Farewell Tauri era. Flutter's rendering pipeline is closer to a game engine than a DOM, and for a desktop app where the UI is the product that's everything. Dart turned out to be a genuinely good language too. The math behind the spectral engine was prototyped in Rust first, so that work carried over fine. Flutter is cross-platform by default, which is great, but it's Googley in nature so there are a few quirks.'
  String get body =>
      'The first version of this was a Tauri app (Rust + TypeScript). I already knew it felt slow. Then I caught a streamer saying the same thing on a stream I don\'t usually watch, and that was the nudge to finally swap. He didn\'t suggest Flutter; far from it. I found Dart on my own, threw together a prototype, and startup went from about 15 seconds to under a second. Night and day. Farewell Tauri era.\n\nFlutter\'s rendering pipeline is closer to a game engine than a DOM, and for a desktop app where the UI is the product that\'s everything. Dart turned out to be a genuinely good language too. The math behind the spectral engine was prototyped in Rust first, so that work carried over fine.\n\nFlutter is cross-platform by default, which is great, but it\'s Googley in nature so there are a few quirks.';
}

// Path: releaseNotes.about.spectralEngine
class Translations$releaseNotes$about$spectralEngine$en {
  Translations$releaseNotes$about$spectralEngine$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'WHAT IS THE SPECTRAL ENGINE?'
  String get question => 'WHAT IS THE SPECTRAL ENGINE?';

  /// en: 'Every time you commit, the files you change together form patterns over time. The spectral engine reads your commit graph and decomposes those co-change patterns into signals: which files are coupled, how tightly, and what structural role they play in the repo. Basically spectral analysis on your development history. In a git client. On purpose. The math is new, so I'm treating it like game feel: tune it, test it, adjust it, and keep going until the signals feel correct. Those signals feed into everything. The seismograph in history, the painted bars under commit subjects, the review system, Muse, the file constellation. The whole app reasons from this layer down, not the other way around.'
  String get body =>
      'Every time you commit, the files you change together form patterns over time. The spectral engine reads your commit graph and decomposes those co-change patterns into signals: which files are coupled, how tightly, and what structural role they play in the repo. Basically spectral analysis on your development history. In a git client. On purpose.\n\nThe math is new, so I\'m treating it like game feel: tune it, test it, adjust it, and keep going until the signals feel correct.\n\nThose signals feed into everything. The seismograph in history, the painted bars under commit subjects, the review system, Muse, the file constellation. The whole app reasons from this layer down, not the other way around.';
}

// Path: releaseNotes.about.whereGoing
class Translations$releaseNotes$about$whereGoing$en {
  Translations$releaseNotes$about$whereGoing$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'WHERE IS THIS GOING?'
  String get question => 'WHERE IS THIS GOING?';

  /// en: 'The first milestone is full parity with GitHub Desktop, SourceTree, and GitKraken. A cross-platform git client that feels fast and handles the fundamentals better than anything else. That's mostly here. The spectral engine already gives us an advantage for operations that other clients make you think through manually. Past that, the goal is to surpass every other git client in speed, accessibility, intelligence, and overall UX. There's more in the pipeline than what's announced here.'
  String get body =>
      'The first milestone is full parity with GitHub Desktop, SourceTree, and GitKraken. A cross-platform git client that feels fast and handles the fundamentals better than anything else. That\'s mostly here. The spectral engine already gives us an advantage for operations that other clients make you think through manually.\n\nPast that, the goal is to surpass every other git client in speed, accessibility, intelligence, and overall UX. There\'s more in the pipeline than what\'s announced here.';
}

// Path: settings.commitPreview.title
class Translations$settings$commitPreview$title$en {
  Translations$settings$commitPreview$title$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$settings$commitPreview$title$verbLed$en verbLed =
      Translations$settings$commitPreview$title$verbLed$en.internal(_root);
  late final Translations$settings$commitPreview$title$descriptive$en
  descriptive =
      Translations$settings$commitPreview$title$descriptive$en.internal(_root);
  late final Translations$settings$commitPreview$title$narrative$en narrative =
      Translations$settings$commitPreview$title$narrative$en.internal(_root);
}

// Path: settings.commitPreview.base
class Translations$settings$commitPreview$base$en {
  Translations$settings$commitPreview$base$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$settings$commitPreview$base$verbLed$en verbLed =
      Translations$settings$commitPreview$base$verbLed$en.internal(_root);
  late final Translations$settings$commitPreview$base$descriptive$en
  descriptive =
      Translations$settings$commitPreview$base$descriptive$en.internal(_root);
  late final Translations$settings$commitPreview$base$narrative$en narrative =
      Translations$settings$commitPreview$base$narrative$en.internal(_root);
}

// Path: settings.commitPreview.balancedSuffix
class Translations$settings$commitPreview$balancedSuffix$en {
  Translations$settings$commitPreview$balancedSuffix$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$settings$commitPreview$balancedSuffix$verbLed$en
  verbLed =
      Translations$settings$commitPreview$balancedSuffix$verbLed$en.internal(
        _root,
      );
  late final Translations$settings$commitPreview$balancedSuffix$descriptive$en
  descriptive =
      Translations$settings$commitPreview$balancedSuffix$descriptive$en.internal(
        _root,
      );
  late final Translations$settings$commitPreview$balancedSuffix$narrative$en
  narrative =
      Translations$settings$commitPreview$balancedSuffix$narrative$en.internal(
        _root,
      );
}

// Path: settings.commitPreview.everythingSuffix
class Translations$settings$commitPreview$everythingSuffix$en {
  Translations$settings$commitPreview$everythingSuffix$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations
  late final Translations$settings$commitPreview$everythingSuffix$verbLed$en
  verbLed =
      Translations$settings$commitPreview$everythingSuffix$verbLed$en.internal(
        _root,
      );
  late final Translations$settings$commitPreview$everythingSuffix$descriptive$en
  descriptive =
      Translations$settings$commitPreview$everythingSuffix$descriptive$en.internal(
        _root,
      );
  late final Translations$settings$commitPreview$everythingSuffix$narrative$en
  narrative =
      Translations$settings$commitPreview$everythingSuffix$narrative$en.internal(
        _root,
      );
}

// Path: xray.cards.branchModel
class Translations$xray$cards$branchModel$en {
  Translations$xray$cards$branchModel$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'The repository has enough branch surface to reward branch-aware navigation.'
  String get broadClaim =>
      'The repository has enough branch surface to reward branch-aware navigation.';

  /// en: 'Branch model has surface area'
  String get broadTitle => 'Branch model has surface area';

  /// en: '{count} local branches.'
  String localBranchesDetail({required Object count}) =>
      '${count} local branches.';

  /// en: 'Local branches'
  String get localBranchesLabel => 'Local branches';

  /// en: '{count} remote branches.'
  String remoteBranchesDetail({required Object count}) =>
      '${count} remote branches.';

  /// en: 'Remote branches'
  String get remoteBranchesLabel => 'Remote branches';

  /// en: 'The visible branch model is narrow.'
  String get simpleClaim => 'The visible branch model is narrow.';

  /// en: 'Simple branch model'
  String get simpleTitle => 'Simple branch model';
}

// Path: xray.cards.bursty
class Translations$xray$cards$bursty$en {
  Translations$xray$cards$bursty$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Work lands in concentrated bursts rather than a flat daily rhythm.'
  String get claim =>
      'Work lands in concentrated bursts rather than a flat daily rhythm.';

  /// en: 'Bursty development cadence'
  String get title => 'Bursty development cadence';
}

// Path: xray.cards.hiddenRefs
class Translations$xray$cards$hiddenRefs$en {
  Translations$xray$cards$hiddenRefs$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '{count} refs live outside normal branch/tag space.'
  String claim({required Object count}) =>
      '${count} refs live outside normal branch/tag space.';

  /// en: '{count} refs outside heads/remotes/tags.'
  String evidenceDetail({required Object count}) =>
      '${count} refs outside heads/remotes/tags.';

  /// en: 'Hidden refs'
  String get evidenceLabel => 'Hidden refs';

  /// en: 'Namespaces'
  String get namespacesLabel => 'Namespaces';

  /// en: 'Hidden Git namespaces'
  String get title => 'Hidden Git namespaces';
}

// Path: xray.cards.keystone
class Translations$xray$cards$keystone$en {
  Translations$xray$cards$keystone$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '(one) {One file carries disproportionate co-change weight relative to its touch count.} (other) {A small set of files carry disproportionate co-change weight relative to their touch counts.}'
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
    n,
    one:
        'One file carries disproportionate co-change weight relative to its touch count.',
    other:
        'A small set of files carry disproportionate co-change weight relative to their touch counts.',
  );

  /// en: '(one) {{n} touch · pull φ={score}} (other) {{n} touches · pull φ={score}}'
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: '${n} touch · pull φ=${score}',
        other: '${n} touches · pull φ=${score}',
      );

  /// en: '(one) {Keystone bridge-file} (other) {{n} keystone bridge-files}'
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(
        n,
        one: 'Keystone bridge-file',
        other: '${n} keystone bridge-files',
      );
}

// Path: xray.cards.machineHistory
class Translations$xray$cards$machineHistory$en {
  Translations$xray$cards$machineHistory$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Checkpoint-style commits materially distort naive history metrics.'
  String get claim =>
      'Checkpoint-style commits materially distort naive history metrics.';

  /// en: '{count} commits matched machine/session patterns.'
  String machineCommitsDetail({required Object count}) =>
      '${count} commits matched machine/session patterns.';

  /// en: 'Machine commits'
  String get machineCommitsLabel => 'Machine commits';

  /// en: '{raw} raw commits vs {filtered} filtered commits.'
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} raw commits vs ${filtered} filtered commits.';

  /// en: 'Raw vs filtered'
  String get rawVsFilteredLabel => 'Raw vs filtered';

  /// en: 'Machine history dominates raw metrics'
  String get title => 'Machine history dominates raw metrics';
}

// Path: xray.cards.migration
class Translations$xray$cards$migration$en {
  Translations$xray$cards$migration$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'History shifts from `{older}` to `{newer}`, suggesting a stack or surface transition.'
  String claim({required Object older, required Object newer}) =>
      'History shifts from `${older}` to `${newer}`, suggesting a stack or surface transition.';

  /// en: '{touches} touches, last active {lastActive}.'
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} touches, last active ${lastActive}.';

  /// en: 'Architecture migration visible'
  String get title => 'Architecture migration visible';
}

// Path: xray.cards.narrowHotspot
class Translations$xray$cards$narrowHotspot$en {
  Translations$xray$cards$narrowHotspot$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'A small set of files and directories absorbs a disproportionate share of changes.'
  String get claim =>
      'A small set of files and directories absorbs a disproportionate share of changes.';

  /// en: 'Hotspot concentration is narrow'
  String get title => 'Hotspot concentration is narrow';

  /// en: '{path} accounts for {pct}% of the visible hotspot set.'
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} accounts for ${pct}% of the visible hotspot set.';

  /// en: 'Top hotspot'
  String get topHotspotLabel => 'Top hotspot';

  /// en: '{count} authors in this history slice.'
  String visibleAuthorsDetail({required Object count}) =>
      '${count} authors in this history slice.';

  /// en: 'Visible authors'
  String get visibleAuthorsLabel => 'Visible authors';
}

// Path: xray.cards.noTags
class Translations$xray$cards$noTags$en {
  Translations$xray$cards$noTags$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Git tags are not being used as a visible release or milestone layer.'
  String get claim =>
      'Git tags are not being used as a visible release or milestone layer.';

  /// en: '{count} remote endpoints configured.'
  String remoteEndpointsDetail({required Object count}) =>
      '${count} remote endpoints configured.';

  /// en: 'Remote endpoints'
  String get remoteEndpointsLabel => 'Remote endpoints';

  /// en: '0 tags found.'
  String get tagCountDetail => '0 tags found.';

  /// en: 'Tag count'
  String get tagCountLabel => 'Tag count';

  /// en: 'No formal release/tag trail'
  String get title => 'No formal release/tag trail';
}

// Path: xray.cards.reflog
class Translations$xray$cards$reflog$en {
  Translations$xray$cards$reflog$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Reflog volume suggests concentrated local iteration beyond published commits.'
  String get claim =>
      'Reflog volume suggests concentrated local iteration beyond published commits.';

  /// en: 'Peak reflog day'
  String get peakReflogDayLabel => 'Peak reflog day';

  /// en: 'Intense local editing sessions'
  String get title => 'Intense local editing sessions';
}

// Path: xray.cards.singleOwner
class Translations$xray$cards$singleOwner$en {
  Translations$xray$cards$singleOwner$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: '`{path}` is a heavily touched {kind} with one distinct visible author.'
  String claim({required Object path, required Object kind}) =>
      '`${path}` is a heavily touched ${kind} with one distinct visible author.';

  /// en: '{count} distinct authors.'
  String ownerCountDetail({required Object count}) =>
      '${count} distinct authors.';

  /// en: 'Owner count'
  String get ownerCountLabel => 'Owner count';

  /// en: 'Single-owner hotspot'
  String get title => 'Single-owner hotspot';

  /// en: 'Touch count'
  String get touchCountLabel => 'Touch count';

  /// en: '{count} touches in filtered history.'
  String touchDetailFiltered({required Object count}) =>
      '${count} touches in filtered history.';

  /// en: '{count} touches in raw history.'
  String touchDetailRaw({required Object count}) =>
      '${count} touches in raw history.';
}

// Path: onboarding.repo.doors.open
class Translations$onboarding$repo$doors$open$en {
  Translations$onboarding$repo$doors$open$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Open'
  String get title => 'Open';

  /// en: 'existing'
  String get subtitle => 'existing';

  /// en: 'one you already have'
  String get hint => 'one you already have';
}

// Path: onboarding.repo.doors.clone
class Translations$onboarding$repo$doors$clone$en {
  Translations$onboarding$repo$doors$clone$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Clone'
  String get title => 'Clone';

  /// en: 'from URL'
  String get subtitle => 'from URL';

  /// en: 'paste a remote URL'
  String get hint => 'paste a remote URL';
}

// Path: onboarding.repo.doors.create
class Translations$onboarding$repo$doors$create$en {
  Translations$onboarding$repo$doors$create$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Create'
  String get title => 'Create';

  /// en: 'new'
  String get subtitle => 'new';

  /// en: 'start something fresh'
  String get hint => 'start something fresh';
}

// Path: settings.commitPreview.title.verbLed
class Translations$settings$commitPreview$title$verbLed$en {
  Translations$settings$commitPreview$title$verbLed$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Let fox skip cookies that smell off'
  String get s0 => 'Let fox skip cookies that smell off';

  /// en: 'Train fox to refuse tampered cookies before swallowing'
  String get s2 => 'Train fox to refuse tampered cookies before swallowing';

  /// en: 'Compel fox to forensically vet every cookie at the gate'
  String get s3 => 'Compel fox to forensically vet every cookie at the gate';

  /// en: 'Teach fox to refuse bad cookies'
  String get def => 'Teach fox to refuse bad cookies';
}

// Path: settings.commitPreview.title.descriptive
class Translations$settings$commitPreview$title$descriptive$en {
  Translations$settings$commitPreview$title$descriptive$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'fox now picks the cookies'
  String get s0 => 'fox now picks the cookies';

  /// en: 'Cookie-inspection routine, drilled into fox'
  String get s2 => 'Cookie-inspection routine, drilled into fox';

  /// en: 'Cookie-vetting forensics, embedded in fox by repetition'
  String get s3 => 'Cookie-vetting forensics, embedded in fox by repetition';

  /// en: 'Cookie-sniff protocol, installed in fox'
  String get def => 'Cookie-sniff protocol, installed in fox';
}

// Path: settings.commitPreview.title.narrative
class Translations$settings$commitPreview$title$narrative$en {
  Translations$settings$commitPreview$title$narrative$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'the fox started skipping cookies that smelled wrong'
  String get s0 => 'the fox started skipping cookies that smelled wrong';

  /// en: 'Sat down with the fox and worked through which cookies to refuse'
  String get s2 =>
      'Sat down with the fox and worked through which cookies to refuse';

  /// en: 'Spent the better part of an afternoon convincing the fox that not every cookie offered is, in good faith, a cookie'
  String get s3 =>
      'Spent the better part of an afternoon convincing the fox that not every cookie offered is, in good faith, a cookie';

  /// en: 'Asked the fox to sniff cookies before eating them'
  String get def => 'Asked the fox to sniff cookies before eating them';
}

// Path: settings.commitPreview.base.verbLed
class Translations$settings$commitPreview$base$verbLed$en {
  Translations$settings$commitPreview$base$verbLed$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Fox glances. Anything off gets left.'
  String get s0 => 'Fox glances. Anything off gets left.';

  /// en: 'Fox inspects each token, declines anything off-scent, and notes the refusal on the porch.'
  String get s2 =>
      'Fox inspects each token, declines anything off-scent, and notes the refusal on the porch.';

  /// en: 'Fox circles each token, samples the air at three angles, refuses any that read wrong, and waits a beat to make sure the refusal sticks.'
  String get s3 =>
      'Fox circles each token, samples the air at three angles, refuses any that read wrong, and waits a beat to make sure the refusal sticks.';

  /// en: 'Fox sniffs each token now and politely declines the suspicious ones.'
  String get def =>
      'Fox sniffs each token now and politely declines the suspicious ones.';
}

// Path: settings.commitPreview.base.descriptive
class Translations$settings$commitPreview$base$descriptive$en {
  Translations$settings$commitPreview$base$descriptive$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'Soft pass on the weird ones, mostly.'
  String get s0 => 'Soft pass on the weird ones, mostly.';

  /// en: 'A documented refusal on every off-scent token, issued from the porch and noted.'
  String get s2 =>
      'A documented refusal on every off-scent token, issued from the porch and noted.';

  /// en: 'A notarized refusal per off-scent token, issued from the porch with one paw raised, the other still.'
  String get s3 =>
      'A notarized refusal per off-scent token, issued from the porch with one paw raised, the other still.';

  /// en: 'A polite refusal on suspicious tokens, issued from the porch.'
  String get def =>
      'A polite refusal on suspicious tokens, issued from the porch.';
}

// Path: settings.commitPreview.base.narrative
class Translations$settings$commitPreview$base$narrative$en {
  Translations$settings$commitPreview$base$narrative$en.internal(this._root);

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: 'The fox just sort of stopped eating the weird ones. Easy.'
  String get s0 => 'The fox just sort of stopped eating the weird ones. Easy.';

  /// en: 'Every token used to go down without much thought; now there’s a pause, a proper look, and a refusal for the ones that don’t sit right.'
  String get s2 =>
      'Every token used to go down without much thought; now there’s a pause, a proper look, and a refusal for the ones that don’t sit right.';

  /// en: 'Every token used to go down without thinking. Now: a pause. The air, taken in. The air, held. The fox watches the porch boards for the small twitch they sometimes have when something is off, and only then is the call made.'
  String get s3 =>
      'Every token used to go down without thinking. Now: a pause. The air, taken in. The air, held. The fox watches the porch boards for the small twitch they sometimes have when something is off, and only then is the call made.';

  /// en: 'Every token used to be swallowed without ceremony; now there’s a whiff first.'
  String get def =>
      'Every token used to be swallowed without ceremony; now there’s a whiff first.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  Translations$settings$commitPreview$balancedSuffix$verbLed$en.internal(
    this._root,
  );

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ' Porch is fine. Backyard is whatever.'
  String get s0 => ' Porch is fine. Backyard is whatever.';

  /// en: ' Porch swept after each refusal; backyard mud allowed within posted hours.'
  String get s2 =>
      ' Porch swept after each refusal; backyard mud allowed within posted hours.';

  /// en: ' Porch swept and re-swept; backyard mud catalogued by paw-print and weather, and the fox lingers at the threshold longer than before.'
  String get s3 =>
      ' Porch swept and re-swept; backyard mud catalogued by paw-print and weather, and the fox lingers at the threshold longer than before.';

  /// en: ' Porch stays clean; backyard keeps its mud rights.'
  String get def => ' Porch stays clean; backyard keeps its mud rights.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  Translations$settings$commitPreview$balancedSuffix$descriptive$en.internal(
    this._root,
  );

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ' Porch okay. Backyard does backyard things.'
  String get s0 => ' Porch okay. Backyard does backyard things.';

  /// en: ' Porch as evidence-clean zone; backyard as designated mud zone, hours posted.'
  String get s2 =>
      ' Porch as evidence-clean zone; backyard as designated mud zone, hours posted.';

  /// en: ' Porch as evidence-grade clean room; backyard as cataloged mud archive; threshold as a place the fox stands and thinks too long.'
  String get s3 =>
      ' Porch as evidence-grade clean room; backyard as cataloged mud archive; threshold as a place the fox stands and thinks too long.';

  /// en: ' Clean porch; mud rights preserved in the backyard.'
  String get def => ' Clean porch; mud rights preserved in the backyard.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class Translations$settings$commitPreview$balancedSuffix$narrative$en {
  Translations$settings$commitPreview$balancedSuffix$narrative$en.internal(
    this._root,
  );

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ' Porch was fine. Backyard, who knows.'
  String get s0 => ' Porch was fine. Backyard, who knows.';

  /// en: ' The porch was kept clean afterward; the fox retreated to the backyard, which is where the thinking happens.'
  String get s2 =>
      ' The porch was kept clean afterward; the fox retreated to the backyard, which is where the thinking happens.';

  /// en: ' The porch was scrubbed twice that evening. The fox walked the backyard slow, paused at the same fence post as always, and looked back at the porch like the porch owed something.'
  String get s3 =>
      ' The porch was scrubbed twice that evening. The fox walked the backyard slow, paused at the same fence post as always, and looked back at the porch like the porch owed something.';

  /// en: ' The porch stays clean, though the backyard still wins on dignity.'
  String get def =>
      ' The porch stays clean, though the backyard still wins on dignity.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  Translations$settings$commitPreview$everythingSuffix$verbLed$en.internal(
    this._root,
  );

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ' Amber’s there. Drift drifts. Thorn pricks if it has to. Mostly nothing.'
  String get s0 =>
      ' Amber’s there. Drift drifts. Thorn pricks if it has to. Mostly nothing.';

  /// en: ' Amber holds each scent for review. Drift carries the day’s air toward the gate thorn, which marks each refusal for the evening tally.'
  String get s2 =>
      ' Amber holds each scent for review. Drift carries the day’s air toward the gate thorn, which marks each refusal for the evening tally.';

  /// en: ' Amber holds each scent and gives a different weight depending on the hour. Drift moves through the porch at angles that should not matter but do. The gate thorn pricks once for refusals and twice for the ones the fox almost missed, and the fox knows the difference even when nobody else does.'
  String get s3 =>
      ' Amber holds each scent and gives a different weight depending on the hour. Drift moves through the porch at angles that should not matter but do. The gate thorn pricks once for refusals and twice for the ones the fox almost missed, and the fox knows the difference even when nobody else does.';

  /// en: ' Amber holds the scent. Drift moves it on. The gate thorn catches what shouldn’t pass.'
  String get def =>
      ' Amber holds the scent. Drift moves it on. The gate thorn catches what shouldn’t pass.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  Translations$settings$commitPreview$everythingSuffix$descriptive$en.internal(
    this._root,
  );

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ' Amber on the post. Drift in the air. Thorn at the gate. Fine.'
  String get s0 =>
      ' Amber on the post. Drift in the air. Thorn at the gate. Fine.';

  /// en: ' Amber as designated scent-witness; drift as a logged ambient; thorn-marks as the day’s refusal record, reconciled at dusk.'
  String get s2 =>
      ' Amber as designated scent-witness; drift as a logged ambient; thorn-marks as the day’s refusal record, reconciled at dusk.';

  /// en: ' Amber as a scent-witness whose silence is itself a reading; drift as a patterned ambient that moves wrong on the days something is wrong; thorn as the gate’s tally-keeper, whose marks the fox checks before bed and again before dawn.'
  String get s3 =>
      ' Amber as a scent-witness whose silence is itself a reading; drift as a patterned ambient that moves wrong on the days something is wrong; thorn as the gate’s tally-keeper, whose marks the fox checks before bed and again before dawn.';

  /// en: ' Amber as scent-witness; drift as ambient context; thorn as the gate’s quiet refusal-mark.'
  String get def =>
      ' Amber as scent-witness; drift as ambient context; thorn as the gate’s quiet refusal-mark.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class Translations$settings$commitPreview$everythingSuffix$narrative$en {
  Translations$settings$commitPreview$everythingSuffix$narrative$en.internal(
    this._root,
  );

  final Translations _root; // ignore: unused_field

  // Translations

  /// en: ' Amber was around. Drift came and went. Thorn did its quiet thing. Whatever, it was chill.'
  String get s0 =>
      ' Amber was around. Drift came and went. Thorn did its quiet thing. Whatever, it was chill.';

  /// en: ' Amber kept the scent-record for the day, drift was noted by direction and hour, and the thorn’s marks were tallied and countersigned by the porch.'
  String get s2 =>
      ' Amber kept the scent-record for the day, drift was noted by direction and hour, and the thorn’s marks were tallied and countersigned by the porch.';

  /// en: ' Amber kept the scent-record, but the fox swears it weighs heavier on certain mornings. Drift moved through the porch the way it always does, which is to say wrong on the days that matter. The gate thorn marked each refusal; the fox went out at first light to count them, the way you count stairs you have already counted.'
  String get s3 =>
      ' Amber kept the scent-record, but the fox swears it weighs heavier on certain mornings. Drift moved through the porch the way it always does, which is to say wrong on the days that matter. The gate thorn marked each refusal; the fox went out at first light to count them, the way you count stairs you have already counted.';

  /// en: ' Amber held the scent-record, drift moved the air, and the gate thorn caught what needed catching.'
  String get def =>
      ' Amber held the scent-record, drift moved the air, and the gate thorn caught what needed catching.';
}
