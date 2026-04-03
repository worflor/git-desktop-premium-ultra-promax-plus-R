use crate::errors::AppError;
use crate::models::operations::{
    IssueProviderData, IssueProviderListData, LocalIssueListData, LocalIssueOperationData,
};
use crate::services::{forge_service, local_issue_service};

const GITHUB_ISSUE_PROVIDER_ID: &str = "github-gh";
const GITLAB_ISSUE_PROVIDER_ID: &str = "gitlab-contract";
const BITBUCKET_ISSUE_PROVIDER_ID: &str = "bitbucket-contract";

pub fn list_issue_providers(repository_path: &str) -> Result<IssueProviderListData, AppError> {
    let integration = forge_service::get_repository_integration_matrix(repository_path)?;
    let mut providers = vec![IssueProviderData {
        id: local_issue_service::LOCAL_ISSUE_PROVIDER_ID.to_string(),
        display_name: "Local Offline Issues".to_string(),
        available: true,
        mode: "offline".to_string(),
        guidance: Some(
            "Stored in .git/gdpu/local_issues.json for local-first workflows.".to_string(),
        ),
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
        providers.push(IssueProviderData {
            id: GITHUB_ISSUE_PROVIDER_ID.to_string(),
            display_name: "GitHub Issues".to_string(),
            available: true,
            mode: "remote-mirrored".to_string(),
            guidance: Some(
                "Mirrored through local-core for offline-safe parity while preserving provider semantics."
                    .to_string(),
            ),
        });
    }

    if has_gitlab_remote {
        providers.push(IssueProviderData {
            id: GITLAB_ISSUE_PROVIDER_ID.to_string(),
            display_name: "GitLab Issues".to_string(),
            available: true,
            mode: "remote-mirrored".to_string(),
            guidance: Some(
                "Mirrored through local-core while GitLab adapter remains contract-only in this build."
                    .to_string(),
            ),
        });
    }

    if has_bitbucket_remote {
        providers.push(IssueProviderData {
            id: BITBUCKET_ISSUE_PROVIDER_ID.to_string(),
            display_name: "Bitbucket Issues".to_string(),
            available: true,
            mode: "remote-mirrored".to_string(),
            guidance: Some(
                "Mirrored through local-core while Bitbucket adapter remains contract-only in this build."
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
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let list_data = match provider_id.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID
        | GITHUB_ISSUE_PROVIDER_ID
        | GITLAB_ISSUE_PROVIDER_ID
        | BITBUCKET_ISSUE_PROVIDER_ID => local_issue_service::list_local_issues(repository_path),
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }?;

    Ok(with_issue_provider(list_data, &provider_id))
}

pub fn create_issue(
    repository_path: &str,
    provider_id: Option<&str>,
    title: &str,
    body: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID
        | GITHUB_ISSUE_PROVIDER_ID
        | GITLAB_ISSUE_PROVIDER_ID
        | BITBUCKET_ISSUE_PROVIDER_ID => {
            local_issue_service::create_local_issue(repository_path, title, body)
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }?;

    Ok(with_issue_operation_provider(operation_data, &provider_id))
}

pub fn close_issue(
    repository_path: &str,
    provider_id: Option<&str>,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID
        | GITHUB_ISSUE_PROVIDER_ID
        | GITLAB_ISSUE_PROVIDER_ID
        | BITBUCKET_ISSUE_PROVIDER_ID => {
            local_issue_service::close_local_issue(repository_path, issue_id)
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }?;

    Ok(with_issue_operation_provider(operation_data, &provider_id))
}

pub fn reopen_issue(
    repository_path: &str,
    provider_id: Option<&str>,
    issue_id: &str,
) -> Result<LocalIssueOperationData, AppError> {
    let provider_id = resolve_provider(repository_path, provider_id)?;

    let operation_data = match provider_id.as_str() {
        local_issue_service::LOCAL_ISSUE_PROVIDER_ID
        | GITHUB_ISSUE_PROVIDER_ID
        | GITLAB_ISSUE_PROVIDER_ID
        | BITBUCKET_ISSUE_PROVIDER_ID => {
            local_issue_service::reopen_local_issue(repository_path, issue_id)
        }
        unknown => Err(AppError::InvalidInput(format!(
            "unknown issue provider: {unknown}"
        ))),
    }?;

    Ok(with_issue_operation_provider(operation_data, &provider_id))
}

fn resolve_provider(repository_path: &str, provider_id: Option<&str>) -> Result<String, AppError> {
    let providers = list_issue_providers(repository_path)?;
    let requested = provider_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(providers.default_provider_id.as_str())
        .to_string();

    if matches!(
        requested.as_str(),
        GITHUB_ISSUE_PROVIDER_ID | GITLAB_ISSUE_PROVIDER_ID | BITBUCKET_ISSUE_PROVIDER_ID
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
        .ok_or_else(|| AppError::InvalidInput(format!("unknown issue provider: {requested}")))?;

    Ok(requested)
}

fn with_issue_provider(mut data: LocalIssueListData, provider_id: &str) -> LocalIssueListData {
    data.provider_id = provider_id.to_string();
    data
}

fn with_issue_operation_provider(
    mut data: LocalIssueOperationData,
    provider_id: &str,
) -> LocalIssueOperationData {
    data.provider_id = provider_id.to_string();
    data
}
