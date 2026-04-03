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
    #[error("git authentication is required: {0}")]
    AuthRequired(String),
    #[error("credential helper is unavailable")]
    AuthHelperUnavailable,
    #[error("forge adapter is unavailable: {0}")]
    ForgeAdapterUnavailable(String),
    #[error("diff payload is too large: {bytes} bytes exceeds {max_bytes} bytes")]
    DiffTooLarge { bytes: u64, max_bytes: u64 },
    #[error("ai provider is unavailable: {0}")]
    AiProviderUnavailable(String),
    #[error("ai process failed: {0}")]
    AiProcessFailed(String),
    #[error("ai guardrail blocked operation: {0}")]
    AiGuardrailViolation(String),
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
            AppError::AuthRequired(_) => "git.auth_required",
            AppError::AuthHelperUnavailable => "auth.helper_unavailable",
            AppError::ForgeAdapterUnavailable(_) => "forge.adapter_unavailable",
            AppError::DiffTooLarge { .. } => "diff.too_large",
            AppError::AiProviderUnavailable(_) => "ai.provider_unavailable",
            AppError::AiProcessFailed(_) => "ai.process_failed",
            AppError::AiGuardrailViolation(_) => "ai.guardrail_blocked",
        };

        CommandError {
            code: code.to_string(),
            message: self.to_string(),
            details: None,
            retryable: matches!(
                self,
                AppError::CommandExecution(_)
                    | AppError::Internal(_)
                    | AppError::AuthRequired(_)
                    | AppError::AiProcessFailed(_)
            ),
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
        let command_error =
            AppError::GitCommand("CONFLICT (add/add)".to_string()).to_command_error();
        assert_eq!(command_error.code, "git.conflict_detected");
    }

    #[test]
    fn command_error_uses_contract_ai_provider_code() {
        let command_error = AppError::AiProviderUnavailable("codex".to_string()).to_command_error();
        assert_eq!(command_error.code, "ai.provider_unavailable");
    }

    #[test]
    fn command_error_uses_contract_ai_guardrail_code() {
        let command_error =
            AppError::AiGuardrailViolation("read-only policy".to_string()).to_command_error();
        assert_eq!(command_error.code, "ai.guardrail_blocked");
    }
}
