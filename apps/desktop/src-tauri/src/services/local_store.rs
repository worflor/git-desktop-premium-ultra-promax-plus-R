use std::path::{Path, PathBuf};

use chrono::{DateTime, SecondsFormat, TimeZone, Utc};

use crate::errors::AppError;
use crate::services::git_provider;

const GDPU_STORE_DIR: &str = "gdpu";

pub fn ensure_git_repository(repository_path: &str) -> Result<PathBuf, AppError> {
    let path = Path::new(repository_path);
    if !path.exists() {
        return Err(AppError::RepositoryPathMissing);
    }

    let dot_git = path.join(".git");
    if !dot_git.exists() {
        return Err(AppError::NotAGitRepository);
    }

    Ok(path.to_path_buf())
}

pub fn gdpu_store_file_path(repository_path: &str, file_name: &str) -> Result<PathBuf, AppError> {
    if file_name.trim().is_empty() {
        return Err(AppError::Internal(
            "local store file name is required".to_string(),
        ));
    }

    let _ = ensure_git_repository(repository_path)?;
    let git_dir = resolve_git_dir_path(repository_path)?;
    Ok(git_dir.join(GDPU_STORE_DIR).join(file_name))
}

pub fn now_iso8601_string() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}

pub fn normalize_timestamp(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return now_iso8601_string();
    }

    if let Ok(epoch_seconds) = trimmed.parse::<i64>() {
        if let Some(timestamp) = Utc.timestamp_opt(epoch_seconds, 0).single() {
            return timestamp.to_rfc3339_opts(SecondsFormat::Secs, true);
        }
    }

    if let Ok(timestamp) = DateTime::parse_from_rfc3339(trimmed) {
        return timestamp
            .with_timezone(&Utc)
            .to_rfc3339_opts(SecondsFormat::Secs, true);
    }

    trimmed.to_string()
}

fn resolve_git_dir_path(repository_path: &str) -> Result<PathBuf, AppError> {
    let output =
        git_provider::run_git(Some(repository_path), &["rev-parse", "--absolute-git-dir"])?;
    let git_dir = output.stdout.trim();
    if git_dir.is_empty() {
        return Err(AppError::Internal(
            "failed to resolve absolute git directory for local metadata store".to_string(),
        ));
    }

    Ok(PathBuf::from(git_dir))
}

#[cfg(test)]
mod tests {
    use super::normalize_timestamp;

    #[test]
    fn normalizes_epoch_seconds_to_iso8601() {
        let normalized = normalize_timestamp("1713000000");
        assert_eq!(normalized, "2024-04-13T09:20:00Z");
    }

    #[test]
    fn normalizes_rfc3339_to_canonical_utc() {
        let normalized = normalize_timestamp("2026-01-01T00:00:00+02:00");
        assert_eq!(normalized, "2025-12-31T22:00:00Z");
    }

    #[test]
    fn preserves_unknown_timestamp_text() {
        let normalized = normalize_timestamp("not-a-timestamp");
        assert_eq!(normalized, "not-a-timestamp");
    }
}
