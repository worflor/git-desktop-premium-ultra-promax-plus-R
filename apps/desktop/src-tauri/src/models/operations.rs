use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PathOperationData {
    pub repository_path: String,
    pub operation: String,
    pub affected_paths: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitData {
    pub repository_path: String,
    pub commit_hash: String,
    pub summary: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncData {
    pub operation: String,
    pub remote: String,
    pub branch: Option<String>,
    pub output: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConflictStateData {
    pub repository_path: String,
    pub in_conflict: bool,
    pub operation: Option<String>,
    pub conflicted_files: Vec<String>,
    pub guidance: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConflictResolutionData {
    pub repository_path: String,
    pub operation: String,
    pub action: String,
    pub output: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileDiffData {
    pub path: String,
    pub diff_text: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BranchInfoData {
    pub name: String,
    pub current: bool,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BranchListData {
    pub current_branch: Option<String>,
    pub branches: Vec<BranchInfoData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BranchOperationData {
    pub repository_path: String,
    pub branch_name: String,
    pub operation: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitHistoryEntryData {
    pub commit_hash: String,
    pub short_hash: String,
    pub subject: String,
    pub author_name: String,
    pub author_email: String,
    pub authored_at: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitHistoryData {
    pub entries: Vec<CommitHistoryEntryData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitFileStatData {
    pub path: String,
    pub additions: u32,
    pub deletions: u32,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitDetailData {
    pub commit_hash: String,
    pub short_hash: String,
    pub subject: String,
    pub body: String,
    pub author_name: String,
    pub author_email: String,
    pub authored_at: String,
    pub files_changed: u32,
    pub additions: u32,
    pub deletions: u32,
    pub files: Vec<CommitFileStatData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiProviderStatus {
    pub id: String,
    pub available: bool,
    pub binary: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiProviderListData {
    pub providers: Vec<AiProviderStatus>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiDiffReviewData {
    pub provider_id: String,
    pub response: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiDiffReviewJobStartData {
    pub job_id: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiDiffReviewJobData {
    pub job_id: String,
    pub status: String,
    pub output: String,
    pub error: Option<String>,
    pub done: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiDiffReviewCancelData {
    pub job_id: String,
    pub canceled: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueProviderData {
    pub id: String,
    pub display_name: String,
    pub available: bool,
    pub mode: String,
    pub guidance: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IssueProviderListData {
    pub repository_path: String,
    pub default_provider_id: String,
    pub providers: Vec<IssueProviderData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalIssueData {
    pub id: String,
    pub title: String,
    pub body: String,
    pub state: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalIssueListData {
    pub repository_path: String,
    pub provider_id: String,
    pub issues: Vec<LocalIssueData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalIssueOperationData {
    pub repository_path: String,
    pub provider_id: String,
    pub operation: String,
    pub issue: LocalIssueData,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalPullRequestData {
    pub id: String,
    pub title: String,
    pub description: String,
    pub source_branch: String,
    pub target_branch: String,
    pub state: String,
    pub draft: bool,
    pub created_at: String,
    pub updated_at: String,
    pub merged_at: Option<String>,
    pub closed_at: Option<String>,
    pub merge_commit_hash: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalPullRequestListData {
    pub repository_path: String,
    pub provider_id: String,
    pub pull_requests: Vec<LocalPullRequestData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalPullRequestOperationData {
    pub repository_path: String,
    pub provider_id: String,
    pub operation: String,
    pub pull_request: LocalPullRequestData,
}

pub type PullRequestProviderData = IssueProviderData;
pub type PullRequestProviderListData = IssueProviderListData;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeData {
    pub path: String,
    pub branch: Option<String>,
    pub head: Option<String>,
    pub bare: bool,
    pub detached: bool,
    pub locked: bool,
    pub prunable: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeListData {
    pub repository_path: String,
    pub worktrees: Vec<WorktreeData>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeOperationData {
    pub repository_path: String,
    pub operation: String,
    pub worktree_path: String,
    pub branch_name: Option<String>,
}
