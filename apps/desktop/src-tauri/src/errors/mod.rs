use thiserror::Error;

use crate::models::contract::CommandError;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("repository path does not exist")]
    RepositoryPathMissing,
    #[error("repository path is not a git repository")]
    NotAGitRepository,
    #[error("git executable is not available")]
    GitUnavailable,
    #[error("command execution failed: {0}")]
    CommandExecution(String),
    #[error("git command failed: {0}")]
    GitCommand(String),
    #[error("internal error: {0}")]
    Internal(String),
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("unsupported git version: found {found}, requires {minimum}+")]
    UnsupportedGitVersion { found: String, minimum: String },
}

impl AppError {
    pub fn to_command_error(&self) -> CommandError {
        let code = match self {
            AppError::RepositoryPathMissing => "repo.not_found",
            AppError::NotAGitRepository => "repo.open_failed",
            AppError::GitUnavailable => "git.not_installed",
            AppError::CommandExecution(_) => "runtime.exec_failed",
            AppError::GitCommand(message) => git_command_error_code(message),
            AppError::Internal(_) => "runtime.internal_error",
            AppError::InvalidInput(_) => "validation.invalid_input",
            AppError::UnsupportedGitVersion { .. } => "git.unsupported_version",
        };

        CommandError {
            code: code.to_string(),
            message: self.to_string(),
            details: None,
            retryable: matches!(self, AppError::CommandExecution(_) | AppError::Internal(_)),
        }
    }
}

fn git_command_error_code(message: &str) -> &'static str {
    let normalized = message.to_ascii_lowercase();
    if normalized.contains("conflict") || normalized.contains("could not apply") {
        return "git.conflict_detected";
    }

    "git.command_failed"
}

#[cfg(test)]
mod tests {
    use super::{git_command_error_code, AppError};

    #[test]
    fn maps_conflict_messages_to_conflict_code() {
        assert_eq!(
            git_command_error_code("CONFLICT (content): Merge conflict in src/app.ts"),
            "git.conflict_detected"
        );
        assert_eq!(
            git_command_error_code("error: could not apply 1234567"),
            "git.conflict_detected"
        );
    }

    #[test]
    fn maps_non_conflict_git_messages_to_generic_code() {
        assert_eq!(
            git_command_error_code("fatal: not a git repository"),
            "git.command_failed"
        );
    }

    #[test]
    fn command_error_uses_conflict_code_for_git_conflicts() {
        let command_error = AppError::GitCommand("CONFLICT (add/add)".to_string()).to_command_error();
        assert_eq!(command_error.code, "git.conflict_detected");
    }
}

