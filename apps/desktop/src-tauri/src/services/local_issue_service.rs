use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{LocalIssueData, LocalIssueListData, LocalIssueOperationData};
use crate::services::local_store;

const ISSUES_FILE_NAME: &str = "local_issues.json";
pub const LOCAL_ISSUE_PROVIDER_ID: &str = "local-core";

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
struct StoredLocalIssue {
    id: String,
    title: String,
    body: String,
    state: String,
    created_at: String,
    updated_at: String,
    closed_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct StoredLocalIssueSet {
    issues: Vec<StoredLocalIssue>,
}

pub fn list_local_issues(repository_path: &str) -> Result<LocalIssueListData, AppError> {
    local_store::ensure_git_repository(repository_path)?;
    let issue_set = load_issue_set(repository_path)?;
    let mut issues: Vec<LocalIssueData> = issue_set.issues.into_iter().map(to_data).collect();

    issues.sort_by(|a, b| {
        if a.state == b.state {
            return b.updated_at.cmp(&a.updated_at);
        }
        if a.state == "open" {
            std::cmp::Ordering::Less
        } else {
            std::cmp::Ordering::Greater
        }
    });

    Ok(LocalIssueListData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_ISSUE_PROVIDER_ID.to_string(),
        issues,
    })
}

pub fn create_local_issue(
    repository_path: &str,
    title: &str,
    body: &str,
) -> Result<LocalIssueOperationData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let title = title.trim();
    if title.is_empty() {
        return Err(AppError::InvalidInput(
            "issue title is required".to_string(),
        ));
    }

    let now = local_store::now_iso8601_string();
    let issue = StoredLocalIssue {
        id: Uuid::new_v4().to_string(),
        title: title.to_string(),
        body: body.trim().to_string(),
        state: "open".to_string(),
        created_at: now.clone(),
        updated_at: now,
        closed_at: None,
    };

    let mut issue_set = load_issue_set(repository_path)?;
    issue_set.issues.push(issue.clone());
    persist_issue_set(repository_path, &issue_set)?;

    Ok(LocalIssueOperationData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_ISSUE_PROVIDER_ID.to_string(),
        operation: "create".to_string(),
        issue: to_data(issue),
    })
}

pub fn close_local_issue(
    repository_path: &str,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    set_local_issue_state(repository_path, issue_id, "closed", "close")
}

pub fn reopen_local_issue(
    repository_path: &str,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    set_local_issue_state(repository_path, issue_id, "open", "reopen")
}

fn set_local_issue_state(
    repository_path: &str,
    issue_id: &str,
    state: &str,
    operation: &str,
) -> Result<LocalIssueOperationData, AppError> {
    local_store::ensure_git_repository(repository_path)?;

    let issue_id = issue_id.trim();
    if issue_id.is_empty() {
        return Err(AppError::InvalidInput("issue id is required".to_string()));
    }

    let mut issue_set = load_issue_set(repository_path)?;
    let target = issue_set
        .issues
        .iter_mut()
        .find(|issue| issue.id == issue_id)
        .ok_or_else(|| AppError::InvalidInput(format!("unknown issue id: {issue_id}")))?;

    let now = local_store::now_iso8601_string();
    target.state = state.to_string();
    target.updated_at = now.clone();
    target.closed_at = if state.eq_ignore_ascii_case("closed") {
        Some(now)
    } else {
        None
    };
    let updated = target.clone();

    persist_issue_set(repository_path, &issue_set)?;

    Ok(LocalIssueOperationData {
        repository_path: repository_path.to_string(),
        provider_id: LOCAL_ISSUE_PROVIDER_ID.to_string(),
        operation: operation.to_string(),
        issue: to_data(updated),
    })
}

fn load_issue_set(repository_path: &str) -> Result<StoredLocalIssueSet, AppError> {
    let path = local_issues_file_path(repository_path)?;
    if !path.exists() {
        return Ok(StoredLocalIssueSet::default());
    }

    let payload = fs::read_to_string(path)
        .map_err(|error| AppError::Internal(format!("failed to read local issues: {error}")))?;

    let mut issue_set = serde_json::from_str::<StoredLocalIssueSet>(&payload)
        .map_err(|error| AppError::Internal(format!("failed to parse local issues: {error}")))?;

    let mut normalized = false;
    for issue in &mut issue_set.issues {
        let normalized_created_at = local_store::normalize_timestamp(&issue.created_at);
        if issue.created_at != normalized_created_at {
            issue.created_at = normalized_created_at;
            normalized = true;
        }

        let normalized_updated_at = local_store::normalize_timestamp(&issue.updated_at);
        if issue.updated_at != normalized_updated_at {
            issue.updated_at = normalized_updated_at;
            normalized = true;
        }

        if let Some(closed_at) = issue.closed_at.as_mut() {
            let normalized_closed_at = local_store::normalize_timestamp(closed_at);
            if *closed_at != normalized_closed_at {
                *closed_at = normalized_closed_at;
                normalized = true;
            }
        }
    }

    if normalized {
        let _ = persist_issue_set(repository_path, &issue_set);
    }

    Ok(issue_set)
}

fn persist_issue_set(repository_path: &str, issue_set: &StoredLocalIssueSet) -> Result<(), AppError> {
    let path = local_issues_file_path(repository_path)?;
    let parent = path
        .parent()
        .ok_or_else(|| AppError::Internal("local issue storage path is invalid".to_string()))?;

    fs::create_dir_all(parent)
        .map_err(|error| AppError::Internal(format!("failed to create local issue directory: {error}")))?;

    let payload = serde_json::to_string_pretty(issue_set)
        .map_err(|error| AppError::Internal(format!("failed to serialize local issues: {error}")))?;

    fs::write(path, payload)
        .map_err(|error| AppError::Internal(format!("failed to persist local issues: {error}")))
}

fn local_issues_file_path(repository_path: &str) -> Result<PathBuf, AppError> {
    local_store::gdpu_store_file_path(repository_path, ISSUES_FILE_NAME)
}

fn to_data(issue: StoredLocalIssue) -> LocalIssueData {
    LocalIssueData {
        id: issue.id,
        title: issue.title,
        body: issue.body,
        state: issue.state,
        created_at: issue.created_at,
        updated_at: issue.updated_at,
        closed_at: issue.closed_at,
    }
}

