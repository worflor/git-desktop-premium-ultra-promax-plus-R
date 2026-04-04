use std::env;
use std::path::Path;

use crate::errors::AppError;
use crate::models::git::{AuthStatus, RemoteAuthDiagnostic};
use crate::services::{forge_service, git_provider, remote_topology_service};

pub fn get_auth_status(repository_path: Option<&str>) -> Result<AuthStatus, AppError> {
    let mut diagnostics = Vec::new();

    let github_cli_status = forge_service::get_github_cli_auth_status();

    let ssh_agent_available =
        env::var("SSH_AUTH_SOCK").is_ok() || env::var("SSH_AGENT_PID").is_ok();
    if ssh_agent_available {
        diagnostics.push("ssh-agent environment appears available".to_string());
    } else {
        diagnostics.push("ssh-agent environment variables are not set".to_string());
    }

    if github_cli_status.available {
        diagnostics.push(format!(
            "github-cli detected: {}",
            github_cli_status.message
        ));
    } else {
        diagnostics.push(
            "github-cli is unavailable; GitHub adapter enhancements are disabled".to_string(),
        );
    }

    let credential_helper_configured =
        match git_provider::run_git(None, &["config", "--global", "credential.helper"]) {
            Ok(output) => {
                let has_helper = !output.stdout.trim().is_empty();
                if has_helper {
                    diagnostics.push("global git credential helper is configured".to_string());
                } else {
                    diagnostics.push("global git credential helper is not configured".to_string());
                }
                has_helper
            }
            Err(_) => {
                diagnostics
                    .push("unable to read global git credential helper configuration".to_string());
                false
            }
        };

    let mut remote_diagnostics = Vec::new();
    if let Some(path) = repository_path.filter(|value| !value.trim().is_empty()) {
        if !Path::new(path).exists() {
            return Err(AppError::RepositoryPathMissing);
        }

        if let Ok(remotes) = remote_topology_service::list_repository_remotes(path) {
            for remote_entry in remotes {
                let remote = remote_entry.remote;
                let url = remote_entry.url;
                let protocol = remote_entry.protocol;
                let host_kind = remote_entry.host_kind;
                let guidance = match protocol.as_str() {
                    "ssh" if !ssh_agent_available => {
                        "SSH remote detected but ssh-agent is not available. Start ssh-agent and load your key.".to_string()
                    }
                    "https" if !credential_helper_configured => {
                        "HTTPS remote detected without a configured credential helper. Configure one to avoid repeated auth prompts.".to_string()
                    }
                    _ if host_kind == "github"
                        && github_cli_status.available
                        && !github_cli_status.authenticated =>
                    {
                        "GitHub remote detected and gh CLI is installed but not authenticated. Run 'gh auth login' for optional adapter features."
                            .to_string()
                    }
                    "ssh" => "SSH remote looks ready with current environment diagnostics.".to_string(),
                    "https" => "HTTPS remote looks ready with credential helper configured.".to_string(),
                    _ => "Remote protocol is non-standard; verify credentials and transport manually.".to_string(),
                };

                remote_diagnostics.push(RemoteAuthDiagnostic {
                    remote,
                    url,
                    protocol,
                    guidance,
                });
            }
        }
    }

    Ok(AuthStatus {
        ssh_agent_available,
        credential_helper_configured,
        github_cli_available: github_cli_status.available,
        github_cli_authenticated: github_cli_status.authenticated,
        diagnostics,
        remote_diagnostics,
    })
}
