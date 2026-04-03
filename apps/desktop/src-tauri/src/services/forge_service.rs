use std::process::Command;

use crate::errors::AppError;
use crate::models::git::{
    ForgeAdapter, ForgeAdapterList, RemoteIntegrationData, RepositoryIntegrationMatrix,
};
use crate::services::git_provider;

fn local_core_adapter() -> ForgeAdapter {
    ForgeAdapter {
        id: "local-core".to_string(),
        available: true,
        version: Some("built-in".to_string()),
    }
}

fn detect_gh() -> ForgeAdapter {
    match Command::new("gh").arg("--version").output() {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let first_line = stdout.lines().next().map(|line| line.to_string());
            ForgeAdapter {
                id: "github-gh".to_string(),
                available: true,
                version: first_line,
            }
        }
        _ => ForgeAdapter {
            id: "github-gh".to_string(),
            available: false,
            version: None,
        },
    }
}

pub fn list_forge_adapters() -> Result<ForgeAdapterList, AppError> {
    let github = detect_gh();
    Ok(ForgeAdapterList {
        adapters: vec![local_core_adapter(), github],
    })
}

pub fn get_repository_integration_matrix(
    repository_path: &str,
) -> Result<RepositoryIntegrationMatrix, AppError> {
    let remote_output = git_provider::run_git(Some(repository_path), &["remote", "-v"])?;
    let github_adapter = detect_gh();
    let mut remotes = Vec::<RemoteIntegrationData>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    for line in remote_output.stdout.lines() {
        if !line.contains("(fetch)") {
            continue;
        }

        let mut fields = line.split_whitespace();
        let remote = fields.next().unwrap_or_default().trim().to_string();
        let url = fields.next().unwrap_or_default().trim().to_string();
        if remote.is_empty() || url.is_empty() {
            continue;
        }

        if !seen.insert(remote.clone()) {
            continue;
        }

        let host_kind = detect_host_kind(&url);
        let (adapter_id, adapter_available) = match host_kind.as_str() {
            "github" => (Some("github-gh".to_string()), github_adapter.available),
            _ => (None, false),
        };

        let mut capability_summary = vec!["core.git.fetch-pull-push".to_string()];
        let offline_supported = matches!(host_kind.as_str(), "local" | "github");
        if offline_supported {
            capability_summary.push("local.offline-ready".to_string());
        }
        if host_kind == "github" {
            capability_summary.push("github.remote.detected".to_string());
            capability_summary.push("github.issues.local-mirror".to_string());
            capability_summary.push("github.pull-requests.local-mirror".to_string());
            if github_adapter.available {
                capability_summary.push("github.optional-adapter.available".to_string());
            } else {
                capability_summary.push("github.optional-adapter.unavailable.local-mirror-active".to_string());
            }
        }

        remotes.push(RemoteIntegrationData {
            remote,
            url,
            host_kind,
            adapter_id,
            adapter_available,
            offline_supported,
            capability_summary,
        });
    }

    Ok(RepositoryIntegrationMatrix {
        repository_path: repository_path.to_string(),
        offline_ready: true,
        local_features: vec![
            "core.git.read-write".to_string(),
            "local.issues.offline".to_string(),
            "local.pull-requests.offline".to_string(),
            "github.issues.local-mirror".to_string(),
            "github.pull-requests.local-mirror".to_string(),
            "local.telemetry.only".to_string(),
        ],
        remotes,
    })
}

fn detect_host_kind(url: &str) -> String {
    let normalized = url.to_ascii_lowercase();
    if normalized.contains("github.com") {
        return "github".to_string();
    }
    if normalized.starts_with("file://")
        || normalized.starts_with("/")
        || normalized.starts_with("./")
        || normalized.starts_with("../")
        || normalized.contains(":\\")
    {
        return "local".to_string();
    }
    "generic".to_string()
}
