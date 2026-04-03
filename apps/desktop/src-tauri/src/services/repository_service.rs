use std::fs;
use std::path::{Path, PathBuf};

use crate::errors::AppError;
use crate::models::repository::OpenRepositoryData;
use crate::runtime::state::AppState;

const RECENTS_FILE_NAME: &str = "recent_repositories.json";

pub fn load_recent_repositories() -> Vec<String> {
    let path = match recents_file_path() {
        Ok(path) => path,
        Err(_) => return Vec::new(),
    };

    let contents = match fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(_) => return Vec::new(),
    };

    serde_json::from_str::<Vec<String>>(&contents).unwrap_or_default()
}

pub fn persist_recent_repositories(items: &[String]) -> Result<(), AppError> {
    let path = recents_file_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| AppError::Internal("recent repository storage path is invalid".to_string()))?;

    fs::create_dir_all(parent).map_err(|error| {
        AppError::Internal(format!("failed to create recent repository storage: {error}"))
    })?;

    let payload = serde_json::to_string_pretty(items)
        .map_err(|error| AppError::Internal(format!("failed to serialize recents: {error}")))?;

    fs::write(path, payload)
        .map_err(|error| AppError::Internal(format!("failed to persist recents: {error}")))
}

fn recents_file_path() -> Result<PathBuf, AppError> {
    let appdata = std::env::var("APPDATA")
        .map_err(|_| AppError::Internal("APPDATA environment variable is unavailable".to_string()))?;
    Ok(PathBuf::from(appdata).join("gdpu").join(RECENTS_FILE_NAME))
}

pub fn open_repository(state: &AppState, repository_path: &str) -> Result<OpenRepositoryData, AppError> {
    let input_path = Path::new(repository_path);

    if !input_path.exists() {
        return Err(AppError::RepositoryPathMissing);
    }

    let normalized_path = fs::canonicalize(input_path)
        .map_err(|error| AppError::Internal(format!("failed to normalize repository path: {error}")))?;
    let normalized_path = normalized_path.to_string_lossy().to_string();

    let path = Path::new(&normalized_path);

    let dot_git = path.join(".git");
    if !dot_git.exists() {
        return Err(AppError::NotAGitRepository);
    }

    {
        let mut recent = state
            .recent_repositories
            .lock()
            .map_err(|_| AppError::Internal("failed to acquire recent repositories lock".to_string()))?;

        if recent.is_empty() {
            *recent = load_recent_repositories();
        }

        if let Some(index) = recent.iter().position(|item| item == &normalized_path) {
            recent.remove(index);
        }

        recent.insert(0, normalized_path.clone());
        if recent.len() > 10 {
            recent.truncate(10);
        }

        persist_recent_repositories(&recent)?;
    }

    Ok(OpenRepositoryData {
        repository_path: normalized_path,
        is_valid_git_repository: true,
    })
}
