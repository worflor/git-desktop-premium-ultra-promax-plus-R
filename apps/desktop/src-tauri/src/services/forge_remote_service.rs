use std::collections::HashMap;
use std::time::Duration;

use reqwest::blocking::{Client, RequestBuilder};
use reqwest::Method;
use serde_json::{json, Value};

use crate::errors::AppError;
use crate::models::operations::{
    LocalIssueData, LocalIssueListData, LocalIssueOperationData, LocalPullRequestData,
    LocalPullRequestListData, LocalPullRequestOperationData,
};
use crate::services::{local_store, remote_topology_service};

pub const GITLAB_PROVIDER_ID: &str = "gitlab-contract";
pub const BITBUCKET_PROVIDER_ID: &str = "bitbucket-contract";

const GITLAB_TOKEN_ENV_VARS: [&str; 2] = ["GDPU_GITLAB_TOKEN", "GITLAB_TOKEN"];
const BITBUCKET_TOKEN_ENV_VARS: [&str; 2] = ["GDPU_BITBUCKET_TOKEN", "BITBUCKET_TOKEN"];
const BITBUCKET_USERNAME_ENV_VARS: [&str; 2] = ["GDPU_BITBUCKET_USERNAME", "BITBUCKET_USERNAME"];
const BITBUCKET_APP_PASSWORD_ENV_VARS: [&str; 2] =
    ["GDPU_BITBUCKET_APP_PASSWORD", "BITBUCKET_APP_PASSWORD"];

#[derive(Debug, Clone)]
pub struct AdapterStatus {
    pub available: bool,
    pub auth_state: String,
    pub guidance: String,
}

#[derive(Debug, Clone)]
struct ResolvedRemote {
    host: String,
    path: String,
}

#[derive(Debug, Clone)]
struct BitbucketRemote {
    workspace: String,
    repo_slug: String,
}

enum BitbucketAuth {
    BearerToken(String),
    Basic {
        username: String,
        app_password: String,
    },
}

pub fn gitlab_adapter_status() -> AdapterStatus {
    if let Some((name, _)) = read_first_set_env_var(&GITLAB_TOKEN_ENV_VARS) {
        return AdapterStatus {
            available: true,
            auth_state: "authenticated".to_string(),
            guidance: format!("GitLab API token loaded from {name}."),
        };
    }

    AdapterStatus {
        available: false,
        auth_state: "unauthenticated".to_string(),
        guidance:
            "Set GDPU_GITLAB_TOKEN (or GITLAB_TOKEN) to enable GitLab issues/merge requests API operations."
                .to_string(),
    }
}

pub fn bitbucket_adapter_status() -> AdapterStatus {
    if let Some((name, _)) = read_first_set_env_var(&BITBUCKET_TOKEN_ENV_VARS) {
        return AdapterStatus {
            available: true,
            auth_state: "authenticated".to_string(),
            guidance: format!("Bitbucket bearer token loaded from {name}."),
        };
    }

    let username = read_first_set_env_var(&BITBUCKET_USERNAME_ENV_VARS);
    let app_password = read_first_set_env_var(&BITBUCKET_APP_PASSWORD_ENV_VARS);
    if let (Some((username_name, _)), Some((password_name, _))) = (username, app_password) {
        return AdapterStatus {
            available: true,
            auth_state: "authenticated".to_string(),
            guidance: format!(
                "Bitbucket basic auth loaded from {username_name} and {password_name}."
            ),
        };
    }

    AdapterStatus {
        available: false,
        auth_state: "unauthenticated".to_string(),
        guidance: "Set GDPU_BITBUCKET_TOKEN (or BITBUCKET_TOKEN) or set GDPU_BITBUCKET_USERNAME + GDPU_BITBUCKET_APP_PASSWORD to enable Bitbucket API operations.".to_string(),
    }
}

pub fn list_gitlab_issues(repository_path: &str) -> Result<LocalIssueListData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let payload = gitlab_request(
        Method::GET,
        remote.host.as_str(),
        format!(
            "/projects/{project_id}/issues?scope=all&state=all&order_by=updated_at&sort=desc&per_page=100"
        )
        .as_str(),
        None,
    )?;

    let mut issues = parse_gitlab_issue_array(payload)?;
    sort_issues(&mut issues);

    Ok(LocalIssueListData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        issues,
    })
}

pub fn create_gitlab_issue(
    repository_path: &str,
    title: &str,
    body: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let payload = gitlab_request(
        Method::POST,
        remote.host.as_str(),
        format!("/projects/{project_id}/issues").as_str(),
        Some(json!({
            "title": title,
            "description": body,
        })),
    )?;

    let issue = parse_gitlab_issue(payload.as_object())?;

    Ok(LocalIssueOperationData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        operation: "create".to_string(),
        issue,
    })
}

pub fn close_gitlab_issue(
    repository_path: &str,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    update_gitlab_issue_state(repository_path, issue_id, "close", "close")
}

pub fn reopen_gitlab_issue(
    repository_path: &str,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    update_gitlab_issue_state(repository_path, issue_id, "reopen", "reopen")
}

pub fn list_bitbucket_issues(repository_path: &str) -> Result<LocalIssueListData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let payload = bitbucket_request(
        Method::GET,
        remote.workspace.as_str(),
        remote.repo_slug.as_str(),
        "issues?sort=-updated_on&pagelen=100",
        None,
    )?;

    let mut issues = parse_bitbucket_issue_array(payload)?;
    sort_issues(&mut issues);

    Ok(LocalIssueListData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        issues,
    })
}

pub fn create_bitbucket_issue(
    repository_path: &str,
    title: &str,
    body: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let payload = bitbucket_request(
        Method::POST,
        remote.workspace.as_str(),
        remote.repo_slug.as_str(),
        "issues",
        Some(json!({
            "title": title,
            "content": {
                "raw": body,
            }
        })),
    )?;

    let issue = parse_bitbucket_issue(payload.as_object())?;

    Ok(LocalIssueOperationData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        operation: "create".to_string(),
        issue,
    })
}

pub fn close_bitbucket_issue(
    repository_path: &str,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    update_bitbucket_issue_state(repository_path, issue_id, "resolved", "close")
}

pub fn reopen_bitbucket_issue(
    repository_path: &str,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    update_bitbucket_issue_state(repository_path, issue_id, "new", "reopen")
}

pub fn list_gitlab_pull_requests(
    repository_path: &str,
) -> Result<LocalPullRequestListData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let payload = gitlab_request(
        Method::GET,
        remote.host.as_str(),
        format!(
            "/projects/{project_id}/merge_requests?state=all&order_by=updated_at&sort=desc&per_page=100"
        )
        .as_str(),
        None,
    )?;

    let mut pull_requests = parse_gitlab_pull_request_array(payload)?;
    sort_pull_requests(&mut pull_requests);

    Ok(LocalPullRequestListData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        pull_requests,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn create_gitlab_pull_request(
    repository_path: &str,
    title: &str,
    description: &str,
    source_branch: &str,
    target_branch: &str,
    draft: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let title = gitlab_apply_draft_prefix(title, draft);
    let payload = gitlab_request(
        Method::POST,
        remote.host.as_str(),
        format!("/projects/{project_id}/merge_requests").as_str(),
        Some(json!({
            "title": title,
            "description": description,
            "source_branch": source_branch,
            "target_branch": target_branch,
            "remove_source_branch": false,
        })),
    )?;

    let pull_request = parse_gitlab_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        operation: "create".to_string(),
        pull_request,
    })
}

pub fn close_gitlab_pull_request(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_gitlab_pull_request_state(repository_path, pull_request_id, "close", "close")
}

pub fn reopen_gitlab_pull_request(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_gitlab_pull_request_state(repository_path, pull_request_id, "reopen", "reopen")
}

pub fn mark_gitlab_pull_request_ready(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let pull_request_iid = parse_identifier(pull_request_id, "merge request id")?;

    let current = gitlab_request(
        Method::GET,
        remote.host.as_str(),
        format!(
            "/projects/{project_id}/merge_requests/{pull_request_iid}?include_rebase_in_progress=true"
        )
        .as_str(),
        None,
    )?;

    let current_title = value_as_string(current.as_object(), "title");
    let updated_title = strip_draft_prefix(current_title.as_deref().unwrap_or_default());
    if updated_title.trim().is_empty() {
        return Err(AppError::InvalidInput(
            "merge request title cannot be empty when clearing draft state".to_string(),
        ));
    }

    let payload = gitlab_request(
        Method::PUT,
        remote.host.as_str(),
        format!("/projects/{project_id}/merge_requests/{pull_request_iid}").as_str(),
        Some(json!({
            "title": updated_title,
        })),
    )?;

    let pull_request = parse_gitlab_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        operation: "mark-ready".to_string(),
        pull_request,
    })
}

pub fn merge_gitlab_pull_request(
    repository_path: &str,
    pull_request_id: &str,
    delete_source_branch: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let pull_request_iid = parse_identifier(pull_request_id, "merge request id")?;

    let payload = gitlab_request(
        Method::PUT,
        remote.host.as_str(),
        format!("/projects/{project_id}/merge_requests/{pull_request_iid}/merge").as_str(),
        Some(json!({
            "should_remove_source_branch": delete_source_branch,
        })),
    )?;

    let pull_request = parse_gitlab_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        operation: "merge".to_string(),
        pull_request,
    })
}

pub fn list_bitbucket_pull_requests(
    repository_path: &str,
) -> Result<LocalPullRequestListData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let mut pull_requests = HashMap::<String, LocalPullRequestData>::new();

    for state in ["OPEN", "MERGED", "DECLINED"] {
        let payload = bitbucket_request(
            Method::GET,
            remote.workspace.as_str(),
            remote.repo_slug.as_str(),
            format!("pullrequests?state={state}&pagelen=100").as_str(),
            None,
        )?;

        for pull_request in parse_bitbucket_pull_request_array(payload)? {
            pull_requests.insert(pull_request.id.clone(), pull_request);
        }
    }

    let mut sorted: Vec<LocalPullRequestData> = pull_requests.into_values().collect();
    sort_pull_requests(&mut sorted);

    Ok(LocalPullRequestListData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        pull_requests: sorted,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn create_bitbucket_pull_request(
    repository_path: &str,
    title: &str,
    description: &str,
    source_branch: &str,
    target_branch: &str,
    draft: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let payload = bitbucket_request(
        Method::POST,
        remote.workspace.as_str(),
        remote.repo_slug.as_str(),
        "pullrequests",
        Some(json!({
            "title": title,
            "description": description,
            "source": {
                "branch": {
                    "name": source_branch,
                }
            },
            "destination": {
                "branch": {
                    "name": target_branch,
                }
            },
            "close_source_branch": false,
            "draft": draft,
        })),
    )?;

    let pull_request = parse_bitbucket_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        operation: "create".to_string(),
        pull_request,
    })
}

pub fn close_bitbucket_pull_request(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_bitbucket_pull_request(repository_path, pull_request_id, json!({ "state": "DECLINED" }), "close")
}

pub fn reopen_bitbucket_pull_request(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_bitbucket_pull_request(repository_path, pull_request_id, json!({ "state": "OPEN" }), "reopen")
}

pub fn mark_bitbucket_pull_request_ready(
    repository_path: &str,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    update_bitbucket_pull_request(repository_path, pull_request_id, json!({ "draft": false }), "mark-ready")
}

pub fn merge_bitbucket_pull_request(
    repository_path: &str,
    pull_request_id: &str,
    delete_source_branch: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let pull_request_id = parse_identifier(pull_request_id, "pull request id")?;

    let payload = bitbucket_request(
        Method::POST,
        remote.workspace.as_str(),
        remote.repo_slug.as_str(),
        format!("pullrequests/{pull_request_id}/merge").as_str(),
        Some(json!({
            "close_source_branch": delete_source_branch,
        })),
    )?;

    let pull_request = parse_bitbucket_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        operation: "merge".to_string(),
        pull_request,
    })
}

fn update_gitlab_issue_state(
    repository_path: &str,
    issue_id: &str,
    state_event: &str,
    operation: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let issue_iid = parse_identifier(issue_id, "issue id")?;
    let payload = gitlab_request(
        Method::PUT,
        remote.host.as_str(),
        format!("/projects/{project_id}/issues/{issue_iid}").as_str(),
        Some(json!({
            "state_event": state_event,
        })),
    )?;

    let issue = parse_gitlab_issue(payload.as_object())?;

    Ok(LocalIssueOperationData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        operation: operation.to_string(),
        issue,
    })
}

fn update_bitbucket_issue_state(
    repository_path: &str,
    issue_id: &str,
    state: &str,
    operation: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let issue_id = parse_identifier(issue_id, "issue id")?;
    let payload = bitbucket_request(
        Method::PUT,
        remote.workspace.as_str(),
        remote.repo_slug.as_str(),
        format!("issues/{issue_id}").as_str(),
        Some(json!({
            "state": state,
        })),
    )?;

    let issue = parse_bitbucket_issue(payload.as_object())?;

    Ok(LocalIssueOperationData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        operation: operation.to_string(),
        issue,
    })
}

fn update_gitlab_pull_request_state(
    repository_path: &str,
    pull_request_id: &str,
    state_event: &str,
    operation: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_remote(repository_path, "gitlab")?;
    let project_id = urlencoding::encode(remote.path.as_str()).into_owned();
    let pull_request_iid = parse_identifier(pull_request_id, "merge request id")?;
    let payload = gitlab_request(
        Method::PUT,
        remote.host.as_str(),
        format!("/projects/{project_id}/merge_requests/{pull_request_iid}").as_str(),
        Some(json!({
            "state_event": state_event,
        })),
    )?;

    let pull_request = parse_gitlab_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: GITLAB_PROVIDER_ID.to_string(),
        operation: operation.to_string(),
        pull_request,
    })
}

fn update_bitbucket_pull_request(
    repository_path: &str,
    pull_request_id: &str,
    payload: Value,
    operation: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    let remote = resolve_bitbucket_remote(repository_path)?;
    let pull_request_id = parse_identifier(pull_request_id, "pull request id")?;
    let payload = bitbucket_request(
        Method::PUT,
        remote.workspace.as_str(),
        remote.repo_slug.as_str(),
        format!("pullrequests/{pull_request_id}").as_str(),
        Some(payload),
    )?;

    let pull_request = parse_bitbucket_pull_request(payload.as_object())?;

    Ok(LocalPullRequestOperationData {
        repository_path: repository_path.to_string(),
        provider_id: BITBUCKET_PROVIDER_ID.to_string(),
        operation: operation.to_string(),
        pull_request,
    })
}

fn resolve_remote(repository_path: &str, host_kind: &str) -> Result<ResolvedRemote, AppError> {
    let remote = remote_topology_service::resolve_remote_for_host_kind(repository_path, host_kind)
        .map_err(|error| match error {
            AppError::ForgeAdapterUnavailable(_) => AppError::ForgeAdapterUnavailable(match host_kind {
                "gitlab" => GITLAB_PROVIDER_ID.to_string(),
                "bitbucket" => BITBUCKET_PROVIDER_ID.to_string(),
                _ => host_kind.to_string(),
            }),
            other => other,
        })?;

    let host = remote.host.ok_or_else(|| {
        AppError::Internal("failed to parse remote host from repository topology".to_string())
    })?;
    let path = remote.normalized_path.ok_or_else(|| {
        AppError::Internal("failed to parse remote path from repository topology".to_string())
    })?;

    return Ok(ResolvedRemote { host, path });
}

fn resolve_bitbucket_remote(repository_path: &str) -> Result<BitbucketRemote, AppError> {
    let remote = resolve_remote(repository_path, "bitbucket")?;
    let mut segments = remote.path.split('/').filter(|value| !value.trim().is_empty());
    let workspace = segments
        .next()
        .ok_or_else(|| AppError::Internal("failed to parse Bitbucket workspace from remote URL".to_string()))?;
    let repo_slug = segments
        .next()
        .ok_or_else(|| AppError::Internal("failed to parse Bitbucket repository slug from remote URL".to_string()))?;

    Ok(BitbucketRemote {
        workspace: workspace.to_string(),
        repo_slug: repo_slug.to_string(),
    })
}

#[cfg(test)]
fn parse_remote_url(value: &str) -> Option<(String, String)> {
    remote_topology_service::parse_remote_url(value)
}

#[cfg(test)]
fn detect_host_kind(host: &str) -> &'static str {
    remote_topology_service::detect_host_kind_from_host(host)
}

fn parse_gitlab_issue_array(payload: Value) -> Result<Vec<LocalIssueData>, AppError> {
    let Some(entries) = payload.as_array() else {
        return Err(AppError::Internal(
            "GitLab issue list response was not an array".to_string(),
        ));
    };

    entries
        .iter()
        .map(|entry| parse_gitlab_issue(entry.as_object()))
        .collect()
}

fn parse_bitbucket_issue_array(payload: Value) -> Result<Vec<LocalIssueData>, AppError> {
    let Some(entries) = payload
        .as_object()
        .and_then(|value| value.get("values"))
        .and_then(Value::as_array)
    else {
        return Err(AppError::Internal(
            "Bitbucket issue list response missing values array".to_string(),
        ));
    };

    entries
        .iter()
        .map(|entry| parse_bitbucket_issue(entry.as_object()))
        .collect()
}

fn parse_gitlab_pull_request_array(payload: Value) -> Result<Vec<LocalPullRequestData>, AppError> {
    let Some(entries) = payload.as_array() else {
        return Err(AppError::Internal(
            "GitLab merge request list response was not an array".to_string(),
        ));
    };

    entries
        .iter()
        .map(|entry| parse_gitlab_pull_request(entry.as_object()))
        .collect()
}

fn parse_bitbucket_pull_request_array(
    payload: Value,
) -> Result<Vec<LocalPullRequestData>, AppError> {
    let Some(entries) = payload
        .as_object()
        .and_then(|value| value.get("values"))
        .and_then(Value::as_array)
    else {
        return Err(AppError::Internal(
            "Bitbucket pull request list response missing values array".to_string(),
        ));
    };

    entries
        .iter()
        .map(|entry| parse_bitbucket_pull_request(entry.as_object()))
        .collect()
}

fn parse_gitlab_issue(value: Option<&serde_json::Map<String, Value>>) -> Result<LocalIssueData, AppError> {
    let value = value
        .ok_or_else(|| AppError::Internal("GitLab issue payload was not an object".to_string()))?;

    let id = value_to_string(value.get("iid")).unwrap_or_else(|| {
        value_to_string(value.get("id")).unwrap_or_else(|| "unknown".to_string())
    });
    let title = value_as_string(Some(value), "title").unwrap_or_else(|| "Untitled issue".to_string());
    let body = value_as_string(Some(value), "description").unwrap_or_default();
    let state = normalize_gitlab_issue_state(
        value_as_string(Some(value), "state")
            .unwrap_or_else(|| "opened".to_string())
            .as_str(),
    );
    let created_at = normalize_timestamp(
        value_as_string(Some(value), "created_at")
            .unwrap_or_else(local_store::now_iso8601_string)
            .as_str(),
    );
    let updated_at = normalize_timestamp(
        value_as_string(Some(value), "updated_at")
            .unwrap_or_else(|| created_at.clone())
            .as_str(),
    );
    let closed_at = value
        .get("closed_at")
        .and_then(Value::as_str)
        .map(normalize_timestamp)
        .or_else(|| {
            if state == "closed" {
                Some(updated_at.clone())
            } else {
                None
            }
        });

    Ok(LocalIssueData {
        id,
        title,
        body,
        state,
        created_at,
        updated_at,
        closed_at,
    })
}

fn parse_bitbucket_issue(
    value: Option<&serde_json::Map<String, Value>>,
) -> Result<LocalIssueData, AppError> {
    let value = value
        .ok_or_else(|| AppError::Internal("Bitbucket issue payload was not an object".to_string()))?;

    let id = value_to_string(value.get("id")).unwrap_or_else(|| "unknown".to_string());
    let title = value_as_string(Some(value), "title").unwrap_or_else(|| "Untitled issue".to_string());
    let body = value
        .get("content")
        .and_then(Value::as_object)
        .and_then(|content| value_as_string(Some(content), "raw"))
        .unwrap_or_default();

    let state = normalize_bitbucket_issue_state(
        value_as_string(Some(value), "state")
            .unwrap_or_else(|| "new".to_string())
            .as_str(),
    );
    let created_at = normalize_timestamp(
        value_as_string(Some(value), "created_on")
            .unwrap_or_else(local_store::now_iso8601_string)
            .as_str(),
    );
    let updated_at = normalize_timestamp(
        value_as_string(Some(value), "updated_on")
            .unwrap_or_else(|| created_at.clone())
            .as_str(),
    );
    let closed_at = if state == "closed" {
        Some(updated_at.clone())
    } else {
        None
    };

    Ok(LocalIssueData {
        id,
        title,
        body,
        state,
        created_at,
        updated_at,
        closed_at,
    })
}

fn parse_gitlab_pull_request(
    value: Option<&serde_json::Map<String, Value>>,
) -> Result<LocalPullRequestData, AppError> {
    let value = value.ok_or_else(|| {
        AppError::Internal("GitLab merge request payload was not an object".to_string())
    })?;

    let id = value_to_string(value.get("iid")).unwrap_or_else(|| {
        value_to_string(value.get("id")).unwrap_or_else(|| "unknown".to_string())
    });
    let title = value_as_string(Some(value), "title").unwrap_or_else(|| "Untitled merge request".to_string());
    let description = value_as_string(Some(value), "description").unwrap_or_default();
    let source_branch = value_as_string(Some(value), "source_branch").unwrap_or_default();
    let target_branch = value_as_string(Some(value), "target_branch").unwrap_or_default();
    let state = normalize_gitlab_pull_request_state(
        value_as_string(Some(value), "state")
            .unwrap_or_else(|| "opened".to_string())
            .as_str(),
    );

    let draft = value
        .get("draft")
        .and_then(Value::as_bool)
        .unwrap_or_else(|| title_is_draft(title.as_str()));

    let created_at = normalize_timestamp(
        value_as_string(Some(value), "created_at")
            .unwrap_or_else(local_store::now_iso8601_string)
            .as_str(),
    );
    let updated_at = normalize_timestamp(
        value_as_string(Some(value), "updated_at")
            .unwrap_or_else(|| created_at.clone())
            .as_str(),
    );

    let merged_at = value
        .get("merged_at")
        .and_then(Value::as_str)
        .map(normalize_timestamp)
        .or_else(|| {
            if state == "merged" {
                Some(updated_at.clone())
            } else {
                None
            }
        });

    let closed_at = value
        .get("closed_at")
        .and_then(Value::as_str)
        .map(normalize_timestamp)
        .or_else(|| {
            if state == "closed" {
                Some(updated_at.clone())
            } else {
                None
            }
        });

    let merge_commit_hash = value
        .get("merge_commit_sha")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_string());

    Ok(LocalPullRequestData {
        id,
        title,
        description,
        source_branch,
        target_branch,
        state,
        draft,
        created_at,
        updated_at,
        merged_at,
        closed_at,
        merge_commit_hash,
    })
}

fn parse_bitbucket_pull_request(
    value: Option<&serde_json::Map<String, Value>>,
) -> Result<LocalPullRequestData, AppError> {
    let value = value.ok_or_else(|| {
        AppError::Internal("Bitbucket pull request payload was not an object".to_string())
    })?;

    let id = value_to_string(value.get("id")).unwrap_or_else(|| "unknown".to_string());
    let title = value_as_string(Some(value), "title").unwrap_or_else(|| "Untitled pull request".to_string());
    let description = value_as_string(Some(value), "description").unwrap_or_default();
    let source_branch = value
        .get("source")
        .and_then(Value::as_object)
        .and_then(|source| source.get("branch"))
        .and_then(Value::as_object)
        .and_then(|branch| value_as_string(Some(branch), "name"))
        .unwrap_or_default();
    let target_branch = value
        .get("destination")
        .and_then(Value::as_object)
        .and_then(|destination| destination.get("branch"))
        .and_then(Value::as_object)
        .and_then(|branch| value_as_string(Some(branch), "name"))
        .unwrap_or_default();

    let state = normalize_bitbucket_pull_request_state(
        value_as_string(Some(value), "state")
            .unwrap_or_else(|| "OPEN".to_string())
            .as_str(),
    );

    let draft = value.get("draft").and_then(Value::as_bool).unwrap_or(false);

    let created_at = normalize_timestamp(
        value_as_string(Some(value), "created_on")
            .unwrap_or_else(local_store::now_iso8601_string)
            .as_str(),
    );
    let updated_at = normalize_timestamp(
        value_as_string(Some(value), "updated_on")
            .unwrap_or_else(|| created_at.clone())
            .as_str(),
    );

    let merged_at = if state == "merged" {
        Some(updated_at.clone())
    } else {
        None
    };
    let closed_at = if state == "closed" {
        Some(updated_at.clone())
    } else {
        None
    };
    let merge_commit_hash = value
        .get("merge_commit")
        .and_then(Value::as_object)
        .and_then(|merge_commit| value_as_string(Some(merge_commit), "hash"));

    Ok(LocalPullRequestData {
        id,
        title,
        description,
        source_branch,
        target_branch,
        state,
        draft,
        created_at,
        updated_at,
        merged_at,
        closed_at,
        merge_commit_hash,
    })
}

fn gitlab_request(
    method: Method,
    host: &str,
    path_and_query: &str,
    payload: Option<Value>,
) -> Result<Value, AppError> {
    let token = read_first_set_env_var(&GITLAB_TOKEN_ENV_VARS)
        .map(|(_, value)| value)
        .ok_or_else(|| AppError::ForgeAdapterUnavailable(GITLAB_PROVIDER_ID.to_string()))?;

    let client = http_client()?;
    let url = format!("https://{host}/api/v4{path_and_query}");
    let mut request = client
        .request(method, url)
        .header("PRIVATE-TOKEN", token)
        .header("Accept", "application/json");

    if let Some(payload) = payload {
        request = request.header("Content-Type", "application/json").json(&payload);
    }

    execute_json_request(request, "GitLab API request")
}

fn bitbucket_request(
    method: Method,
    workspace: &str,
    repo_slug: &str,
    path_and_query: &str,
    payload: Option<Value>,
) -> Result<Value, AppError> {
    let auth = resolve_bitbucket_auth()
        .ok_or_else(|| AppError::ForgeAdapterUnavailable(BITBUCKET_PROVIDER_ID.to_string()))?;

    let encoded_workspace = urlencoding::encode(workspace).into_owned();
    let encoded_repo_slug = urlencoding::encode(repo_slug).into_owned();
    let path_and_query = path_and_query.trim_start_matches('/');
    let url = format!(
        "https://api.bitbucket.org/2.0/repositories/{encoded_workspace}/{encoded_repo_slug}/{path_and_query}"
    );

    let client = http_client()?;
    let mut request = client.request(method, url).header("Accept", "application/json");
    request = match auth {
        BitbucketAuth::BearerToken(token) => request.bearer_auth(token),
        BitbucketAuth::Basic {
            username,
            app_password,
        } => request.basic_auth(username, Some(app_password)),
    };

    if let Some(payload) = payload {
        request = request.header("Content-Type", "application/json").json(&payload);
    }

    execute_json_request(request, "Bitbucket API request")
}

fn resolve_bitbucket_auth() -> Option<BitbucketAuth> {
    if let Some((_, token)) = read_first_set_env_var(&BITBUCKET_TOKEN_ENV_VARS) {
        return Some(BitbucketAuth::BearerToken(token));
    }

    let username = read_first_set_env_var(&BITBUCKET_USERNAME_ENV_VARS).map(|(_, value)| value);
    let app_password =
        read_first_set_env_var(&BITBUCKET_APP_PASSWORD_ENV_VARS).map(|(_, value)| value);

    match (username, app_password) {
        (Some(username), Some(app_password)) => Some(BitbucketAuth::Basic {
            username,
            app_password,
        }),
        _ => None,
    }
}

fn read_first_set_env_var(candidates: &[&str]) -> Option<(String, String)> {
    for candidate in candidates {
        let Ok(value) = std::env::var(candidate) else {
            continue;
        };
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }

        return Some(((*candidate).to_string(), trimmed.to_string()));
    }

    None
}

fn http_client() -> Result<Client, AppError> {
    Client::builder()
        .timeout(Duration::from_secs(20))
        .user_agent("gdpu-desktop/0.1")
        .build()
        .map_err(|error| AppError::Internal(format!("failed to initialize HTTP client: {error}")))
}

fn execute_json_request(request: RequestBuilder, context: &str) -> Result<Value, AppError> {
    let response = request
        .send()
        .map_err(|error| AppError::CommandExecution(format!("{context} failed: {error}")))?;

    let status = response.status();
    let body = response.text().unwrap_or_default();
    if !status.is_success() {
        let message = extract_remote_error_message(body.as_str())
            .unwrap_or_else(|| truncate_message(body.as_str(), 280));
        return Err(AppError::CommandExecution(format!(
            "{context} returned HTTP {}: {message}",
            status.as_u16()
        )));
    }

    if body.trim().is_empty() {
        return Ok(Value::Object(serde_json::Map::new()));
    }

    serde_json::from_str(body.as_str()).map_err(|error| {
        AppError::Internal(format!("{context} returned malformed JSON payload: {error}"))
    })
}

fn extract_remote_error_message(body: &str) -> Option<String> {
    let trimmed = body.trim();
    if trimmed.is_empty() {
        return None;
    }

    let Ok(payload) = serde_json::from_str::<Value>(trimmed) else {
        return None;
    };

    if let Some(message) = payload.get("message").and_then(Value::as_str) {
        return Some(message.to_string());
    }

    if let Some(message) = payload
        .get("error")
        .and_then(Value::as_object)
        .and_then(|error| value_as_string(Some(error), "message"))
    {
        return Some(message);
    }

    if let Some(errors) = payload.get("errors").and_then(Value::as_array) {
        let collected = errors
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join("; ");
        if !collected.trim().is_empty() {
            return Some(collected);
        }
    }

    None
}

fn normalize_gitlab_issue_state(value: &str) -> String {
    let normalized = value.trim().to_ascii_lowercase();
    if normalized == "opened" || normalized == "open" {
        return "open".to_string();
    }

    "closed".to_string()
}

fn normalize_bitbucket_issue_state(value: &str) -> String {
    let normalized = value.trim().to_ascii_lowercase();
    if matches!(
        normalized.as_str(),
        "new" | "open" | "on hold" | "on_hold"
    ) {
        return "open".to_string();
    }

    "closed".to_string()
}

fn normalize_gitlab_pull_request_state(value: &str) -> String {
    match value.trim().to_ascii_lowercase().as_str() {
        "opened" | "open" => "open".to_string(),
        "merged" => "merged".to_string(),
        _ => "closed".to_string(),
    }
}

fn normalize_bitbucket_pull_request_state(value: &str) -> String {
    match value.trim().to_ascii_uppercase().as_str() {
        "OPEN" => "open".to_string(),
        "MERGED" => "merged".to_string(),
        _ => "closed".to_string(),
    }
}

fn value_to_string(value: Option<&Value>) -> Option<String> {
    match value {
        Some(Value::String(text)) => Some(text.to_string()),
        Some(Value::Number(number)) => Some(number.to_string()),
        Some(Value::Bool(boolean)) => Some(boolean.to_string()),
        _ => None,
    }
}

fn value_as_string(
    value: Option<&serde_json::Map<String, Value>>,
    key: &str,
) -> Option<String> {
    value.and_then(|value| value_to_string(value.get(key)))
}

fn normalize_timestamp(value: &str) -> String {
    local_store::normalize_timestamp(value)
}

fn parse_identifier(value: &str, label: &str) -> Result<String, AppError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(AppError::InvalidInput(format!("{label} is required")));
    }

    Ok(trimmed.to_string())
}

fn sort_issues(issues: &mut [LocalIssueData]) {
    issues.sort_by(|left, right| {
        if left.state == right.state {
            return right.updated_at.cmp(&left.updated_at);
        }

        if left.state == "open" {
            return std::cmp::Ordering::Less;
        }

        std::cmp::Ordering::Greater
    });
}

fn sort_pull_requests(pull_requests: &mut [LocalPullRequestData]) {
    pull_requests.sort_by(|left, right| {
        let left_rank = pull_request_rank(left.state.as_str(), left.draft);
        let right_rank = pull_request_rank(right.state.as_str(), right.draft);

        if left_rank != right_rank {
            return left_rank.cmp(&right_rank);
        }

        right.updated_at.cmp(&left.updated_at)
    });
}

fn pull_request_rank(state: &str, draft: bool) -> u8 {
    match (state, draft) {
        ("open", false) => 0,
        ("open", true) => 1,
        ("merged", _) => 2,
        ("closed", _) => 3,
        _ => 4,
    }
}

fn title_is_draft(title: &str) -> bool {
    let trimmed = title.trim();
    trimmed.starts_with("Draft:")
        || trimmed.starts_with("draft:")
        || trimmed.starts_with("WIP:")
        || trimmed.starts_with("wip:")
}

fn gitlab_apply_draft_prefix(title: &str, draft: bool) -> String {
    if !draft {
        return title.trim().to_string();
    }

    if title_is_draft(title) {
        return title.trim().to_string();
    }

    format!("Draft: {}", title.trim())
}

fn strip_draft_prefix(title: &str) -> String {
    for prefix in ["Draft:", "draft:", "WIP:", "wip:"] {
        if let Some(rest) = title.strip_prefix(prefix) {
            return rest.trim().to_string();
        }
    }

    title.trim().to_string()
}

fn truncate_message(value: &str, max_chars: usize) -> String {
    let mut iter = value.chars();
    let truncated: String = iter.by_ref().take(max_chars).collect();
    if iter.next().is_some() {
        return format!("{truncated}...");
    }

    truncated
}

#[cfg(test)]
mod tests {
    use super::{
        detect_host_kind, normalize_bitbucket_issue_state, parse_remote_url, strip_draft_prefix,
        title_is_draft,
    };

    #[test]
    fn parse_remote_url_handles_https_and_ssh_urls() {
        let https = parse_remote_url("https://gitlab.com/group/project.git")
            .expect("https remote should parse");
        assert_eq!(https.0, "gitlab.com");
        assert_eq!(https.1, "group/project");

        let ssh = parse_remote_url("git@bitbucket.org:workspace/repo.git")
            .expect("ssh remote should parse");
        assert_eq!(ssh.0, "bitbucket.org");
        assert_eq!(ssh.1, "workspace/repo");
    }

    #[test]
    fn detect_host_kind_classifies_forge_hosts() {
        assert_eq!(detect_host_kind("gitlab.com"), "gitlab");
        assert_eq!(detect_host_kind("bitbucket.org"), "bitbucket");
        assert_eq!(detect_host_kind("github.com"), "github");
        assert_eq!(detect_host_kind("example.com"), "generic");
    }

    #[test]
    fn bitbucket_issue_state_maps_to_open_closed() {
        assert_eq!(normalize_bitbucket_issue_state("new"), "open");
        assert_eq!(normalize_bitbucket_issue_state("open"), "open");
        assert_eq!(normalize_bitbucket_issue_state("resolved"), "closed");
    }

    #[test]
    fn draft_prefix_helpers_round_trip() {
        assert!(title_is_draft("Draft: add api integration"));
        assert!(title_is_draft("wip: add api integration"));
        assert_eq!(strip_draft_prefix("Draft: add api integration"), "add api integration");
        assert_eq!(strip_draft_prefix("title without prefix"), "title without prefix");
    }
}
