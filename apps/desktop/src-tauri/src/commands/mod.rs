use std::time::Instant;

use serde::Serialize;
use tauri::State;
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::contract::{CommandResult, ResponseMeta};
use crate::models::git::{
    AuthStatus, ForgeAdapterList, GitCapabilities, RepositoryIntegrationMatrix,
};
use crate::models::operations::{
    AiDiffReviewCancelData, AiDiffReviewData, AiDiffReviewJobData, AiDiffReviewJobStartData,
    AiProviderListData, BranchListData, BranchOperationData, CommitData, CommitDetailData,
    CommitHistoryData, ConflictResolutionData, ConflictStateData, FileDiffData,
    IssueProviderListData, LocalIssueListData, LocalIssueOperationData, LocalPullRequestListData,
    LocalPullRequestOperationData, PathOperationData, PullRequestProviderListData, SyncData,
    WorktreeListData, WorktreeOperationData,
};
use crate::models::repository::{OpenRepositoryData, RecentRepositoriesData, RepositoryStatusData};
use crate::models::settings::AppSettingsData;
use crate::runtime::state::AppState;
use crate::services::{
    ai_service, auth_service, forge_service, git_provider, issue_service, pull_request_service,
    repository_service, settings_service,
};

fn response_meta(started_at: Instant, state: &State<'_, AppState>) -> ResponseMeta {
    ResponseMeta {
        request_id: Uuid::new_v4().to_string(),
        duration_ms: started_at.elapsed().as_millis() as u64,
        version: state.contract_version.clone(),
    }
}

fn map_error<T: Serialize>(
    started_at: Instant,
    state: &State<'_, AppState>,
    error: AppError,
) -> CommandResult<T> {
    CommandResult::error(error.to_command_error(), response_meta(started_at, state))
}

#[tauri::command]
pub fn open_repository(repository_path: String, state: State<'_, AppState>) -> CommandResult<OpenRepositoryData> {
    let started_at = Instant::now();

    match repository_service::open_repository(&state, &repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_recent_repositories(state: State<'_, AppState>) -> CommandResult<RecentRepositoriesData> {
    let started_at = Instant::now();

    let mut repositories = state
        .recent_repositories
        .lock()
        .map(|items| items.clone())
        .unwrap_or_default();

    if repositories.is_empty() {
        repositories = repository_service::load_recent_repositories();
        if let Ok(mut current) = state.recent_repositories.lock() {
            *current = repositories.clone();
        }
    }

    CommandResult::ok(
        RecentRepositoriesData { repositories },
        response_meta(started_at, &state),
    )
}

#[tauri::command]
pub fn get_git_capabilities(state: State<'_, AppState>) -> CommandResult<GitCapabilities> {
    let started_at = Instant::now();

    match git_provider::detect_capabilities() {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_auth_status(state: State<'_, AppState>) -> CommandResult<AuthStatus> {
    let started_at = Instant::now();

    match auth_service::get_auth_status(None) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_repository_auth_status(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<AuthStatus> {
    let started_at = Instant::now();

    match auth_service::get_auth_status(Some(&repository_path)) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_forge_adapters(state: State<'_, AppState>) -> CommandResult<ForgeAdapterList> {
    let started_at = Instant::now();

    match forge_service::list_forge_adapters() {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_repository_integration_matrix(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<RepositoryIntegrationMatrix> {
    let started_at = Instant::now();

    match forge_service::get_repository_integration_matrix(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_repository_status(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<RepositoryStatusData> {
    let started_at = Instant::now();

    match git_provider::get_repository_status(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_branches(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<BranchListData> {
    let started_at = Instant::now();

    match git_provider::list_branches(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn create_branch(
    repository_path: String,
    branch_name: String,
    from_ref: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();

    match git_provider::create_branch(&repository_path, &branch_name, from_ref.as_deref()) {
        Ok(_) => CommandResult::ok(
            BranchOperationData {
                repository_path,
                branch_name,
                operation: "create".to_string(),
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn checkout_branch(
    repository_path: String,
    branch_name: String,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();

    match git_provider::checkout_branch(&repository_path, &branch_name) {
        Ok(_) => CommandResult::ok(
            BranchOperationData {
                repository_path,
                branch_name,
                operation: "checkout".to_string(),
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn delete_branch(
    repository_path: String,
    branch_name: String,
    force: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();
    let force = force.unwrap_or(false);

    match git_provider::delete_branch(&repository_path, &branch_name, force) {
        Ok(_) => CommandResult::ok(
            BranchOperationData {
                repository_path,
                branch_name,
                operation: if force {
                    "delete-force".to_string()
                } else {
                    "delete".to_string()
                },
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_worktrees(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<WorktreeListData> {
    let started_at = Instant::now();

    match git_provider::list_worktrees(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn create_worktree(
    repository_path: String,
    worktree_path: String,
    branch_name: String,
    start_point: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<WorktreeOperationData> {
    let started_at = Instant::now();

    match git_provider::create_worktree(
        &repository_path,
        &worktree_path,
        &branch_name,
        start_point.as_deref(),
    ) {
        Ok(_) => CommandResult::ok(
            WorktreeOperationData {
                repository_path,
                operation: "create".to_string(),
                worktree_path,
                branch_name: Some(branch_name),
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn remove_worktree(
    repository_path: String,
    worktree_path: String,
    force: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<WorktreeOperationData> {
    let started_at = Instant::now();
    let force = force.unwrap_or(false);

    match git_provider::remove_worktree(&repository_path, &worktree_path, force) {
        Ok(_) => CommandResult::ok(
            WorktreeOperationData {
                repository_path,
                operation: if force {
                    "remove-force".to_string()
                } else {
                    "remove".to_string()
                },
                worktree_path,
                branch_name: None,
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_commit_history(
    repository_path: String,
    limit: Option<u32>,
    branch: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<CommitHistoryData> {
    let started_at = Instant::now();
    let limit = limit.unwrap_or(50).clamp(1, 500) as usize;

    match git_provider::list_commit_history(&repository_path, limit, branch.as_deref()) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_commit_detail(
    repository_path: String,
    commit_hash: String,
    state: State<'_, AppState>,
) -> CommandResult<CommitDetailData> {
    let started_at = Instant::now();

    match git_provider::get_commit_detail(&repository_path, &commit_hash) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn stage_paths(
    repository_path: String,
    paths: Vec<String>,
    state: State<'_, AppState>,
) -> CommandResult<PathOperationData> {
    let started_at = Instant::now();

    match git_provider::stage_paths(&repository_path, &paths) {
        Ok(_) => CommandResult::ok(
            PathOperationData {
                repository_path,
                operation: "stage".to_string(),
                affected_paths: paths,
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn unstage_paths(
    repository_path: String,
    paths: Vec<String>,
    state: State<'_, AppState>,
) -> CommandResult<PathOperationData> {
    let started_at = Instant::now();

    match git_provider::unstage_paths(&repository_path, &paths) {
        Ok(_) => CommandResult::ok(
            PathOperationData {
                repository_path,
                operation: "unstage".to_string(),
                affected_paths: paths,
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn create_commit(
    repository_path: String,
    message: String,
    amend: bool,
    signoff: bool,
    state: State<'_, AppState>,
) -> CommandResult<CommitData> {
    let started_at = Instant::now();

    let result = git_provider::create_commit(&repository_path, &message, amend, signoff)
        .and_then(|summary| {
            git_provider::get_head_commit_hash(&repository_path).map(|commit_hash| CommitData {
                repository_path: repository_path.clone(),
                commit_hash,
                summary,
            })
        });

    match result {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_file_diff(
    repository_path: String,
    path: String,
    staged: Option<bool>,
    context_lines: Option<u32>,
    state: State<'_, AppState>,
) -> CommandResult<FileDiffData> {
    let started_at = Instant::now();
    let staged = staged.unwrap_or(false);
    let context_lines = context_lines.unwrap_or(3).clamp(0, 30) as usize;

    match git_provider::get_file_diff(&repository_path, &path, staged, context_lines) {
        Ok(diff_text) => CommandResult::ok(
            FileDiffData { path, diff_text },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn fetch_remote(
    repository_path: String,
    remote: Option<String>,
    prune: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<SyncData> {
    let started_at = Instant::now();
    let prune = prune.unwrap_or(false);

    match git_provider::fetch_remote(&repository_path, remote.as_deref(), prune) {
        Ok(output) => CommandResult::ok(
            SyncData {
                operation: "fetch".to_string(),
                remote: remote.unwrap_or_else(|| "default".to_string()),
                branch: None,
                output,
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn pull_remote(
    repository_path: String,
    remote: Option<String>,
    branch: Option<String>,
    rebase: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<SyncData> {
    let started_at = Instant::now();
    let rebase = rebase.unwrap_or(false);

    match git_provider::pull_remote(&repository_path, remote.as_deref(), branch.as_deref(), rebase) {
        Ok(output) => CommandResult::ok(
            SyncData {
                operation: "pull".to_string(),
                remote: remote.unwrap_or_else(|| "default".to_string()),
                branch,
                output,
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn push_remote(
    repository_path: String,
    remote: Option<String>,
    branch: Option<String>,
    force_with_lease: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<SyncData> {
    let started_at = Instant::now();
    let force_with_lease = force_with_lease.unwrap_or(false);

    match git_provider::push_remote(
        &repository_path,
        remote.as_deref(),
        branch.as_deref(),
        force_with_lease,
    ) {
        Ok(output) => CommandResult::ok(
            SyncData {
                operation: "push".to_string(),
                remote: remote.unwrap_or_else(|| "default".to_string()),
                branch,
                output,
            },
            response_meta(started_at, &state),
        ),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_conflict_state(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictStateData> {
    let started_at = Instant::now();

    match git_provider::get_conflict_state(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn continue_conflict_resolution(
    repository_path: String,
    operation: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();

    match git_provider::continue_conflict_resolution(&repository_path, operation.as_deref()) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn abort_conflict_resolution(
    repository_path: String,
    operation: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();

    match git_provider::abort_conflict_resolution(&repository_path, operation.as_deref()) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_issue_providers(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<IssueProviderListData> {
    let started_at = Instant::now();

    match issue_service::list_issue_providers(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_local_issues(
    repository_path: String,
    provider_id: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueListData> {
    let started_at = Instant::now();

    match issue_service::list_issues(&repository_path, provider_id.as_deref()) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_pull_request_providers(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<PullRequestProviderListData> {
    let started_at = Instant::now();

    match pull_request_service::list_pull_request_providers(&repository_path) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_pull_requests(
    repository_path: String,
    provider_id: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestListData> {
    let started_at = Instant::now();

    match pull_request_service::list_pull_requests(&repository_path, provider_id.as_deref()) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn create_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    title: String,
    description: String,
    source_branch: String,
    target_branch: String,
    draft: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();
    let draft = draft.unwrap_or(false);

    match pull_request_service::create_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &title,
        &description,
        &source_branch,
        &target_branch,
        draft,
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn close_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();

    match pull_request_service::close_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn reopen_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();

    match pull_request_service::reopen_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn mark_pull_request_ready(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();

    match pull_request_service::mark_pull_request_ready(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn merge_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    delete_source_branch: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();
    let delete_source_branch = delete_source_branch.unwrap_or(false);

    match pull_request_service::merge_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
        delete_source_branch,
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn create_local_issue(
    repository_path: String,
    provider_id: Option<String>,
    title: String,
    body: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueOperationData> {
    let started_at = Instant::now();

    match issue_service::create_issue(&repository_path, provider_id.as_deref(), &title, &body) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn close_local_issue(
    repository_path: String,
    provider_id: Option<String>,
    issue_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueOperationData> {
    let started_at = Instant::now();

    match issue_service::close_issue(&repository_path, provider_id.as_deref(), &issue_id) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn reopen_local_issue(
    repository_path: String,
    provider_id: Option<String>,
    issue_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueOperationData> {
    let started_at = Instant::now();

    match issue_service::reopen_issue(&repository_path, provider_id.as_deref(), &issue_id) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn list_ai_providers(state: State<'_, AppState>) -> CommandResult<AiProviderListData> {
    let started_at = Instant::now();

    match ai_service::list_providers() {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn run_ai_diff_review(
    provider_id: String,
    repository_path: String,
    prompt: String,
    diff_scope_path: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewData> {
    let started_at = Instant::now();

    match ai_service::run_diff_review(
        &provider_id,
        &repository_path,
        &prompt,
        diff_scope_path.as_deref(),
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn start_ai_diff_review_job(
    provider_id: String,
    repository_path: String,
    prompt: String,
    diff_scope_path: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewJobStartData> {
    let started_at = Instant::now();

    match ai_service::start_diff_review_job(
        &state,
        &provider_id,
        &repository_path,
        &prompt,
        diff_scope_path.as_deref(),
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_ai_diff_review_job(
    job_id: String,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewJobData> {
    let started_at = Instant::now();

    match ai_service::get_diff_review_job(&state, &job_id) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn cancel_ai_diff_review_job(
    job_id: String,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewCancelData> {
    let started_at = Instant::now();

    match ai_service::cancel_diff_review_job(&state, &job_id) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn get_app_settings(state: State<'_, AppState>) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();

    match settings_service::get_settings() {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn update_ai_guardrail(
    guardrail_value: f32,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();

    match settings_service::update_guardrail(guardrail_value) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn update_telemetry_retention(
    retention_days: u32,
    retention_mb: u32,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();

    match settings_service::update_telemetry_retention(retention_days, retention_mb) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn update_layout_preferences(
    sidebar_width_px: u32,
    sidebar_position: String,
    utility_drawer_default_expanded: bool,
    utility_drawer_height_px: u32,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();

    match settings_service::update_layout_preferences(
        sidebar_width_px,
        &sidebar_position,
        utility_drawer_default_expanded,
        utility_drawer_height_px,
    ) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}

#[tauri::command]
pub fn update_ui_preferences(
    theme_id: String,
    keybinding_profile: String,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();

    match settings_service::update_ui_preferences(&theme_id, &keybinding_profile) {
        Ok(data) => CommandResult::ok(data, response_meta(started_at, &state)),
        Err(error) => map_error(started_at, &state, error),
    }
}
