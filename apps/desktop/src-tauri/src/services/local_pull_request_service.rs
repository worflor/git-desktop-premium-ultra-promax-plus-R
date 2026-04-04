use std::fs;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{
    LocalPullRequestData, LocalPullRequestListData, LocalPullRequestOperationData,
};
use crate::services::{git_provider, local_store, repository_root_service};

const PULL_REQUESTS_FILE_NAME: &str = "local_pull_requests.json";
pub const LOCAL_PULL_REQUEST_PROVIDER_ID: &str = "local-core";

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
struct StoredLocalPullRequest {
    id: String,
    title: String,
    description: String,
    source_branch: String,
    target_branch: String,
    state: String,
    draft: bool,
    created_at: String,
    updated_at: String,
    merged_at: Option<String>,
    closed_at: Option<String>,
    merge_commit_hash: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct StoredLocalPullRequestSet {
    pull_requests: Vec<StoredLocalPullRequest>,
}

pub fn list_local_pull_requests(
    repository_path: &str,
) -> Result<LocalPullRequestListData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let mut pull_requests: Vec<LocalPullRequestData> = load_pull_request_set(repository_path)?
        .pull_requests
        .into_iter()
        .map(to_data)
        .collect();

    pull_requests.sort_by(|a, b| {
        let rank_a = state_rank(&a.state, a.draft);
        let rank_b = state_rank(&b.state, b.draft);
        if rank_a != rank_b {
            return rank_a.cmp(&rank_b);
        }

        b.updated_at.cmp(&a.updated_at)
    });

    Ok(LocalPullRequestListData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        pull_requests,
    })
}

pub fn create_local_pull_request(
    repository_path: &str,
    title: &str,
    description: &str,
    source_branch: &str,
    target_branch: &str,
    draft: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let title = title.trim();
    if title.is_empty() {
        return Err(AppError::InvalidInput(
            "pull request title is required".to_string(),
        ));
    }

    let source_branch = source_branch.trim();
    let target_branch = target_branch.trim();
    if source_branch.is_empty() || target_branch.is_empty() {
        return Err(AppError::InvalidInput(
            "source and target branches are required".to_string(),
        ));
    }

    if source_branch == target_branch {
        return Err(AppError::InvalidInput(
            "source and target branches must differ".to_string(),
        ));
    }

    verify_branch_exists(repository_path, source_branch)?;
    verify_branch_exists(repository_path, target_branch)?;

    let mut pr_set = load_pull_request_set(repository_path)?;
    let duplicate_exists = pr_set.pull_requests.iter().any(|pull_request| {
        pull_request.state == "open"
            && pull_request.source_branch == source_branch
            && pull_request.target_branch == target_branch
    });
    if duplicate_exists {
        return Err(AppError::InvalidInput(
            "an open local pull request already exists for this source/target pair".to_string(),
        ));
    }

    let now = local_store::now_iso8601_string();
    let pull_request = StoredLocalPullRequest {
        id: Uuid::new_v4().to_string(),
        title: title.to_string(),
        description: description.trim().to_string(),
        source_branch: source_branch.to_string(),
        target_branch: target_branch.to_string(),
        state: "open".to_string(),
        draft,
        created_at: now.clone(),
        updated_at: now,
        merged_at: None,
        closed_at: None,
        merge_commit_hash: None,
    };

    pr_set.pull_requests.push(pull_request.clone());
    persist_pull_request_set(repository_path, &pr_set)?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        operation: "create".to_string(),
        pull_request: to_data(pull_request),
    })
}

pub fn close_local_pull_request(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_pull_request_state(repository_path, pull_request_id, "closed", "close")
}

pub fn reopen_local_pull_request(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_pull_request_state(repository_path, pull_request_id, "open", "reopen")
}

pub fn mark_local_pull_request_ready(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let pull_request_id = pull_request_id.trim();
    if pull_request_id.is_empty() {
        return Err(AppError::InvalidInput(
            "pull request id is required".to_string(),
        ));
    }

    let mut pr_set = load_pull_request_set(repository_path)?;
    let pull_request = pr_set
        .pull_requests
        .iter_mut()
        .find(|item| item.id == pull_request_id)
        .ok_or_else(|| {
            AppError::InvalidInput(format!("unknown pull request id: {pull_request_id}"))
        })?;

    if pull_request.state != "open" {
        return Err(AppError::InvalidInput(
            "only open pull requests can be marked ready".to_string(),
        ));
    }

    if !pull_request.draft {
        return Err(AppError::InvalidInput(
            "pull request is already ready".to_string(),
        ));
    }

    pull_request.draft = false;
    pull_request.updated_at = local_store::now_iso8601_string();
    let updated = pull_request.clone();

    persist_pull_request_set(repository_path, &pr_set)?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        operation: "mark-ready".to_string(),
        pull_request: to_data(updated),
    })
}

pub fn merge_local_pull_request(
    repository_path: &str,
    pull_request_id: &str,
    delete_source_branch: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let pull_request_id = pull_request_id.trim();
    if pull_request_id.is_empty() {
        return Err(AppError::InvalidInput(
            "pull request id is required".to_string(),
        ));
    }

    ensure_clean_worktree(repository_path)?;

    let mut pr_set = load_pull_request_set(repository_path)?;
    let pull_request = pr_set
        .pull_requests
        .iter_mut()
        .find(|item| item.id == pull_request_id)
        .ok_or_else(|| {
            AppError::InvalidInput(format!("unknown pull request id: {pull_request_id}"))
        })?;

    if pull_request.state != "open" {
        return Err(AppError::InvalidInput(
            "only open pull requests can be merged".to_string(),
        ));
    }

    if pull_request.draft {
        return Err(AppError::InvalidInput(
            "draft pull requests must be marked ready before merge".to_string(),
        ));
    }

    let source_branch = pull_request.source_branch.clone();
    let target_branch = pull_request.target_branch.clone();
    let merge_title = pull_request.title.clone();

    verify_branch_exists(repository_path, &source_branch)?;
    verify_branch_exists(repository_path, &target_branch)?;

    let original_branch = repository_root_service::get_repository_root_snapshot(repository_path)?
        .current_branch;

    let restore_branch = branch_to_restore_after_merge(
        &original_branch,
        &source_branch,
        &target_branch,
        delete_source_branch,
    );

    if original_branch != target_branch {
        git_provider::run_git(Some(repository_path), &["checkout", target_branch.as_str()])?;
    }

    let merge_message = format!("Merge local PR {pull_request_id}: {merge_title}");
    let merge_result = git_provider::run_git(
        Some(repository_path),
        &[
            "merge",
            "--no-ff",
            source_branch.as_str(),
            "-m",
            merge_message.as_str(),
        ],
    );

    if let Err(error) = merge_result {
        let _ = git_provider::run_git(Some(repository_path), &["merge", "--abort"]);
        if original_branch != target_branch {
            let _ = git_provider::run_git(
                Some(repository_path),
                &["checkout", original_branch.as_str()],
            );
        }
        return Err(error);
    }

    let merge_commit_hash = git_provider::run_git(Some(repository_path), &["rev-parse", "HEAD"])
        .map(|output| output.stdout)
        .ok();

    if delete_source_branch {
        let _ = git_provider::run_git(
            Some(repository_path),
            &["branch", "-d", source_branch.as_str()],
        );
    }

    let now = local_store::now_iso8601_string();
    pull_request.state = "merged".to_string();
    pull_request.updated_at = now.clone();
    pull_request.merged_at = Some(now);
    pull_request.closed_at = None;
    pull_request.merge_commit_hash = merge_commit_hash;
    let merged_pull_request = pull_request.clone();

    persist_pull_request_set(repository_path, &pr_set)?;

    if restore_branch != target_branch {
        let _ = git_provider::run_git(
            Some(repository_path),
            &["checkout", restore_branch.as_str()],
        );
    }

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        operation: "merge".to_string(),
        pull_request: to_data(merged_pull_request),
    })
}

fn update_pull_request_state(
    repository_path: &str,
    pull_request_id: &str,
    new_state: &str,
    operation: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let pull_request_id = pull_request_id.trim();
    if pull_request_id.is_empty() {
        return Err(AppError::InvalidInput(
            "pull request id is required".to_string(),
        ));
    }

    let mut pr_set = load_pull_request_set(repository_path)?;
    let pull_request = pr_set
        .pull_requests
        .iter_mut()
        .find(|item| item.id == pull_request_id)
        .ok_or_else(|| {
            AppError::InvalidInput(format!("unknown pull request id: {pull_request_id}"))
        })?;

    match new_state {
        "closed" => {
            if pull_request.state != "open" {
                return Err(AppError::InvalidInput(
                    "only open pull requests can be closed".to_string(),
                ));
            }
            let now = local_store::now_iso8601_string();
            pull_request.state = "closed".to_string();
            pull_request.updated_at = now.clone();
            pull_request.closed_at = Some(now);
        }
        "open" => {
            if pull_request.state != "closed" {
                return Err(AppError::InvalidInput(
                    "only closed pull requests can be reopened".to_string(),
                ));
            }
            pull_request.state = "open".to_string();
            pull_request.updated_at = local_store::now_iso8601_string();
            pull_request.closed_at = None;
        }
        _ => {
            return Err(AppError::InvalidInput(format!(
                "unsupported pull request state: {new_state}"
            )))
        }
    }

    let updated = pull_request.clone();
    persist_pull_request_set(repository_path, &pr_set)?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        operation: operation.to_string(),
        pull_request: to_data(updated),
    })
}

fn ensure_clean_worktree(repository_path: &str) -> Result<(), AppError> {
    let snapshot = repository_root_service::get_repository_root_snapshot(repository_path)?;
    if snapshot.worktree_dirty {
        return Err(AppError::InvalidInput(
            "working tree must be clean before local pull request merge".to_string(),
        ));
    }

    Ok(())
}

fn verify_branch_exists(repository_path: &str, branch_name: &str) -> Result<(), AppError> {
    let branch_name = branch_name.trim();
    if branch_name.is_empty() {
        return Err(AppError::InvalidInput(
            "branch name is required".to_string(),
        ));
    }

    let full_ref = format!("refs/heads/{branch_name}");
    git_provider::run_git(
        Some(repository_path),
        &["rev-parse", "--verify", full_ref.as_str()],
    )
    .map(|_| ())
}

fn state_rank(state: &str, draft: bool) -> u8 {
    match (state, draft) {
        ("open", false) => 0,
        ("open", true) => 1,
        ("merged", _) => 2,
        ("closed", _) => 3,
        _ => 4,
    }
}

fn load_pull_request_set(repository_path: &str) -> Result<StoredLocalPullRequestSet, AppError> {
    let path = local_store::gdpu_store_file_path(repository_path, PULL_REQUESTS_FILE_NAME)?;
    if !path.exists() {
        return Ok(StoredLocalPullRequestSet::default());
    }

    let payload = fs::read_to_string(path).map_err(|error| {
        AppError::Internal(format!("failed to read local pull requests: {error}"))
    })?;

    let mut pull_request_set = serde_json::from_str::<StoredLocalPullRequestSet>(&payload)
        .map_err(|error| {
            AppError::Internal(format!("failed to parse local pull requests: {error}"))
        })?;

    let mut normalized = false;
    for pull_request in &mut pull_request_set.pull_requests {
        let normalized_created_at = local_store::normalize_timestamp(&pull_request.created_at);
        if pull_request.created_at != normalized_created_at {
            pull_request.created_at = normalized_created_at;
            normalized = true;
        }

        let normalized_updated_at = local_store::normalize_timestamp(&pull_request.updated_at);
        if pull_request.updated_at != normalized_updated_at {
            pull_request.updated_at = normalized_updated_at;
            normalized = true;
        }

        if let Some(merged_at) = pull_request.merged_at.as_mut() {
            let normalized_merged_at = local_store::normalize_timestamp(merged_at);
            if *merged_at != normalized_merged_at {
                *merged_at = normalized_merged_at;
                normalized = true;
            }
        }

        if let Some(closed_at) = pull_request.closed_at.as_mut() {
            let normalized_closed_at = local_store::normalize_timestamp(closed_at);
            if *closed_at != normalized_closed_at {
                *closed_at = normalized_closed_at;
                normalized = true;
            }
        }
    }

    if normalized {
        let _ = persist_pull_request_set(repository_path, &pull_request_set);
    }

    Ok(pull_request_set)
}

fn persist_pull_request_set(
    repository_path: &str,
    pull_request_set: &StoredLocalPullRequestSet,
) -> Result<(), AppError> {
    let path = local_store::gdpu_store_file_path(repository_path, PULL_REQUESTS_FILE_NAME)?;
    let parent = path.parent().ok_or_else(|| {
        AppError::Internal("local pull request storage path is invalid".to_string())
    })?;

    fs::create_dir_all(parent).map_err(|error| {
        AppError::Internal(format!(
            "failed to create local pull request directory: {error}"
        ))
    })?;

    let payload = serde_json::to_string_pretty(pull_request_set).map_err(|error| {
        AppError::Internal(format!("failed to serialize local pull requests: {error}"))
    })?;

    fs::write(path, payload).map_err(|error| {
        AppError::Internal(format!("failed to persist local pull requests: {error}"))
    })
}

fn to_data(pull_request: StoredLocalPullRequest) -> LocalPullRequestData {
    LocalPullRequestData {
        id: pull_request.id,
        title: pull_request.title,
        description: pull_request.description,
        source_branch: pull_request.source_branch,
        target_branch: pull_request.target_branch,
        state: pull_request.state,
        draft: pull_request.draft,
        created_at: pull_request.created_at,
        updated_at: pull_request.updated_at,
        merged_at: pull_request.merged_at,
        closed_at: pull_request.closed_at,
        merge_commit_hash: pull_request.merge_commit_hash,
    }
}

fn branch_to_restore_after_merge(
    original_branch: &str,
    source_branch: &str,
    target_branch: &str,
    delete_source_branch: bool,
) -> String {
    if delete_source_branch && original_branch == source_branch {
        return target_branch.to_string();
    }

    original_branch.to_string()
}

#[cfg(test)]
mod tests {
    use super::branch_to_restore_after_merge;

    #[test]
    fn restore_branch_defaults_to_original() {
        let restore = branch_to_restore_after_merge("feature/a", "feature/b", "main", false);
        assert_eq!(restore, "feature/a");
    }

    #[test]
    fn restore_branch_uses_target_when_original_source_deleted() {
        let restore = branch_to_restore_after_merge("feature/a", "feature/a", "main", true);
        assert_eq!(restore, "main");
    }

    #[test]
    fn restore_branch_keeps_original_when_source_deleted_but_original_differs() {
        let restore = branch_to_restore_after_merge("release", "feature/a", "main", true);
        assert_eq!(restore, "release");
    }
}
