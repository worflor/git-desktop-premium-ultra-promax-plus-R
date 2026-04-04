export interface GitCapabilities {
  gitInstalled: boolean;
  gitVersion?: string;
  gitExecutablePath?: string;
  supportsPartialClone: boolean;
  supportsSparseCheckout: boolean;
}

export interface AuthStatus {
  sshAgentAvailable: boolean;
  credentialHelperConfigured: boolean;
  diagnostics: string[];
  remoteDiagnostics: RemoteAuthDiagnostic[];
}

export interface RemoteAuthDiagnostic {
  remote: string;
  url: string;
  protocol: string;
  guidance: string;
}

export interface ForgeAdapter {
  id: string;
  available: boolean;
  version?: string;
  authState?: string;
  authMessage?: string;
}

export interface RemoteIntegrationData {
  remote: string;
  url: string;
  hostKind: string;
  adapterId?: string;
  adapterAvailable: boolean;
  offlineSupported: boolean;
  capabilitySummary: string[];
}

export interface RepositoryIntegrationMatrix {
  repositoryPath: string;
  offlineReady: boolean;
  localFeatures: string[];
  remotes: RemoteIntegrationData[];
}

export interface RepositoryStatusFile {
  path: string;
  staged: string;
  unstaged: string;
}

export interface RepositoryStatus {
  branch: string;
  upstream?: string;
  ahead: number;
  behind: number;
  files: RepositoryStatusFile[];
}

export interface OpenRepositoryData {
  repositoryPath: string;
  isValidGitRepository: boolean;
}

export interface PickRepositoryDirectoryData {
  repositoryPath: string | null;
}

export interface RecentRepositoriesData {
  repositories: string[];
}

export interface PathOperationData {
  repositoryPath: string;
  operation: string;
  affectedPaths: string[];
}

export interface CommitData {
  repositoryPath: string;
  commitHash: string;
  summary: string;
}

export interface SyncData {
  operation: string;
  remote: string;
  branch?: string;
  output: string;
}

export interface ConflictStateData {
  repositoryPath: string;
  inConflict: boolean;
  operation?: "merge" | "rebase" | "cherry-pick" | "revert" | string;
  conflictedFiles: string[];
  guidance: string[];
}

export interface ConflictResolutionData {
  repositoryPath: string;
  operation: string;
  action: "continue" | "abort" | string;
  output: string;
}

export interface FileDiffData {
  path: string;
  diffText: string;
}

export interface DiffHunkData {
  hunkIndex: number;
  header: string;
  oldStart: number;
  oldLines: number;
  newStart: number;
  newLines: number;
  addedLines: number;
  deletedLines: number;
}

export interface FileDiffManifestData {
  diffId: string;
  path: string;
  staged: boolean;
  contextLines: number;
  chunkSizeBytes: number;
  chunkCount: number;
  totalBytes: number;
  totalLines: number;
  changedLines: number;
  additions: number;
  deletions: number;
  hunkCount: number;
  rendererMode: "dom" | "canvas" | "fallback" | string;
  modeThresholdMaxChangedLines: number;
  modeThresholdMaxPayloadBytes: number;
  pretextVersion: string;
  pretextPrepareMs: number;
  pretextLayoutMs: number;
  fallbackActivated: boolean;
  fallbackReason?: string;
  visualRowCount: number;
  layoutCacheKey: string;
  initialChunkText: string;
  hunks: DiffHunkData[];
}

export interface FileDiffChunkData {
  diffId: string;
  chunkIndex: number;
  chunkCount: number;
  hasMore: boolean;
  chunkText: string;
}

export interface BranchInfo {
  name: string;
  current: boolean;
  upstream?: string;
  ahead: number;
  behind: number;
}

export interface BranchListData {
  currentBranch?: string;
  branches: BranchInfo[];
}

export interface BranchOperationData {
  repositoryPath: string;
  branchName: string;
  operation: string;
}

export interface WorktreeData {
  path: string;
  branch?: string;
  head?: string;
  bare: boolean;
  detached: boolean;
  locked: boolean;
  prunable: boolean;
}

export interface WorktreeListData {
  repositoryPath: string;
  worktrees: WorktreeData[];
}

export interface WorktreeOperationData {
  repositoryPath: string;
  operation: string;
  worktreePath: string;
  branchName?: string;
}

export interface CommitHistoryEntry {
  commitHash: string;
  shortHash: string;
  subject: string;
  authorName: string;
  authorEmail: string;
  authoredAt: string;
}

export interface CommitHistoryData {
  entries: CommitHistoryEntry[];
}

export interface CommitFileStatData {
  path: string;
  additions: number;
  deletions: number;
}

export interface CommitDetailData {
  commitHash: string;
  shortHash: string;
  subject: string;
  body: string;
  authorName: string;
  authorEmail: string;
  authoredAt: string;
  filesChanged: number;
  additions: number;
  deletions: number;
  files: CommitFileStatData[];
}

export interface CommitDetailBatchData {
  entries: CommitDetailData[];
}

export interface AiProviderStatus {
  id: string;
  available: boolean;
  binary: string;
  planName?: string;
}

export interface AiProviderListData {
  providers: AiProviderStatus[];
}

export interface AiModelOptionData {
  value: string;
  modelId: string;
  providerId: string;
  providerSymbol: string;
  planName?: string;
  label: string;
  description: string;
}

export interface AiModelCategoryData {
  id: string;
  label: string;
  description?: string;
  models: AiModelOptionData[];
}

export interface AiModelOptionListData {
  categories: AiModelCategoryData[];
}

export interface AiDiffReviewData {
  providerId: string;
  response: string;
}

export interface AiDiffReviewJobStartData {
  jobId: string;
}

export interface AiDiffReviewJobData {
  jobId: string;
  status: "queued" | "running" | "completed" | "failed" | "canceled";
  output: string;
  error?: string;
  done: boolean;
}

export interface AiDiffReviewCancelData {
  jobId: string;
  canceled: boolean;
}

export interface AiAuditMaintenanceData {
  operation: string;
  affectedEntries: number;
  sampleCount: number;
}

export interface AppSettingsData {
  guardrailValue: number;
  guardrailProfile: "Loose" | "Balanced" | "Strict" | "Paranoid";
  aiReadOnlyDefault: boolean;
  telemetryRetentionDays: number;
  telemetryRetentionMb: number;
  updateChannel: "stable" | "beta" | string;
  crashReportingEnabled: boolean;
  themeId: string;
  keybindingProfile: "classic" | "compact" | string;
  sidebarWidthPx: number;
  sidebarPosition: "left" | "right" | string;
  utilityDrawerDefaultExpanded: boolean;
  utilityDrawerHeightPx: number;
}

export interface AppUpdateCheckData {
  channel: "stable" | "beta" | string;
  endpoint?: string;
  checkedAt: string;
  updateAvailable: boolean;
  currentVersion: string;
  latestVersion?: string;
  notes?: string;
  publishedAt?: string;
  target?: string;
  downloadUrl?: string;
}

export interface AppUpdateInstallData {
  channel: "stable" | "beta" | string;
  endpoint?: string;
  checkedAt: string;
  attempted: boolean;
  installed: boolean;
  currentVersion: string;
  targetVersion?: string;
  message: string;
}

export interface StartupReadinessCheckData {
  id: string;
  ok: boolean;
  durationMs: number;
  errorCode?: string;
  message?: string;
}

export interface StartupReadinessSnapshotData {
  requestId: string;
  startedAt: string;
  completedAt: string;
  durationMs: number;
  ok: boolean;
  degradedChecks: number;
  checks: StartupReadinessCheckData[];
}

export interface IssueProviderData {
  id: string;
  displayName: string;
  available: boolean;
  mode: string;
  guidance?: string;
}

export interface IssueProviderListData {
  repositoryPath: string;
  defaultProviderId: string;
  providers: IssueProviderData[];
}

export interface PullRequestProviderData {
  id: string;
  displayName: string;
  available: boolean;
  mode: string;
  guidance?: string;
}

export interface PullRequestProviderListData {
  repositoryPath: string;
  defaultProviderId: string;
  providers: PullRequestProviderData[];
}

export interface LocalIssueData {
  id: string;
  title: string;
  body: string;
  state: string;
  createdAt: string;
  updatedAt: string;
  closedAt?: string;
}

export interface LocalIssueListData {
  repositoryPath: string;
  providerId: string;
  issues: LocalIssueData[];
}

export interface LocalIssueOperationData {
  repositoryPath: string;
  providerId: string;
  issue: LocalIssueData;
  operation: string;
}

export interface LocalPullRequestData {
  id: string;
  title: string;
  description: string;
  sourceBranch: string;
  targetBranch: string;
  state: string;
  draft: boolean;
  createdAt: string;
  updatedAt: string;
  mergedAt?: string;
  closedAt?: string;
  mergeCommitHash?: string;
}

export interface LocalPullRequestListData {
  repositoryPath: string;
  providerId: string;
  pullRequests: LocalPullRequestData[];
}

export interface LocalPullRequestOperationData {
  repositoryPath: string;
  providerId: string;
  operation: string;
  pullRequest: LocalPullRequestData;
}
