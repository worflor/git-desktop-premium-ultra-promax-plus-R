use crate::errors::AppError;
use crate::models::operations::{
    LocalPullRequestListData, LocalPullRequestOperationData, PullRequestProviderData,
    PullRequestProviderListData,
};
use crate::services::{forge_service, local_pull_request_service};

const GITHUB_PULL_REQUEST_PROVIDER_ID: &str = "github-gh";
const GITLAB_PULL_REQUEST_PROVIDER_ID: &str = "gitlab-contract";
const BITBUCKET_PULL_REQUEST_PROVIDER_ID: &str = "bitbucket-contract";

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
    let has_gitlab_remote = integration
        .remotes
        .iter()
        .any(|remote| remote.host_kind == "gitlab");
    let has_bitbucket_remote = integration
        .remotes
        .iter()
        .any(|remote| remote.host_kind == "bitbucket");

    if has_github_remote {
        providers.push(PullRequestProviderData {
            id: GITHUB_PULL_REQUEST_PROVIDER_ID.to_string(),
            display_name: "GitHub Pull Requests".to_string(),
            available: true,
            mode: "remote-mirrored".to_string(),
            guidance: Some(
                "Mirrored through local-core for offline-safe parity while preserving provider semantics."
                    .to_string(),
            ),
        });
    }

    if has_gitlab_remote {
        providers.push(PullRequestProviderData {
            id: GITLAB_PULL_REQUEST_PROVIDER_ID.to_string(),
            display_name: "GitLab Merge Requests".to_string(),
            available: true,
            mode: "remote-mirrored".to_string(),
            guidance: Some(
                "Mirrored through local-core while GitLab adapter remains contract-only in this build."
                    .to_string(),
            ),
        });
    }

    if has_bitbucket_remote {
        providers.push(PullRequestProviderData {
            id: BITBUCKET_PULL_REQUEST_PROVIDER_ID.to_string(),
            display_name: "Bitbucket Pull Requests".to_string(),
            available: true,
            mode: "remote-mirrored".to_string(),
            guidance: Some(
                "Mirrored through local-core while Bitbucket adapter remains contract-only in this build."
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
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let list_data = match provider_id.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID
        | GITHUB_PULL_REQUEST_PROVIDER_ID
        | GITLAB_PULL_REQUEST_PROVIDER_ID
        | BITBUCKET_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::list_local_pull_requests(repository_path)
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }?;

    Ok(with_pull_request_provider(list_data, &provider_id))
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
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID
        | GITHUB_PULL_REQUEST_PROVIDER_ID
        | GITLAB_PULL_REQUEST_PROVIDER_ID
        | BITBUCKET_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::create_local_pull_request(
                repository_path,
                title,
                description,
                source_branch,
                target_branch,
                draft,
            )
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }?;

    Ok(with_pull_request_operation_provider(
        operation_data,
        &provider_id,
    ))
}

pub fn close_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID
        | GITHUB_PULL_REQUEST_PROVIDER_ID
        | GITLAB_PULL_REQUEST_PROVIDER_ID
        | BITBUCKET_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::close_local_pull_request(repository_path, pull_request_id)
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }?;

    Ok(with_pull_request_operation_provider(
        operation_data,
        &provider_id,
    ))
}

pub fn reopen_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID
        | GITHUB_PULL_REQUEST_PROVIDER_ID
        | GITLAB_PULL_REQUEST_PROVIDER_ID
        | BITBUCKET_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::reopen_local_pull_request(repository_path, pull_request_id)
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }?;

    Ok(with_pull_request_operation_provider(
        operation_data,
        &provider_id,
    ))
}

pub fn mark_pull_request_ready(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
) -> Result<LocalPullRequestOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID
        | GITHUB_PULL_REQUEST_PROVIDER_ID
        | GITLAB_PULL_REQUEST_PROVIDER_ID
        | BITBUCKET_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::mark_local_pull_request_ready(
                repository_path,
                pull_request_id,
            )
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }?;

    Ok(with_pull_request_operation_provider(
        operation_data,
        &provider_id,
    ))
}

pub fn merge_pull_request(
    repository_path: &str,
    provider_id: Option<&str>,
    pull_request_id: &str,
    delete_source_branch: bool,
) -> Result<LocalPullRequestOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_pull_request_service::LOCAL_PULL_REQUEST_PROVIDER_ID
        | GITHUB_PULL_REQUEST_PROVIDER_ID
        | GITLAB_PULL_REQUEST_PROVIDER_ID
        | BITBUCKET_PULL_REQUEST_PROVIDER_ID => {
            local_pull_request_service::merge_local_pull_request(
                repository_path,
                pull_request_id,
                delete_source_branch,
            )
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown pull request provider: {unknown}"
        ))),
    }?;

    Ok(with_pull_request_operation_provider(
        operation_data,
        &provider_id,
    ))
}

fn resolve_provider(repository_path: &str, provider_id: Option<&str>) -> Result<String, AppError> {
    let providers = list_pull_request_providers(repository_path)?;
    let requested = provider_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(providers.default_provider_id.as_str())
        .to_string();

    if matches!(
        requested.as_str(),
        GITHUB_PULL_REQUEST_PROVIDER_ID
            | GITLAB_PULL_REQUEST_PROVIDER_ID
            | BITBUCKET_PULL_REQUEST_PROVIDER_ID
    ) && !providers
        .providers
        .iter()
        .any(|provider| provider.id == requested)
    {
        return Err(AppError::ForgeAdapterUnavailable(requested));
    }

    providers
        .providers
        .iter()
        .find(|provider| provider.id == requested)
        .ok_or_else(|| {
            AppError::InvalidInput(format!("unknown pull request provider: {requested}"))
        })?;

    Ok(requested)
}

fn with_pull_request_provider(
    mut data: LocalPullRequestListData,
    provider_id: &str,
) -> LocalPullRequestListData {
    data.provider_id = provider_id.to_string();
    data
}

fn with_pull_request_operation_provider(
    mut data: LocalPullRequestOperationData,
    provider_id: &str,
) -> LocalPullRequestOperationData {
    data.provider_id = provider_id.to_string();
    data
}
