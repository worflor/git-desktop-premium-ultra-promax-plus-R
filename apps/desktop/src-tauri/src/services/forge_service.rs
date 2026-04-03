use std::process::Command;

use crate::errors::AppError;
use crate::models::git::{
    ForgeAdapter, ForgeAdapterList, RemoteIntegrationData, RepositoryIntegrationMatrix,
};
use crate::services::git_provider;

pub struct GithubCliAuthStatus {
    pub available: bool,
    pub authenticated: bool,
    pub version: Option<String>,
    pub message: String,
}

fn local_core_adapter() -> ForgeAdapter {
    ForgeAdapter {
        id: "local-core".to_string(),
        available: true,
        version: Some("built-in".to_string()),
        auth_state: Some("n/a".to_string()),
        auth_message: Some("local-core adapter does not require external login".to_string()),
    }
}

fn detect_gh() -> ForgeAdapter {
    let status = get_github_cli_auth_status();
    ForgeAdapter {
        id: "github-gh".to_string(),
        available: status.available,
        version: status.version,
        auth_state: Some(if status.authenticated {
            "authenticated".to_string()
        } else if status.available {
            "unauthenticated".to_string()
        } else {
            "unavailable".to_string()
        }),
        auth_message: Some(status.message),
    }
}

pub fn get_github_cli_auth_status() -> GithubCliAuthStatus {
    let version_output = Command::new("gh").arg("--version").output();
    let Ok(version_output) = version_output else {
        return GithubCliAuthStatus {
            available: false,
            authenticated: false,
            version: None,
            message: "GitHub CLI is not installed or unavailable on PATH.".to_string(),
        };
    };

    if !version_output.status.success() {
        return GithubCliAuthStatus {
            available: false,
            authenticated: false,
            version: None,
            message: "GitHub CLI did not report a healthy version response.".to_string(),
        };
    }

    let version = String::from_utf8_lossy(&version_output.stdout)
        .lines()
        .next()
        .map(|line| line.trim().to_string())
        .filter(|line| !line.is_empty());

    let auth_output = Command::new("gh")
        .args(["auth", "status", "--hostname", "github.com"])
        .output();

    match auth_output {
        Ok(output) if output.status.success() => {
            let message = first_non_empty_line(&output.stdout, &output.stderr)
                .unwrap_or_else(|| "GitHub CLI is authenticated for github.com.".to_string());
            GithubCliAuthStatus {
                available: true,
                authenticated: true,
                version,
                message,
            }
        }
        Ok(output) => {
            let message =
                first_non_empty_line(&output.stderr, &output.stdout).unwrap_or_else(|| {
                    "GitHub CLI is installed but not authenticated for github.com.".to_string()
                });
            GithubCliAuthStatus {
                available: true,
                authenticated: false,
                version,
                message,
            }
        }
        Err(error) => GithubCliAuthStatus {
            available: true,
            authenticated: false,
            version,
            message: format!("GitHub CLI auth status probe failed: {error}"),
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
    let github_auth = get_github_cli_auth_status();
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
                capability_summary.push(if github_auth.authenticated {
                    "github.optional-adapter.authenticated".to_string()
                } else {
                    "github.optional-adapter.unauthenticated".to_string()
                });
            } else {
                capability_summary
                    .push("github.optional-adapter.unavailable.local-mirror-active".to_string());
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

fn first_non_empty_line(primary: &[u8], secondary: &[u8]) -> Option<String> {
    for payload in [primary, secondary] {
        for line in String::from_utf8_lossy(payload).lines() {
            let trimmed = line.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }

    None
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

#[cfg(test)]
mod tests {
    use super::{detect_host_kind, first_non_empty_line, list_forge_adapters};

    #[test]
    fn detect_host_kind_classifies_github_and_local_paths() {
        assert_eq!(detect_host_kind("git@github.com:owner/repo.git"), "github");
        assert_eq!(detect_host_kind("file:///tmp/repo"), "local");
        assert_eq!(detect_host_kind("../relative/repo"), "local");
        assert_eq!(detect_host_kind("ssh://example.com/repo.git"), "generic");
    }

    #[test]
    fn first_non_empty_line_prefers_primary_then_secondary() {
        let value = first_non_empty_line(b"\n\nprimary\n", b"secondary\n");
        assert_eq!(value.as_deref(), Some("primary"));

        let fallback = first_non_empty_line(b"\n", b"secondary\n");
        assert_eq!(fallback.as_deref(), Some("secondary"));
    }

    #[test]
    fn list_forge_adapters_includes_local_core_contract() {
        let adapters = list_forge_adapters().expect("listing forge adapters should succeed");
        let local_core = adapters
            .adapters
            .iter()
            .find(|adapter| adapter.id == "local-core")
            .expect("local-core adapter should always be present");

        assert!(local_core.available);
        assert_eq!(local_core.version.as_deref(), Some("built-in"));
    }
}
