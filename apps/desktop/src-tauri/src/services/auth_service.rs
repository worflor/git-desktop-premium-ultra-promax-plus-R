use std::env;
use std::path::Path;

use crate::errors::AppError;
use crate::models::git::{AuthStatus, RemoteAuthDiagnostic};
use crate::services::git_provider;

pub fn get_auth_status(repository_path: Option<&str>) -> Result<AuthStatus, AppError> {
    let mut diagnostics = Vec::new();

    let ssh_agent_available = env::var("SSH_AUTH_SOCK").is_ok() || env::var("SSH_AGENT_PID").is_ok();
    if ssh_agent_available {
        diagnostics.push("ssh-agent environment appears available".to_string());
    } else {
        diagnostics.push("ssh-agent environment variables are not set".to_string());
    }

    let credential_helper_configured = match git_provider::run_git(None, &["config", "--global", "credential.helper"]) {
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
            diagnostics.push("unable to read global git credential helper configuration".to_string());
            false
        }
    };

    let mut remote_diagnostics = Vec::new();
    if let Some(path) = repository_path.filter(|value| !value.trim().is_empty()) {
        if !Path::new(path).exists() {
            return Err(AppError::RepositoryPathMissing);
        }

        if let Ok(output) = git_provider::run_git(Some(path), &["remote", "-v"]) {
            for line in output.stdout.lines() {
                if !line.contains("(fetch)") {
                    continue;
                }

                let mut parts = line.split_whitespace();
                let remote = parts.next().unwrap_or("unknown").to_string();
                let url = parts.next().unwrap_or("").to_string();
                if url.is_empty() {
                    continue;
                }

                let protocol = detect_protocol(&url);
                let guidance = match protocol.as_str() {
                    "ssh" if !ssh_agent_available => {
                        "SSH remote detected but ssh-agent is not available. Start ssh-agent and load your key.".to_string()
                    }
                    "https" if !credential_helper_configured => {
                        "HTTPS remote detected without a configured credential helper. Configure one to avoid repeated auth prompts.".to_string()
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
        diagnostics,
        remote_diagnostics,
    })
}

fn detect_protocol(url: &str) -> String {
    if url.starts_with("git@") || url.starts_with("ssh://") {
        return "ssh".to_string();
    }
    if url.starts_with("https://") || url.starts_with("http://") {
        return "https".to_string();
    }
    "other".to_string()
}
