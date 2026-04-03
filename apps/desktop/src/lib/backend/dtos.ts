export interface GitCapabilities {
  gitInstalled: boolean;
  gitVersion?: string;
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
  ahead: number;
  behind: number;
  files: RepositoryStatusFile[];
}

export interface OpenRepositoryData {
  repositoryPath: string;
  isValidGitRepository: boolean;
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

export interface AiProviderStatus {
  id: string;
  available: boolean;
  binary: string;
}

export interface AiProviderListData {
  providers: AiProviderStatus[];
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

export interface AppSettingsData {
  guardrailValue: number;
  guardrailProfile: "Loose" | "Balanced" | "Strict" | "Paranoid";
  aiReadOnlyDefault: boolean;
  telemetryRetentionDays: number;
  telemetryRetentionMb: number;
  themeId: string;
  keybindingProfile: "classic" | "compact" | string;
  sidebarWidthPx: number;
  sidebarPosition: "left" | "right" | string;
  utilityDrawerDefaultExpanded: boolean;
  utilityDrawerHeightPx: number;
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
