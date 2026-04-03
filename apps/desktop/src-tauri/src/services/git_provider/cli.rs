use std::process::Command;
use std::time::Instant;

use crate::errors::AppError;
use crate::services::telemetry_service;

pub struct GitCommandOutput {
    pub stdout: String,
}

pub fn run_git(repository_path: Option<&str>, args: &[&str]) -> Result<GitCommandOutput, AppError> {
    let started_at = Instant::now();
    let command_label = classify_git_command(args);

    let mut command = Command::new("git");
    command.args(args);

    if let Some(path) = repository_path {
        command.current_dir(path);
    }

    let output = match command.output() {
        Ok(output) => output,
        Err(error) => {
            let app_error = match error.kind() {
                std::io::ErrorKind::NotFound => AppError::GitUnavailable,
                _ => AppError::CommandExecution(error.to_string()),
            };

            let error_code = app_error.to_command_error().code;
            record_git_telemetry(
                command_label.as_str(),
                started_at.elapsed().as_millis() as u64,
                false,
                Some(error_code.as_str()),
            );

            return Err(app_error);
        }
    };

    let duration_ms = started_at.elapsed().as_millis() as u64;

    if !output.status.success() {
        let app_error = AppError::GitCommand(String::from_utf8_lossy(&output.stderr).trim().to_string());
        let error_code = app_error.to_command_error().code;
        record_git_telemetry(
            command_label.as_str(),
            duration_ms,
            false,
            Some(error_code.as_str()),
        );
        return Err(app_error);
    }

    record_git_telemetry(command_label.as_str(), duration_ms, true, None);

    Ok(GitCommandOutput {
        stdout: String::from_utf8_lossy(&output.stdout).trim().to_string(),
    })
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

fn record_git_telemetry(command: &str, duration_ms: u64, ok: bool, error_code: Option<&str>) {
    let _ = telemetry_service::record_command_sample("git", command, ok, duration_ms, error_code);
}
