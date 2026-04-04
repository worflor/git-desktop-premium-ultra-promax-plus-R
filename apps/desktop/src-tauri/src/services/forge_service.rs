use std::process::Command;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::git::{
    ForgeAdapter, ForgeAdapterList, RemoteIntegrationData, RepositoryIntegrationMatrix,
};
use crate::services::{forge_remote_service, remote_topology_service};

const ADAPTER_ID_LOCAL_CORE: &str = "local-core";
const ADAPTER_ID_GITHUB_GH: &str = "github-gh";
const ADAPTER_ID_GITLAB_CONTRACT: &str = forge_remote_service::GITLAB_PROVIDER_ID;
const ADAPTER_ID_BITBUCKET_CONTRACT: &str = forge_remote_service::BITBUCKET_PROVIDER_ID;

#[derive(Debug, Clone)]
pub struct GithubCliAuthStatus {
    pub available: bool,
    pub authenticated: bool,
    pub version: Option<String>,
    pub message: String,
}

#[derive(Debug, Clone)]
struct GithubCliAuthStatusCacheEntry {
    checked_at: Instant,
    status: GithubCliAuthStatus,
}

const GITHUB_CLI_AUTH_CACHE_TTL: Duration = Duration::from_secs(30);

fn local_core_adapter() -> ForgeAdapter {
    ForgeAdapter {
        id: ADAPTER_ID_LOCAL_CORE.to_string(),
        available: true,
        version: Some("built-in".to_string()),
        auth_state: Some("n/a".to_string()),
        auth_message: Some("local-core adapter does not require external login".to_string()),
    }
}

fn detect_gh() -> ForgeAdapter {
    let status = get_github_cli_auth_status();
    ForgeAdapter {
        id: ADAPTER_ID_GITHUB_GH.to_string(),
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

fn remote_api_adapter(id: &str, status: forge_remote_service::AdapterStatus, version: &str) -> ForgeAdapter {
    ForgeAdapter {
        id: id.to_string(),
        available: status.available,
        version: Some(version.to_string()),
        auth_state: Some(status.auth_state),
        auth_message: Some(status.guidance),
    }
}

fn detect_gitlab_adapter() -> ForgeAdapter {
    remote_api_adapter(
        ADAPTER_ID_GITLAB_CONTRACT,
        forge_remote_service::gitlab_adapter_status(),
        "api-v4",
    )
}

fn detect_bitbucket_adapter() -> ForgeAdapter {
    remote_api_adapter(
        ADAPTER_ID_BITBUCKET_CONTRACT,
        forge_remote_service::bitbucket_adapter_status(),
        "api-v2",
    )
}

pub fn get_github_cli_auth_status() -> GithubCliAuthStatus {
    if let Ok(cache) = github_cli_auth_status_cache().lock() {
        if let Some(entry) = cache.as_ref() {
            if entry.checked_at.elapsed() <= GITHUB_CLI_AUTH_CACHE_TTL {
                return entry.status.clone();
            }
        }
    }

    let version_output = Command::new("gh").arg("--version").output();
    let status = if let Ok(version_output) = version_output {
        if !version_output.status.success() {
            GithubCliAuthStatus {
                available: false,
                authenticated: false,
                version: None,
                message: "GitHub CLI did not report a healthy version response.".to_string(),
            }
        } else {
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
    } else {
        GithubCliAuthStatus {
            available: false,
            authenticated: false,
            version: None,
            message: "GitHub CLI is not installed or unavailable on PATH.".to_string(),
        }
    };

    if let Ok(mut cache) = github_cli_auth_status_cache().lock() {
        *cache = Some(GithubCliAuthStatusCacheEntry {
            checked_at: Instant::now(),
            status: status.clone(),
        });
    }

    status
}

fn github_cli_auth_status_cache() -> &'static Mutex<Option<GithubCliAuthStatusCacheEntry>> {
    static CACHE: OnceLock<Mutex<Option<GithubCliAuthStatusCacheEntry>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

pub fn list_forge_adapters() -> Result<ForgeAdapterList, AppError> {
    let github = detect_gh();
    Ok(ForgeAdapterList {
        adapters: vec![
            local_core_adapter(),
            github,
            detect_gitlab_adapter(),
            detect_bitbucket_adapter(),
        ],
    })
}

pub fn get_repository_integration_matrix(
    repository_path: &str,
) -> Result<RepositoryIntegrationMatrix, AppError> {
    let repository_remotes = remote_topology_service::list_repository_remotes(repository_path)?;
    let github_adapter = detect_gh();
    let github_auth = get_github_cli_auth_status();
    let gitlab_adapter = detect_gitlab_adapter();
    let bitbucket_adapter = detect_bitbucket_adapter();
    let mut remotes = Vec::<RemoteIntegrationData>::new();

    for remote_entry in repository_remotes {
        let remote = remote_entry.remote;
        let url = remote_entry.url;
        let host_kind = remote_entry.host_kind;
        let (adapter_id, adapter_available) = match host_kind.as_str() {
            "github" => (
                Some(ADAPTER_ID_GITHUB_GH.to_string()),
                github_adapter.available,
            ),
            "gitlab" => (
                Some(ADAPTER_ID_GITLAB_CONTRACT.to_string()),
                gitlab_adapter.available,
            ),
            "bitbucket" => (
                Some(ADAPTER_ID_BITBUCKET_CONTRACT.to_string()),
                bitbucket_adapter.available,
            ),
            _ => (None, false),
        };

        let mut capability_summary = vec!["core.git.fetch-pull-push".to_string()];
        let offline_supported = matches!(
            host_kind.as_str(),
            "local" | "github" | "gitlab" | "bitbucket"
        );
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
        if host_kind == "gitlab" {
            capability_summary.push("gitlab.remote.detected".to_string());
            capability_summary.push("gitlab.issues.remote-api".to_string());
            capability_summary.push("gitlab.merge-requests.remote-api".to_string());
            if gitlab_adapter.available {
                capability_summary.push("gitlab.optional-adapter.available".to_string());
                capability_summary.push("gitlab.optional-adapter.authenticated".to_string());
            } else {
                capability_summary.push("gitlab.optional-adapter.unauthenticated".to_string());
            }
        }
        if host_kind == "bitbucket" {
            capability_summary.push("bitbucket.remote.detected".to_string());
            capability_summary.push("bitbucket.issues.remote-api".to_string());
            capability_summary.push("bitbucket.pull-requests.remote-api".to_string());
            if bitbucket_adapter.available {
                capability_summary.push("bitbucket.optional-adapter.available".to_string());
                capability_summary.push("bitbucket.optional-adapter.authenticated".to_string());
            } else {
                capability_summary.push("bitbucket.optional-adapter.unauthenticated".to_string());
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
            "gitlab.issues.remote-api".to_string(),
            "gitlab.merge-requests.remote-api".to_string(),
            "bitbucket.issues.remote-api".to_string(),
            "bitbucket.pull-requests.remote-api".to_string(),
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

#[cfg(test)]
fn detect_host_kind(url: &str) -> String {
    remote_topology_service::detect_host_kind_from_url(url).to_string()
}

#[cfg(test)]
mod tests {
    use super::{
        detect_host_kind, first_non_empty_line, list_forge_adapters, ADAPTER_ID_BITBUCKET_CONTRACT,
        ADAPTER_ID_GITLAB_CONTRACT,
    };

    #[test]
    fn detect_host_kind_classifies_supported_hosts() {
        assert_eq!(detect_host_kind("git@github.com:owner/repo.git"), "github");
        assert_eq!(
            detect_host_kind("https://gitlab.com/group/project.git"),
            "gitlab"
        );
        assert_eq!(
            detect_host_kind("ssh://git@bitbucket.org/team/repo.git"),
            "bitbucket"
        );
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

        assert!(adapters
            .adapters
            .iter()
            .any(|adapter| adapter.id == ADAPTER_ID_GITLAB_CONTRACT));
        assert!(adapters
            .adapters
            .iter()
            .any(|adapter| adapter.id == ADAPTER_ID_BITBUCKET_CONTRACT));
    }
}
