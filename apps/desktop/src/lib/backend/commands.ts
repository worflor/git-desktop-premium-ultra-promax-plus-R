import type { CommandResult } from "@/lib/contracts/command";
import type {
  AiDiffReviewCancelData,
  AiDiffReviewData,
  AiDiffReviewJobData,
  AiDiffReviewJobStartData,
  AiModelOptionListData,
  AiProviderListData,
  AppSettingsData,
  AppUpdateCheckData,
  AppUpdateInstallData,
  AuthStatus,
  BranchListData,
  BranchOperationData,
  CommitData,
  CommitDetailData,
  CommitHistoryData,
  ConflictResolutionData,
  ConflictStateData,
  FileDiffChunkData,
  FileDiffData,
  FileDiffManifestData,
  ForgeAdapter,
  GitCapabilities,
  IssueProviderListData,
  LocalIssueListData,
  LocalIssueOperationData,
  LocalPullRequestListData,
  LocalPullRequestOperationData,
  OpenRepositoryData,
  PathOperationData,
  PullRequestProviderListData,
  RecentRepositoriesData,
  RepositoryIntegrationMatrix,
  RepositoryStatus,
  StartupReadinessSnapshotData,
  SyncData,
  WorktreeListData,
  WorktreeOperationData
} from "@/lib/backend/dtos";
import { invokeCommand } from "@/lib/backend/client";

export function openRepository(repositoryPath: string): Promise<CommandResult<OpenRepositoryData>> {
  return invokeCommand("open_repository", { repositoryPath });
}

export function listRecentRepositories(): Promise<CommandResult<RecentRepositoriesData>> {
  return invokeCommand("list_recent_repositories", {});
}

export function getGitCapabilities(): Promise<CommandResult<GitCapabilities>> {
  return invokeCommand("get_git_capabilities", {});
}

export function getAuthStatus(): Promise<CommandResult<AuthStatus>> {
  return invokeCommand("get_auth_status", {});
}

export function getRepositoryAuthStatus(repositoryPath: string): Promise<CommandResult<AuthStatus>> {
  return invokeCommand("get_repository_auth_status", { repositoryPath });
}

export function listForgeAdapters(): Promise<CommandResult<{ adapters: ForgeAdapter[] }>> {
  return invokeCommand("list_forge_adapters", {});
}

export function getRepositoryIntegrationMatrix(
  repositoryPath: string
): Promise<CommandResult<RepositoryIntegrationMatrix>> {
  return invokeCommand("get_repository_integration_matrix", { repositoryPath });
}

export function getRepositoryStatus(repositoryPath: string): Promise<CommandResult<RepositoryStatus>> {
  return invokeCommand("get_repository_status", { repositoryPath });
}

export function listBranches(repositoryPath: string): Promise<CommandResult<BranchListData>> {
  return invokeCommand("list_branches", { repositoryPath });
}

export function createBranch(
  repositoryPath: string,
  branchName: string,
  fromRef?: string
): Promise<CommandResult<BranchOperationData>> {
  return invokeCommand("create_branch", { repositoryPath, branchName, fromRef });
}

export function checkoutBranch(
  repositoryPath: string,
  branchName: string
): Promise<CommandResult<BranchOperationData>> {
  return invokeCommand("checkout_branch", { repositoryPath, branchName });
}

export function deleteBranch(
  repositoryPath: string,
  branchName: string,
  force = false
): Promise<CommandResult<BranchOperationData>> {
  return invokeCommand("delete_branch", { repositoryPath, branchName, force });
}

export function listWorktrees(repositoryPath: string): Promise<CommandResult<WorktreeListData>> {
  return invokeCommand("list_worktrees", { repositoryPath });
}

export function createWorktree(
  repositoryPath: string,
  worktreePath: string,
  branchName: string,
  startPoint?: string
): Promise<CommandResult<WorktreeOperationData>> {
  return invokeCommand("create_worktree", { repositoryPath, worktreePath, branchName, startPoint });
}

export function removeWorktree(
  repositoryPath: string,
  worktreePath: string,
  force = false
): Promise<CommandResult<WorktreeOperationData>> {
  return invokeCommand("remove_worktree", { repositoryPath, worktreePath, force });
}

export function listCommitHistory(
  repositoryPath: string,
  limit = 50,
  branch?: string
): Promise<CommandResult<CommitHistoryData>> {
  return invokeCommand("list_commit_history", { repositoryPath, limit, branch });
}

export function getCommitDetail(
  repositoryPath: string,
  commitHash: string
): Promise<CommandResult<CommitDetailData>> {
  return invokeCommand("get_commit_detail", { repositoryPath, commitHash });
}

export function stagePaths(
  repositoryPath: string,
  paths: string[]
): Promise<CommandResult<PathOperationData>> {
  return invokeCommand("stage_paths", { repositoryPath, paths });
}

export function unstagePaths(
  repositoryPath: string,
  paths: string[]
): Promise<CommandResult<PathOperationData>> {
  return invokeCommand("unstage_paths", { repositoryPath, paths });
}

export function createCommit(
  repositoryPath: string,
  message: string,
  amend = false,
  signoff = false
): Promise<CommandResult<CommitData>> {
  return invokeCommand("create_commit", {
    repositoryPath,
    message,
    amend,
    signoff
  });
}

export function getFileDiff(
  repositoryPath: string,
  path: string,
  staged = false,
  contextLines = 3
): Promise<CommandResult<FileDiffData>> {
  return invokeCommand("get_file_diff", {
    repositoryPath,
    path,
    staged,
    contextLines
  });
}

export function prepareFileDiffChunks(
  repositoryPath: string,
  path: string,
  options?: {
    staged?: boolean;
    contextLines?: number;
    chunkSizeBytes?: number;
    layoutWidthPx?: number;
    fontProfile?: string;
    lineHeightPx?: number;
  }
): Promise<CommandResult<FileDiffManifestData>> {
  return invokeCommand("prepare_file_diff_chunks", {
    repositoryPath,
    path,
    staged: options?.staged,
    contextLines: options?.contextLines,
    chunkSizeBytes: options?.chunkSizeBytes,
    layoutWidthPx: options?.layoutWidthPx,
    fontProfile: options?.fontProfile,
    lineHeightPx: options?.lineHeightPx
  });
}

export function getFileDiffChunk(
  diffId: string,
  chunkIndex: number
): Promise<CommandResult<FileDiffChunkData>> {
  return invokeCommand("get_file_diff_chunk", { diffId, chunkIndex });
}

export function fetchRemote(
  repositoryPath: string,
  remote?: string,
  prune = false
): Promise<CommandResult<SyncData>> {
  return invokeCommand("fetch_remote", { repositoryPath, remote, prune });
}

export function pullRemote(
  repositoryPath: string,
  remote?: string,
  branch?: string,
  rebase = false
): Promise<CommandResult<SyncData>> {
  return invokeCommand("pull_remote", {
    repositoryPath,
    remote,
    branch,
    rebase
  });
}

export function pushRemote(
  repositoryPath: string,
  remote?: string,
  branch?: string,
  forceWithLease = false
): Promise<CommandResult<SyncData>> {
  return invokeCommand("push_remote", {
    repositoryPath,
    remote,
    branch,
    forceWithLease
  });
}

export function getConflictState(repositoryPath: string): Promise<CommandResult<ConflictStateData>> {
  return invokeCommand("get_conflict_state", { repositoryPath });
}

export function continueConflictResolution(
  repositoryPath: string,
  operation?: string
): Promise<CommandResult<ConflictResolutionData>> {
  return invokeCommand("continue_conflict_resolution", { repositoryPath, operation });
}

export function abortConflictResolution(
  repositoryPath: string,
  operation?: string
): Promise<CommandResult<ConflictResolutionData>> {
  return invokeCommand("abort_conflict_resolution", { repositoryPath, operation });
}

export function listIssueProviders(repositoryPath: string): Promise<CommandResult<IssueProviderListData>> {
  return invokeCommand("list_issue_providers", { repositoryPath });
}

export function listPullRequestProviders(
  repositoryPath: string
): Promise<CommandResult<PullRequestProviderListData>> {
  return invokeCommand("list_pull_request_providers", { repositoryPath });
}

export function listLocalIssues(
  repositoryPath: string,
  providerId?: string
): Promise<CommandResult<LocalIssueListData>> {
  return invokeCommand("list_local_issues", { repositoryPath, providerId });
}

export function createLocalIssue(
  repositoryPath: string,
  providerId: string | undefined,
  title: string,
  body: string
): Promise<CommandResult<LocalIssueOperationData>> {
  return invokeCommand("create_local_issue", { repositoryPath, providerId, title, body });
}

export function closeLocalIssue(
  repositoryPath: string,
  providerId: string | undefined,
  issueId: string
): Promise<CommandResult<LocalIssueOperationData>> {
  return invokeCommand("close_local_issue", { repositoryPath, providerId, issueId });
}

export function reopenLocalIssue(
  repositoryPath: string,
  providerId: string | undefined,
  issueId: string
): Promise<CommandResult<LocalIssueOperationData>> {
  return invokeCommand("reopen_local_issue", { repositoryPath, providerId, issueId });
}

export function listPullRequests(
  repositoryPath: string,
  providerId?: string
): Promise<CommandResult<LocalPullRequestListData>> {
  return invokeCommand("list_pull_requests", { repositoryPath, providerId });
}

export function createPullRequest(
  repositoryPath: string,
  providerId: string | undefined,
  title: string,
  description: string,
  sourceBranch: string,
  targetBranch: string,
  draft = false
): Promise<CommandResult<LocalPullRequestOperationData>> {
  return invokeCommand("create_pull_request", {
    repositoryPath,
    providerId,
    title,
    description,
    sourceBranch,
    targetBranch,
    draft
  });
}

export function closePullRequest(
  repositoryPath: string,
  providerId: string | undefined,
  pullRequestId: string
): Promise<CommandResult<LocalPullRequestOperationData>> {
  return invokeCommand("close_pull_request", { repositoryPath, providerId, pullRequestId });
}

export function reopenPullRequest(
  repositoryPath: string,
  providerId: string | undefined,
  pullRequestId: string
): Promise<CommandResult<LocalPullRequestOperationData>> {
  return invokeCommand("reopen_pull_request", { repositoryPath, providerId, pullRequestId });
}

export function markPullRequestReady(
  repositoryPath: string,
  providerId: string | undefined,
  pullRequestId: string
): Promise<CommandResult<LocalPullRequestOperationData>> {
  return invokeCommand("mark_pull_request_ready", { repositoryPath, providerId, pullRequestId });
}

export function mergePullRequest(
  repositoryPath: string,
  providerId: string | undefined,
  pullRequestId: string,
  deleteSourceBranch = false
): Promise<CommandResult<LocalPullRequestOperationData>> {
  return invokeCommand("merge_pull_request", {
    repositoryPath,
    providerId,
    pullRequestId,
    deleteSourceBranch
  });
}

export function listAiProviders(): Promise<CommandResult<AiProviderListData>> {
  return invokeCommand("list_ai_providers", {});
}

export function listAiModelOptions(): Promise<CommandResult<AiModelOptionListData>> {
  return invokeCommand("list_ai_model_options", {});
}

export function runAiDiffReview(
  providerId: string,
  repositoryPath: string,
  prompt: string,
  diffScopePath?: string
): Promise<CommandResult<AiDiffReviewData>> {
  return invokeCommand("run_ai_diff_review", {
    providerId,
    repositoryPath,
    prompt,
    diffScopePath
  });
}

export function startAiDiffReviewJob(
  providerId: string,
  repositoryPath: string,
  prompt: string,
  diffScopePath?: string
): Promise<CommandResult<AiDiffReviewJobStartData>> {
  return invokeCommand("start_ai_diff_review_job", {
    providerId,
    repositoryPath,
    prompt,
    diffScopePath
  });
}

export function getAiDiffReviewJob(jobId: string): Promise<CommandResult<AiDiffReviewJobData>> {
  return invokeCommand("get_ai_diff_review_job", { jobId });
}

export function cancelAiDiffReviewJob(jobId: string): Promise<CommandResult<AiDiffReviewCancelData>> {
  return invokeCommand("cancel_ai_diff_review_job", { jobId });
}

export function getStartupReadinessSnapshot(
  refresh = false
): Promise<CommandResult<StartupReadinessSnapshotData>> {
  return invokeCommand("get_startup_readiness_snapshot", { refresh });
}

export function getAppSettings(): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("get_app_settings", {});
}

export function updateAiGuardrail(guardrailValue: number): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("update_ai_guardrail", { guardrailValue });
}

export function updateTelemetryRetention(
  retentionDays: number,
  retentionMb: number
): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("update_telemetry_retention", { retentionDays, retentionMb });
}

export function updateUpdateChannel(
  updateChannel: "stable" | "beta" | string
): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("update_update_channel", { updateChannel });
}

export function checkForAppUpdate(): Promise<CommandResult<AppUpdateCheckData>> {
  return invokeCommand("check_for_app_update", {});
}

export function installAppUpdate(): Promise<CommandResult<AppUpdateInstallData>> {
  return invokeCommand("install_app_update", {});
}

export function updateCrashReporting(
  crashReportingEnabled: boolean
): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("update_crash_reporting", { crashReportingEnabled });
}

export function updateLayoutPreferences(
  sidebarWidthPx: number,
  sidebarPosition: "left" | "right",
  utilityDrawerDefaultExpanded: boolean,
  utilityDrawerHeightPx: number
): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("update_layout_preferences", {
    sidebarWidthPx,
    sidebarPosition,
    utilityDrawerDefaultExpanded,
    utilityDrawerHeightPx
  });
}

export function updateUiPreferences(
  themeId: string,
  keybindingProfile: "classic" | "compact"
): Promise<CommandResult<AppSettingsData>> {
  return invokeCommand("update_ui_preferences", {
    themeId,
    keybindingProfile
  });
}
