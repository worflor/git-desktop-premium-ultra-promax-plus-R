use std::process::Command;
use std::thread;
use std::time::Duration;
use std::time::Instant;
use uuid::Uuid;

use crate::errors::AppError;
use crate::services::{logging_service, telemetry_service};

const MAX_TRANSIENT_RETRIES: u32 = 2;
const RETRY_BACKOFF_MS: [u64; 2] = [200, 500];

pub struct GitCommandOutput {
    pub stdout: String,
}

pub fn run_git(repository_path: Option<&str>, args: &[&str]) -> Result<GitCommandOutput, AppError> {
    let started_at = Instant::now();
    let command_label = classify_git_command(args);

    let request_id =
        logging_service::current_request_context().unwrap_or_else(|| Uuid::new_v4().to_string());

    logging_service::with_request_context(request_id.as_str(), || {
        let mut attempt = 1_u32;
        loop {
            match execute_git_command(repository_path, args) {
                Ok(output) if output.status.success() => {
                    record_git_telemetry(
                        command_label.as_str(),
                        started_at.elapsed().as_millis() as u64,
                        true,
                        None,
                    );
                    let success_message = if attempt > 1 {
                        Some(format!("completed after {attempt} attempts"))
                    } else {
                        None
                    };
                    let _ = logging_service::record_operation_span(
                        "git",
                        command_label.as_str(),
                        Some(request_id.as_str()),
                        started_at,
                        true,
                        None,
                        success_message.as_deref(),
                    );

                    return Ok(GitCommandOutput {
                        stdout: String::from_utf8_lossy(&output.stdout).trim().to_string(),
                    });
                }
                Ok(output) => {
                    let app_error = map_git_failure(String::from_utf8_lossy(&output.stderr).trim());
                    if should_retry_transient_failure(&app_error, args, attempt) {
                        let error_code = app_error.to_command_error().code;
                        let _ = logging_service::record_retry_event(
                            "git",
                            command_label.as_str(),
                            Some(request_id.as_str()),
                            attempt + 1,
                            Some(error_code.as_str()),
                            "transient git network failure detected; retrying",
                        );
                        sleep_retry_backoff(attempt);
                        attempt += 1;
                        continue;
                    }

                    let error_code = app_error.to_command_error().code;
                    record_git_telemetry(
                        command_label.as_str(),
                        started_at.elapsed().as_millis() as u64,
                        false,
                        Some(error_code.as_str()),
                    );
                    let _ = logging_service::record_operation_span(
                        "git",
                        command_label.as_str(),
                        Some(request_id.as_str()),
                        started_at,
                        false,
                        Some(error_code.as_str()),
                        Some(app_error.to_string().as_str()),
                    );

                    return Err(app_error);
                }
                Err(error) => {
                    let app_error = match error.kind() {
                        std::io::ErrorKind::NotFound => AppError::GitUnavailable,
                        _ => AppError::CommandExecution(error.to_string()),
                    };

                    if should_retry_transient_failure(&app_error, args, attempt) {
                        let error_code = app_error.to_command_error().code;
                        let _ = logging_service::record_retry_event(
                            "git",
                            command_label.as_str(),
                            Some(request_id.as_str()),
                            attempt + 1,
                            Some(error_code.as_str()),
                            "transient git execution failure detected; retrying",
                        );
                        sleep_retry_backoff(attempt);
                        attempt += 1;
                        continue;
                    }

                    let error_code = app_error.to_command_error().code;
                    record_git_telemetry(
                        command_label.as_str(),
                        started_at.elapsed().as_millis() as u64,
                        false,
                        Some(error_code.as_str()),
                    );
                    let _ = logging_service::record_operation_span(
                        "git",
                        command_label.as_str(),
                        Some(request_id.as_str()),
                        started_at,
                        false,
                        Some(error_code.as_str()),
                        Some(app_error.to_string().as_str()),
                    );

                    return Err(app_error);
                }
            }
        }
    })
}

fn execute_git_command(
    repository_path: Option<&str>,
    args: &[&str],
) -> std::io::Result<std::process::Output> {
    let mut command = Command::new("git");
    command.args(args);

    if let Some(path) = repository_path {
        command.current_dir(path);
    }

    command.output()
}

fn classify_git_command(args: &[&str]) -> String {
    let first = args
        .iter()
        .map(|value| value.trim())
        .find(|value| !value.is_empty());

    match first {
        Some(value) if value.starts_with('-') => "git.meta".to_string(),
        Some(value) => format!("git.{}", value.to_ascii_lowercase()),
        None => "git.unknown".to_string(),
    }
}

fn map_git_failure(stderr: &str) -> AppError {
    let message = if stderr.trim().is_empty() {
        "git command failed".to_string()
    } else {
        stderr.trim().to_string()
    };

    let normalized = message.to_ascii_lowercase();
    if (normalized.contains("credential")
        && normalized.contains("helper")
        && (normalized.contains("not found")
            || normalized.contains("unavailable")
            || normalized.contains("cannot run")
            || normalized.contains("no such file")))
        || normalized.contains("fatal: could not read username")
    {
        return AppError::AuthHelperUnavailable;
    }

    if normalized.contains("authentication failed")
        || normalized.contains("auth failed")
        || normalized.contains("permission denied")
        || normalized.contains("access denied")
        || normalized.contains("authorization failed")
        || normalized.contains("could not read username")
        || normalized.contains("could not read password")
        || normalized.contains("repository not found")
    {
        return AppError::AuthRequired(message);
    }

    AppError::GitCommand(message)
}

fn should_retry_transient_failure(error: &AppError, args: &[&str], attempt: u32) -> bool {
    if attempt > MAX_TRANSIENT_RETRIES || !is_retryable_git_command(args) {
        return false;
    }

    match error {
        AppError::GitCommand(message) | AppError::CommandExecution(message) => {
            has_transient_network_hint(message)
        }
        _ => false,
    }
}

fn is_retryable_git_command(args: &[&str]) -> bool {
    let Some(command) = args
        .iter()
        .map(|value| value.trim().to_ascii_lowercase())
        .find(|value| !value.is_empty() && !value.starts_with('-'))
    else {
        return false;
    };

    matches!(
        command.as_str(),
        "fetch" | "pull" | "push" | "ls-remote" | "remote"
    )
}

fn has_transient_network_hint(message: &str) -> bool {
    let normalized = message.to_ascii_lowercase();
    [
        "timed out",
        "timeout",
        "temporary failure",
        "temporarily unavailable",
        "connection reset",
        "connection was reset",
        "network is unreachable",
        "failed to connect",
        "unable to access",
        "could not resolve host",
        "name or service not known",
        "couldn't resolve host",
        "connection refused",
    ]
    .iter()
    .any(|hint| normalized.contains(hint))
}

fn sleep_retry_backoff(attempt: u32) {
    let index = attempt
        .saturating_sub(1)
        .min((RETRY_BACKOFF_MS.len() - 1) as u32) as usize;
    thread::sleep(Duration::from_millis(RETRY_BACKOFF_MS[index]));
}

fn record_git_telemetry(command: &str, duration_ms: u64, ok: bool, error_code: Option<&str>) {
    let _ = telemetry_service::record_command_sample("git", command, ok, duration_ms, error_code);
}

#[cfg(test)]
mod tests {
    use crate::errors::AppError;

    use super::{
        has_transient_network_hint, is_retryable_git_command, should_retry_transient_failure,
    };

    #[test]
    fn retryable_git_command_filter_targets_network_operations() {
        assert!(is_retryable_git_command(&["fetch"]));
        assert!(is_retryable_git_command(&["pull", "origin", "main"]));
        assert!(is_retryable_git_command(&["push", "origin", "main"]));
        assert!(!is_retryable_git_command(&["status"]));
        assert!(!is_retryable_git_command(&["commit", "-m", "x"]));
    }

    #[test]
    fn transient_hint_detection_matches_common_network_failures() {
        assert!(has_transient_network_hint(
            "fatal: unable to access url: Operation timed out"
        ));
        assert!(has_transient_network_hint("connection reset by peer"));
        assert!(!has_transient_network_hint("authentication failed"));
    }

    #[test]
    fn retry_decision_requires_both_command_and_transient_error() {
        let transient = AppError::GitCommand("operation timed out".to_string());
        let permanent = AppError::GitCommand("authentication failed".to_string());

        assert!(should_retry_transient_failure(&transient, &["fetch"], 1));
        assert!(!should_retry_transient_failure(&transient, &["status"], 1));
        assert!(!should_retry_transient_failure(&permanent, &["fetch"], 1));
        assert!(!should_retry_transient_failure(&transient, &["fetch"], 3));
    }
}
