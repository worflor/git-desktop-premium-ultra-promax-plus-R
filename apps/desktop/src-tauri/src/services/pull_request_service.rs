use crate::errors::AppError;
use crate::models::operations::{
    LocalPullRequestListData, LocalPullRequestOperationData, PullRequestProviderData,
    PullRequestProviderListData,
};
use crate::services::{forge_service, local_pull_request_service};

const GITHUB_PULL_REQUEST_PROVIDER_ID: &str = "github-gh";

pub fn list_pull_request_providers(
    repository_path: &str,
) -> Result<PullRequestProviderListData, AppError> {
    let integration = forge_service::get_repository_integration_matrix(repository_path)?;
    let mut providers = vec![PullRequestProviderData {
        id: local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        display_name: "Local Pull Requests".to_string(),
        available: true,
        mode: "offline".to_string(),
        guidance: Some("Stored in .git/gdpu/local_pull_requests.json as first-party local collaboration artifacts.".to_string()),
    }];

    let has_github_remote = integration
        .remotes
        .iter()
        .any(|remote| remote.host_kind == "github");
    if has_github_remote {
        providers.push(PullRequestProviderData {
            id: GITHUB_PULL_REQUEST_PROVIDER_ID.to_string(),
            display_name: "GitHub Pull Requests (Planned)".to_string(),
            available: false,
            mode: "remote".to_string(),
            guidance: Some(
                "This phase prioritizes local-native parity before online provider execution."
                    .to_string(),
            ),
        });
    }

    Ok(PullRequestProviderListData {
        repository_path: repository_path.to_string(),
        default_provider_id: local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID.to_string(),
        providers,
    })
}

pub fn list_pull_requests(
    repository_path: &str,
    provider_id: Option<&str>,
) -> Result<LocalPullRequestListData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::list_local_pull_requests(repository_path)
        }
        GITHUB_PULL_REQUEST_PROVIDER_ID => {
            Err(provider_unavailable_error(GITHUB_PULL_REQUEST_PROVIDER_ID))
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }
}

pub fn create_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    title: &str,
    description: &str,
    source_branch: &str,
    target_branch: &str,
    draft: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::create_local_pull_request(
                repository_path,
                title,
                description,
                source_branch,
                target_branch,
                draft,
            )
        }
        GITHUB_PULL_REQUEST_PROVIDER_ID => {
            Err(provider_unavailable_error(GITHUB_PULL_REQUEST_PROVIDER_ID))
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }
}

pub fn close_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::close_local_pull_request(repository_path, pull_request_id)
        }
        GITHUB_PULL_REQUEST_PROVIDER_ID => {
            Err(provider_unavailable_error(GITHUB_PULL_REQUEST_PROVIDER_ID))
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }
}

pub fn reopen_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::reopen_local_pull_request(repository_path, pull_request_id)
        }
        GITHUB_PULL_REQUEST_PROVIDER_ID => {
            Err(provider_unavailable_error(GITHUB_PULL_REQUEST_PROVIDER_ID))
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }
}

pub fn mark_pull_request_ready(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::mark_local_pull_request_ready(repository_path, pull_request_id)
        }
        GITHUB_PULL_REQUEST_PROVIDER_ID => {
            Err(provider_unavailable_error(GITHUB_PULL_REQUEST_PROVIDER_ID))
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }
}

pub fn merge_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
    delete_source_branch: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    match resolve_provider(repository_path, provider_id)?.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::merge_local_pull_request(
                repository_path,
                pull_request_id,
                delete_source_branch,
            )
        }
        GITHUB_PULL_REQUEST_PROVIDER_ID => {
            Err(provider_unavailable_error(GITHUB_PULL_REQUEST_PROVIDER_ID))
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }
}

fn resolve_provider(repository_path: &str, provider_id: Option<&str>) -> Result<String, AppError> {
    let providers = list_pull_request_providers(repository_path)?;
    let requested = provider_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(providers.default_provider_id.as_str())
        .to_string();

    let selected = providers
        .providers
        .iter()
        .find(|provider| provider.id == requested)
        .ok_or_else(|| AppError::InvalidInput(format!("unknown pull request provider: {requested}")))?;

    if !selected.available {
        return Err(provider_unavailable_error(&requested));
    }

    Ok(requested)
}

fn provider_unavailable_error(provider_id: &str) -> AppError {
    AppError::InvalidInput(format!(
        "pull request provider '{provider_id}' is currently unavailable in this local-first phase"
    ))
}
