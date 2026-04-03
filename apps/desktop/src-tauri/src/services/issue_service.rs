use crate::errors::AppError;
use crate::models::operations::{
    IssueProviderData, IssueProviderListData, LocalIssueListData, LocalIssueOperationData,
};
use crate::services::{forge_service, local_issue_service};

const GITHUB_ISSUE_PROVIDER_ID: &str = "github-gh";

pub fn list_issue_providers(repository_path: &str) -> Result<IssueProviderListData, AppError> {
    let integration = forge_service::get_repository_integration_matrix(repository_path)?;
    let mut providers = vec![IssueProviderData {
        id: local_issue_service::LOCAL_ISSUE_PROVIDER_ID.to_string(),
        display_name: "Local Offline Issues".to_string(),
        available: true,
        mode: "offline".to_string(),
        guidance: Some("Stored in .git/gdpu/local_issues.json for local-first workflows.".to_string()),
    }];

    let has_github_remote = integration.remotes.iter().any(|remote| remote.host_kind == "github");
    if has_github_remote {
        providers.push(IssueProviderData {
            id: GITHUB_ISSUE_PROVIDER_ID.to_string(),
            display_name: "GitHub Issues (Planned)".to_string(),
            available: false,
            mode: "remote".to_string(),
            guidance: Some(
                "Local-first phase keeps issues on local-core to avoid online coupling regressions."
                    .to_string(),
            ),
        });
    }

    Ok(IssueProviderListData {
        repository_path: repository_path.to_string(),
        default_provider_id: local_issue_service::LOCAL_ISSUE_PROVIDER_ID.to_string(),
        providers,
    })
}

pub fn list_issues(
    repository_path: &str,
    provider_id: Option<&str>,
) -> Result<LocalIssueListData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID => local_issue_service::list_local_issues(repository_path),
        GITHUB_ISSUE_PROVIDER_ID => Err(provider_unavailable_error(GITHUB_ISSUE_PROVIDER_ID)),
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }
}

pub fn create_issue(
    repository_path: &str,
    provider_id: Option<&str>,
    title: &str,
    body: &str,
) -> Result<LocalIssueOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID => {
            local_issue_service::create_local_issue(repository_path, title, body)
        }
        GITHUB_ISSUE_PROVIDER_ID => Err(provider_unavailable_error(GITHUB_ISSUE_PROVIDER_ID)),
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }
}

pub fn close_issue(
    repository_path: &str,
    provider_id: Option<&str>,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID => {
            local_issue_service::close_local_issue(repository_path, issue_id)
        }
        GITHUB_ISSUE_PROVIDER_ID => Err(provider_unavailable_error(GITHUB_ISSUE_PROVIDER_ID)),
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }
}

pub fn reopen_issue(
    repository_path: &str,
    provider_id: Option<&str>,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID => {
            local_issue_service::reopen_local_issue(repository_path, issue_id)
        }
        GITHUB_ISSUE_PROVIDER_ID => Err(provider_unavailable_error(GITHUB_ISSUE_PROVIDER_ID)),
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }
}

fn resolve_provider(repository_path: &str, provider_id: Option<&str>) -> Result<String, AppError> {
    let providers = list_issue_providers(repository_path)?;
    let requested = provider_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(providers.default_provider_id.as_str())
        .to_string();

    let selected = providers
        .providers
        .iter()
        .find(|provider| provider.id == requested)
        .ok_or_else(|| AppError::InvalidInput(format!("unknown issue provider: {requested}")))?;

    if !selected.available {
        return Err(provider_unavailable_error(&requested));
    }

    Ok(requested)
}

fn provider_unavailable_error(provider_id: &str) -> AppError {
    AppError::InvalidInput(format!(
        "issue provider '{provider_id}' is currently unavailable in this local-first phase"
    ))
}
