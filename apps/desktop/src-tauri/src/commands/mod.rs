use std::time::Instant;

use serde::{Deserialize, Serialize};
use tauri::State;
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::contract::{CommandResult, ResponseMeta};
use crate::models::git::{
    AuthStatus, ForgeAdapterList, GitCapabilities, RepositoryIntegrationMatrix,
};
use crate::models::operations::{
    AiAuditListData, AiAuditMaintenanceData, AiDiffReviewCancelData, AiDiffReviewData, AiDiffReviewJobData,
    AiDiffReviewJobStartData, AiModelOptionListData, AiProviderListData, AppUpdateCheckData,
    AppUpdateInstallData,
    BranchListData, BranchOperationData, BranchTrackingOperationData,
    CommandTelemetryMaintenanceData, CommandTelemetrySnapshotData, CommitData, CommitDetailData,
    CommitHistoryData, ConflictResolutionData, ConflictStateData, FileDiffChunkData, FileDiffData,
    FileDiffManifestData, IssueProviderListData, LocalIssueListData, LocalIssueOperationData,
    LocalPullRequestListData, LocalPullRequestOperationData, PathOperationData,
    PullRequestProviderListData, StartupReadinessSnapshotData, StashListData,
    StashOperationData, SyncData, WorktreeListData, WorktreeOperationData,
};
use crate::models::repository::{
    OpenRepositoryData, PickRepositoryDirectoryData, RecentRepositoriesData, RepositoryStatusData,
};
use crate::models::settings::AppSettingsData;
use crate::runtime::state::AppState;
use crate::services::{
    ai_service, auth_service, bootstrap_service, diff_service, forge_service, git_provider,
    issue_service, logging_service, pull_request_service, repository_service, settings_service,
    telemetry_service, update_service,
};

fn response_meta(started_at: Instant, state: &State<'_, AppState>) -> ResponseMeta {
    let request_id =
        logging_service::current_request_context().unwrap_or_else(|| Uuid::new_v4().to_string());
    ResponseMeta {
        request_id,
        duration_ms: started_at.elapsed().as_millis() as u64,
        version: state.contract_version.clone(),
    }
}

fn command_ok<T: Serialize>(
    command_name: &str,
    started_at: Instant,
    state: &State<'_, AppState>,
    data: T,
) -> CommandResult<T> {
    let meta = response_meta(started_at, state);
    let _ = logging_service::record_operation_span(
        "command",
        command_name,
        Some(meta.request_id.as_str()),
        started_at,
        true,
        None,
        None,
    );
    let _ = telemetry_service::record_command_sample(
        "command",
        command_name,
        true,
        meta.duration_ms,
        None,
    );
    logging_service::clear_request_context();
    CommandResult::ok(data, meta)
}

fn map_error_with_command<T: Serialize>(
    command_name: &str,
    started_at: Instant,
    state: &State<'_, AppState>,
    error: AppError,
) -> CommandResult<T> {
    let command_error = error.to_command_error();
    let error_code = command_error.code.clone();
    let error_message = command_error.message.clone();
    let meta = response_meta(started_at, state);
    let _ = logging_service::record_operation_span(
        "command",
        command_name,
        Some(meta.request_id.as_str()),
        started_at,
        false,
        Some(error_code.as_str()),
        Some(error_message.as_str()),
    );
    let _ = telemetry_service::record_command_sample(
        "command",
        command_name,
        false,
        meta.duration_ms,
        Some(error_code.as_str()),
    );
    logging_service::clear_request_context();
    CommandResult::error(command_error, meta)
}

#[tauri::command(async)]
pub fn open_repository(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<OpenRepositoryData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match repository_service::open_repository(&state, &repository_path) {
        Ok(data) => command_ok("open_repository", started_at, &state, data),
        Err(error) => map_error_with_command("open_repository", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn pick_repository_directory(
    state: State<'_, AppState>,
) -> CommandResult<PickRepositoryDirectoryData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    let repository_path = repository_service::pick_repository_directory();
    command_ok(
        "pick_repository_directory",
        started_at,
        &state,
        PickRepositoryDirectoryData { repository_path },
    )
}

#[tauri::command(async)]
pub fn list_recent_repositories(
    state: State<'_, AppState>,
) -> CommandResult<RecentRepositoriesData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

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

    command_ok(
        "list_recent_repositories",
        started_at,
        &state,
        RecentRepositoriesData { repositories },
    )
}

#[tauri::command(async)]
pub fn get_git_capabilities(state: State<'_, AppState>) -> CommandResult<GitCapabilities> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::detect_capabilities() {
        Ok(data) => command_ok("get_git_capabilities", started_at, &state, data),
        Err(error) => map_error_with_command("get_git_capabilities", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_auth_status(state: State<'_, AppState>) -> CommandResult<AuthStatus> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match auth_service::get_auth_status(None) {
        Ok(data) => command_ok("get_auth_status", started_at, &state, data),
        Err(error) => map_error_with_command("get_auth_status", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_repository_auth_status(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<AuthStatus> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match auth_service::get_auth_status(Some(&repository_path)) {
        Ok(data) => command_ok("get_repository_auth_status", started_at, &state, data),
        Err(error) => {
            map_error_with_command("get_repository_auth_status", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn list_forge_adapters(state: State<'_, AppState>) -> CommandResult<ForgeAdapterList> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match forge_service::list_forge_adapters() {
        Ok(data) => command_ok("list_forge_adapters", started_at, &state, data),
        Err(error) => map_error_with_command("list_forge_adapters", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_repository_integration_matrix(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<RepositoryIntegrationMatrix> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match forge_service::get_repository_integration_matrix(&repository_path) {
        Ok(data) => command_ok(
            "get_repository_integration_matrix",
            started_at,
            &state,
            data,
        ),
        Err(error) => map_error_with_command(
            "get_repository_integration_matrix",
            started_at,
            &state,
            error,
        ),
    }
}

#[tauri::command(async)]
pub fn get_repository_status(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<RepositoryStatusData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::get_repository_status(&repository_path) {
        Ok(data) => command_ok("get_repository_status", started_at, &state, data),
        Err(error) => map_error_with_command("get_repository_status", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_branches(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<BranchListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::list_branches(&repository_path) {
        Ok(data) => command_ok("list_branches", started_at, &state, data),
        Err(error) => map_error_with_command("list_branches", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn create_branch(
    repository_path: String,
    branch_name: String,
    from_ref: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::create_branch(&repository_path, &branch_name, from_ref.as_deref()) {
        Ok(_) => command_ok(
            "create_branch",
            started_at,
            &state,
            BranchOperationData {
                repository_path,
                branch_name,
                operation: "create".to_string(),
            },
        ),
        Err(error) => map_error_with_command("create_branch", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn checkout_branch(
    repository_path: String,
    branch_name: String,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::checkout_branch(&repository_path, &branch_name) {
        Ok(_) => command_ok(
            "checkout_branch",
            started_at,
            &state,
            BranchOperationData {
                repository_path,
                branch_name,
                operation: "checkout".to_string(),
            },
        ),
        Err(error) => map_error_with_command("checkout_branch", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn delete_branch(
    repository_path: String,
    branch_name: String,
    force: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let force = force.unwrap_or(false);

    match git_provider::delete_branch(&repository_path, &branch_name, force) {
        Ok(_) => command_ok(
            "delete_branch",
            started_at,
            &state,
            BranchOperationData {
                repository_path,
                branch_name,
                operation: if force {
                    "delete-force".to_string()
                } else {
                    "delete".to_string()
                },
            },
        ),
        Err(error) => map_error_with_command("delete_branch", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn rename_branch(
    repository_path: String,
    old_branch_name: String,
    new_branch_name: String,
    state: State<'_, AppState>,
) -> CommandResult<BranchOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::rename_branch(&repository_path, &old_branch_name, &new_branch_name) {
        Ok(_) => command_ok(
            "rename_branch",
            started_at,
            &state,
            BranchOperationData {
                repository_path,
                branch_name: new_branch_name,
                operation: "rename".to_string(),
            },
        ),
        Err(error) => map_error_with_command("rename_branch", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn set_branch_upstream(
    repository_path: String,
    branch_name: String,
    upstream: String,
    state: State<'_, AppState>,
) -> CommandResult<BranchTrackingOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::set_branch_upstream(&repository_path, &branch_name, &upstream) {
        Ok(_) => command_ok(
            "set_branch_upstream",
            started_at,
            &state,
            BranchTrackingOperationData {
                repository_path,
                branch_name,
                upstream,
                operation: "track".to_string(),
            },
        ),
        Err(error) => map_error_with_command("set_branch_upstream", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_stashes(
    repository_path: String,
    limit: Option<u32>,
    state: State<'_, AppState>,
) -> CommandResult<StashListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let limit = limit.unwrap_or(50).clamp(1, 500) as usize;

    match git_provider::list_stashes(&repository_path, limit) {
        Ok(data) => command_ok("list_stashes", started_at, &state, data),
        Err(error) => map_error_with_command("list_stashes", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn create_stash(
    repository_path: String,
    message: Option<String>,
    include_untracked: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<StashOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let include_untracked = include_untracked.unwrap_or(false);

    match git_provider::create_stash(&repository_path, message.as_deref(), include_untracked) {
        Ok(data) => command_ok("create_stash", started_at, &state, data),
        Err(error) => map_error_with_command("create_stash", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn pop_stash(
    repository_path: String,
    stash_ref: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<StashOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::pop_stash(&repository_path, stash_ref.as_deref()) {
        Ok(data) => command_ok("pop_stash", started_at, &state, data),
        Err(error) => map_error_with_command("pop_stash", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn drop_stash(
    repository_path: String,
    stash_ref: String,
    state: State<'_, AppState>,
) -> CommandResult<StashOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::drop_stash(&repository_path, &stash_ref) {
        Ok(data) => command_ok("drop_stash", started_at, &state, data),
        Err(error) => map_error_with_command("drop_stash", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_worktrees(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<WorktreeListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::list_worktrees(&repository_path) {
        Ok(data) => command_ok("list_worktrees", started_at, &state, data),
        Err(error) => map_error_with_command("list_worktrees", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn create_worktree(
    repository_path: String,
    worktree_path: String,
    branch_name: String,
    start_point: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<WorktreeOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::create_worktree(
        &repository_path,
        &worktree_path,
        &branch_name,
        start_point.as_deref(),
    ) {
        Ok(_) => command_ok(
            "create_worktree",
            started_at,
            &state,
            WorktreeOperationData {
                repository_path,
                operation: "create".to_string(),
                worktree_path,
                branch_name: Some(branch_name),
            },
        ),
        Err(error) => map_error_with_command("create_worktree", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn remove_worktree(
    repository_path: String,
    worktree_path: String,
    force: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<WorktreeOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let force = force.unwrap_or(false);

    match git_provider::remove_worktree(&repository_path, &worktree_path, force) {
        Ok(_) => command_ok(
            "remove_worktree",
            started_at,
            &state,
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
        ),
        Err(error) => map_error_with_command("remove_worktree", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_commit_history(
    repository_path: String,
    limit: Option<u32>,
    branch: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<CommitHistoryData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let limit = limit.unwrap_or(50).clamp(1, 500) as usize;

    match git_provider::list_commit_history(&repository_path, limit, branch.as_deref()) {
        Ok(data) => command_ok("list_commit_history", started_at, &state, data),
        Err(error) => map_error_with_command("list_commit_history", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_commit_detail(
    repository_path: String,
    commit_hash: String,
    state: State<'_, AppState>,
) -> CommandResult<CommitDetailData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::get_commit_detail(&repository_path, &commit_hash) {
        Ok(data) => command_ok("get_commit_detail", started_at, &state, data),
        Err(error) => map_error_with_command("get_commit_detail", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn stage_paths(
    repository_path: String,
    paths: Vec<String>,
    state: State<'_, AppState>,
) -> CommandResult<PathOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::stage_paths(&repository_path, &paths) {
        Ok(_) => command_ok(
            "stage_paths",
            started_at,
            &state,
            PathOperationData {
                repository_path,
                operation: "stage".to_string(),
                affected_paths: paths,
            },
        ),
        Err(error) => map_error_with_command("stage_paths", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn unstage_paths(
    repository_path: String,
    paths: Vec<String>,
    state: State<'_, AppState>,
) -> CommandResult<PathOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::unstage_paths(&repository_path, &paths) {
        Ok(_) => command_ok(
            "unstage_paths",
            started_at,
            &state,
            PathOperationData {
                repository_path,
                operation: "unstage".to_string(),
                affected_paths: paths,
            },
        ),
        Err(error) => map_error_with_command("unstage_paths", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn create_commit(
    repository_path: String,
    message: String,
    amend: bool,
    signoff: bool,
    state: State<'_, AppState>,
) -> CommandResult<CommitData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    let result = git_provider::create_commit(&repository_path, &message, amend, signoff).and_then(
        |summary| {
            git_provider::get_head_commit_hash(&repository_path).map(|commit_hash| CommitData {
                repository_path: repository_path.clone(),
                commit_hash,
                summary,
            })
        },
    );

    match result {
        Ok(data) => command_ok("create_commit", started_at, &state, data),
        Err(error) => map_error_with_command("create_commit", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_file_diff(
    repository_path: String,
    path: String,
    staged: Option<bool>,
    context_lines: Option<u32>,
    state: State<'_, AppState>,
) -> CommandResult<FileDiffData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let staged = staged.unwrap_or(false);
    let context_lines = context_lines.unwrap_or(3).clamp(0, 30) as usize;

    match git_provider::get_file_diff(&repository_path, &path, staged, context_lines) {
        Ok(diff_text) => command_ok(
            "get_file_diff",
            started_at,
            &state,
            FileDiffData { path, diff_text },
        ),
        Err(error) => map_error_with_command("get_file_diff", started_at, &state, error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrepareFileDiffChunksRequest {
    repository_path: String,
    path: String,
    staged: Option<bool>,
    context_lines: Option<u32>,
    chunk_size_bytes: Option<u32>,
    layout_width_px: Option<u32>,
    font_profile: Option<String>,
    line_height_px: Option<u32>,
}

#[tauri::command(async)]
pub fn prepare_file_diff_chunks(
    request: PrepareFileDiffChunksRequest,
    state: State<'_, AppState>,
) -> CommandResult<FileDiffManifestData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let staged = request.staged.unwrap_or(false);
    let context_lines = request.context_lines.unwrap_or(3).clamp(0, 30) as usize;
    let chunk_size = request.chunk_size_bytes.unwrap_or((64 * 1024) as u32) as usize;

    match diff_service::prepare_file_diff_chunks(
        &state,
        diff_service::PrepareFileDiffChunksInput {
            repository_path: &request.repository_path,
            path: &request.path,
            staged,
            context_lines,
            chunk_size_bytes: Some(chunk_size),
            layout_width_px: request.layout_width_px,
            font_profile: request.font_profile.as_deref(),
            line_height_px: request.line_height_px,
        },
    ) {
        Ok(data) => command_ok("prepare_file_diff_chunks", started_at, &state, data),
        Err(error) => map_error_with_command("prepare_file_diff_chunks", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_file_diff_chunk(
    diff_id: String,
    chunk_index: u32,
    state: State<'_, AppState>,
) -> CommandResult<FileDiffChunkData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match diff_service::get_file_diff_chunk(&state, &diff_id, chunk_index as usize) {
        Ok(data) => command_ok("get_file_diff_chunk", started_at, &state, data),
        Err(error) => map_error_with_command("get_file_diff_chunk", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn fetch_remote(
    repository_path: String,
    remote: Option<String>,
    prune: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<SyncData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let prune = prune.unwrap_or(false);

    match git_provider::fetch_remote(&repository_path, remote.as_deref(), prune) {
        Ok(output) => command_ok(
            "fetch_remote",
            started_at,
            &state,
            SyncData {
                operation: "fetch".to_string(),
                remote: remote.unwrap_or_else(|| "default".to_string()),
                branch: None,
                output,
            },
        ),
        Err(error) => map_error_with_command("fetch_remote", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn pull_remote(
    repository_path: String,
    remote: Option<String>,
    branch: Option<String>,
    rebase: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<SyncData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let rebase = rebase.unwrap_or(false);

    match git_provider::pull_remote(
        &repository_path,
        remote.as_deref(),
        branch.as_deref(),
        rebase,
    ) {
        Ok(output) => command_ok(
            "pull_remote",
            started_at,
            &state,
            SyncData {
                operation: "pull".to_string(),
                remote: remote.unwrap_or_else(|| "default".to_string()),
                branch,
                output,
            },
        ),
        Err(error) => map_error_with_command("pull_remote", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn push_remote(
    repository_path: String,
    remote: Option<String>,
    branch: Option<String>,
    force_with_lease: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<SyncData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let force_with_lease = force_with_lease.unwrap_or(false);

    match git_provider::push_remote(
        &repository_path,
        remote.as_deref(),
        branch.as_deref(),
        force_with_lease,
    ) {
        Ok(output) => command_ok(
            "push_remote",
            started_at,
            &state,
            SyncData {
                operation: "push".to_string(),
                remote: remote.unwrap_or_else(|| "default".to_string()),
                branch,
                output,
            },
        ),
        Err(error) => map_error_with_command("push_remote", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn start_rebase(
    repository_path: String,
    onto_ref: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::start_rebase(&repository_path, &onto_ref) {
        Ok(data) => command_ok("start_rebase", started_at, &state, data),
        Err(error) => map_error_with_command("start_rebase", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn continue_rebase(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::continue_rebase(&repository_path) {
        Ok(data) => command_ok("continue_rebase", started_at, &state, data),
        Err(error) => map_error_with_command("continue_rebase", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn abort_rebase(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::abort_rebase(&repository_path) {
        Ok(data) => command_ok("abort_rebase", started_at, &state, data),
        Err(error) => map_error_with_command("abort_rebase", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn start_cherry_pick(
    repository_path: String,
    commit_ref: String,
    mainline: Option<u32>,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::start_cherry_pick(&repository_path, &commit_ref, mainline) {
        Ok(data) => command_ok("start_cherry_pick", started_at, &state, data),
        Err(error) => map_error_with_command("start_cherry_pick", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn continue_cherry_pick(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::continue_cherry_pick(&repository_path) {
        Ok(data) => command_ok("continue_cherry_pick", started_at, &state, data),
        Err(error) => map_error_with_command("continue_cherry_pick", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn abort_cherry_pick(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::abort_cherry_pick(&repository_path) {
        Ok(data) => command_ok("abort_cherry_pick", started_at, &state, data),
        Err(error) => map_error_with_command("abort_cherry_pick", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_conflict_state(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<ConflictStateData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::get_conflict_state(&repository_path) {
        Ok(data) => command_ok("get_conflict_state", started_at, &state, data),
        Err(error) => map_error_with_command("get_conflict_state", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn continue_conflict_resolution(
    repository_path: String,
    operation: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::continue_conflict_resolution(&repository_path, operation.as_deref()) {
        Ok(data) => command_ok("continue_conflict_resolution", started_at, &state, data),
        Err(error) => {
            map_error_with_command("continue_conflict_resolution", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn abort_conflict_resolution(
    repository_path: String,
    operation: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<ConflictResolutionData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match git_provider::abort_conflict_resolution(&repository_path, operation.as_deref()) {
        Ok(data) => command_ok("abort_conflict_resolution", started_at, &state, data),
        Err(error) => {
            map_error_with_command("abort_conflict_resolution", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn list_issue_providers(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<IssueProviderListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match issue_service::list_issue_providers(&repository_path) {
        Ok(data) => command_ok("list_issue_providers", started_at, &state, data),
        Err(error) => map_error_with_command("list_issue_providers", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_local_issues(
    repository_path: String,
    provider_id: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match issue_service::list_issues(&repository_path, provider_id.as_deref()) {
        Ok(data) => command_ok("list_local_issues", started_at, &state, data),
        Err(error) => map_error_with_command("list_local_issues", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_pull_request_providers(
    repository_path: String,
    state: State<'_, AppState>,
) -> CommandResult<PullRequestProviderListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match pull_request_service::list_pull_request_providers(&repository_path) {
        Ok(data) => command_ok("list_pull_request_providers", started_at, &state, data),
        Err(error) => {
            map_error_with_command("list_pull_request_providers", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn list_pull_requests(
    repository_path: String,
    provider_id: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match pull_request_service::list_pull_requests(&repository_path, provider_id.as_deref()) {
        Ok(data) => command_ok("list_pull_requests", started_at, &state, data),
        Err(error) => map_error_with_command("list_pull_requests", started_at, &state, error),
    }
}

#[tauri::command(async)]
#[allow(clippy::too_many_arguments)]
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
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
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
        Ok(data) => command_ok("create_pull_request", started_at, &state, data),
        Err(error) => map_error_with_command("create_pull_request", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn close_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match pull_request_service::close_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
    ) {
        Ok(data) => command_ok("close_pull_request", started_at, &state, data),
        Err(error) => map_error_with_command("close_pull_request", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn reopen_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match pull_request_service::reopen_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
    ) {
        Ok(data) => command_ok("reopen_pull_request", started_at, &state, data),
        Err(error) => map_error_with_command("reopen_pull_request", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn mark_pull_request_ready(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match pull_request_service::mark_pull_request_ready(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
    ) {
        Ok(data) => command_ok("mark_pull_request_ready", started_at, &state, data),
        Err(error) => map_error_with_command("mark_pull_request_ready", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn merge_pull_request(
    repository_path: String,
    provider_id: Option<String>,
    pull_request_id: String,
    delete_source_branch: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<LocalPullRequestOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let delete_source_branch = delete_source_branch.unwrap_or(false);

    match pull_request_service::merge_pull_request(
        &repository_path,
        provider_id.as_deref(),
        &pull_request_id,
        delete_source_branch,
    ) {
        Ok(data) => command_ok("merge_pull_request", started_at, &state, data),
        Err(error) => map_error_with_command("merge_pull_request", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn create_local_issue(
    repository_path: String,
    provider_id: Option<String>,
    title: String,
    body: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match issue_service::create_issue(&repository_path, provider_id.as_deref(), &title, &body) {
        Ok(data) => command_ok("create_local_issue", started_at, &state, data),
        Err(error) => map_error_with_command("create_local_issue", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn close_local_issue(
    repository_path: String,
    provider_id: Option<String>,
    issue_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match issue_service::close_issue(&repository_path, provider_id.as_deref(), &issue_id) {
        Ok(data) => command_ok("close_local_issue", started_at, &state, data),
        Err(error) => map_error_with_command("close_local_issue", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn reopen_local_issue(
    repository_path: String,
    provider_id: Option<String>,
    issue_id: String,
    state: State<'_, AppState>,
) -> CommandResult<LocalIssueOperationData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match issue_service::reopen_issue(&repository_path, provider_id.as_deref(), &issue_id) {
        Ok(data) => command_ok("reopen_local_issue", started_at, &state, data),
        Err(error) => map_error_with_command("reopen_local_issue", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_ai_providers(state: State<'_, AppState>) -> CommandResult<AiProviderListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::list_providers() {
        Ok(data) => command_ok("list_ai_providers", started_at, &state, data),
        Err(error) => map_error_with_command("list_ai_providers", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn list_ai_model_options(state: State<'_, AppState>) -> CommandResult<AiModelOptionListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::list_model_options() {
        Ok(data) => command_ok("list_ai_model_options", started_at, &state, data),
        Err(error) => map_error_with_command("list_ai_model_options", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_ai_audit_entries(
    limit: Option<u32>,
    state: State<'_, AppState>,
) -> CommandResult<AiAuditListData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let limit = limit.unwrap_or(200).clamp(1, 1_000) as usize;

    match ai_service::get_audit_entries(Some(limit)) {
        Ok(data) => command_ok("get_ai_audit_entries", started_at, &state, data),
        Err(error) => map_error_with_command("get_ai_audit_entries", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn clear_ai_audit_entries(
    state: State<'_, AppState>,
) -> CommandResult<AiAuditMaintenanceData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::clear_audit_entries() {
        Ok(affected_entries) => command_ok(
            "clear_ai_audit_entries",
            started_at,
            &state,
            AiAuditMaintenanceData {
                operation: "clear".to_string(),
                affected_entries,
                sample_count: 0,
            },
        ),
        Err(error) => map_error_with_command("clear_ai_audit_entries", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn run_ai_diff_review(
    provider_id: String,
    repository_path: String,
    prompt: String,
    diff_scope_path: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::run_diff_review(
        &provider_id,
        &repository_path,
        &prompt,
        diff_scope_path.as_deref(),
    ) {
        Ok(data) => command_ok("run_ai_diff_review", started_at, &state, data),
        Err(error) => map_error_with_command("run_ai_diff_review", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn start_ai_diff_review_job(
    provider_id: String,
    repository_path: String,
    prompt: String,
    diff_scope_path: Option<String>,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewJobStartData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::start_diff_review_job(
        &state,
        &provider_id,
        &repository_path,
        &prompt,
        diff_scope_path.as_deref(),
    ) {
        Ok(data) => command_ok("start_ai_diff_review_job", started_at, &state, data),
        Err(error) => map_error_with_command("start_ai_diff_review_job", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_ai_diff_review_job(
    job_id: String,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewJobData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::get_diff_review_job(&state, &job_id) {
        Ok(data) => command_ok("get_ai_diff_review_job", started_at, &state, data),
        Err(error) => map_error_with_command("get_ai_diff_review_job", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn cancel_ai_diff_review_job(
    job_id: String,
    state: State<'_, AppState>,
) -> CommandResult<AiDiffReviewCancelData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match ai_service::cancel_diff_review_job(&state, &job_id) {
        Ok(data) => command_ok("cancel_ai_diff_review_job", started_at, &state, data),
        Err(error) => {
            map_error_with_command("cancel_ai_diff_review_job", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn get_startup_readiness_snapshot(
    refresh: Option<bool>,
    state: State<'_, AppState>,
) -> CommandResult<StartupReadinessSnapshotData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match bootstrap_service::get_startup_readiness_snapshot(refresh.unwrap_or(false)) {
        Ok(data) => command_ok("get_startup_readiness_snapshot", started_at, &state, data),
        Err(error) => {
            map_error_with_command("get_startup_readiness_snapshot", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn get_app_settings(state: State<'_, AppState>) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::get_settings() {
        Ok(data) => command_ok("get_app_settings", started_at, &state, data),
        Err(error) => map_error_with_command("get_app_settings", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn update_ai_guardrail(
    guardrail_value: f32,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::update_guardrail(guardrail_value) {
        Ok(data) => command_ok("update_ai_guardrail", started_at, &state, data),
        Err(error) => map_error_with_command("update_ai_guardrail", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn update_telemetry_retention(
    retention_days: u32,
    retention_mb: u32,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::update_telemetry_retention(retention_days, retention_mb) {
        Ok(data) => {
            let _ = telemetry_service::enforce_retention_policy();
            command_ok("update_telemetry_retention", started_at, &state, data)
        }
        Err(error) => {
            map_error_with_command("update_telemetry_retention", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn update_update_channel(
    update_channel: String,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::update_update_channel(&update_channel) {
        Ok(data) => command_ok("update_update_channel", started_at, &state, data),
        Err(error) => map_error_with_command("update_update_channel", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn check_for_app_update(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
) -> CommandResult<AppUpdateCheckData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match tauri::async_runtime::block_on(update_service::check_for_updates(&app)) {
        Ok(data) => command_ok("check_for_app_update", started_at, &state, data),
        Err(error) => map_error_with_command("check_for_app_update", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn install_app_update(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
) -> CommandResult<AppUpdateInstallData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match tauri::async_runtime::block_on(update_service::install_update(&app)) {
        Ok(data) => command_ok("install_app_update", started_at, &state, data),
        Err(error) => map_error_with_command("install_app_update", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn update_crash_reporting(
    crash_reporting_enabled: bool,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::update_crash_reporting(crash_reporting_enabled) {
        Ok(data) => command_ok("update_crash_reporting", started_at, &state, data),
        Err(error) => map_error_with_command("update_crash_reporting", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn update_layout_preferences(
    sidebar_width_px: u32,
    sidebar_position: String,
    utility_drawer_default_expanded: bool,
    utility_drawer_height_px: u32,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::update_layout_preferences(
        sidebar_width_px,
        &sidebar_position,
        utility_drawer_default_expanded,
        utility_drawer_height_px,
    ) {
        Ok(data) => command_ok("update_layout_preferences", started_at, &state, data),
        Err(error) => {
            map_error_with_command("update_layout_preferences", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn update_ui_preferences(
    theme_id: String,
    keybinding_profile: String,
    state: State<'_, AppState>,
) -> CommandResult<AppSettingsData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match settings_service::update_ui_preferences(&theme_id, &keybinding_profile) {
        Ok(data) => command_ok("update_ui_preferences", started_at, &state, data),
        Err(error) => map_error_with_command("update_ui_preferences", started_at, &state, error),
    }
}

#[tauri::command(async)]
pub fn get_command_telemetry_snapshot(
    recent_limit: Option<u32>,
    state: State<'_, AppState>,
) -> CommandResult<CommandTelemetrySnapshotData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());
    let recent_limit = recent_limit.unwrap_or(200).clamp(1, 1_000) as usize;

    match telemetry_service::get_command_telemetry_snapshot(Some(recent_limit)) {
        Ok(data) => command_ok("get_command_telemetry_snapshot", started_at, &state, data),
        Err(error) => {
            map_error_with_command("get_command_telemetry_snapshot", started_at, &state, error)
        }
    }
}

#[tauri::command(async)]
pub fn clear_command_telemetry(
    state: State<'_, AppState>,
) -> CommandResult<CommandTelemetryMaintenanceData> {
    let started_at = Instant::now();
    let request_id = Uuid::new_v4().to_string();
    logging_service::set_request_context(request_id.as_str());

    match telemetry_service::clear_command_samples() {
        Ok(affected_samples) => command_ok(
            "clear_command_telemetry",
            started_at,
            &state,
            CommandTelemetryMaintenanceData {
                operation: "clear".to_string(),
                affected_samples,
                sample_count: 0,
            },
        ),
        Err(error) => map_error_with_command("clear_command_telemetry", started_at, &state, error),
    }
}
