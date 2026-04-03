use std::path::PathBuf;

use crate::errors::AppError;

const APP_DATA_DIR_NAME: &str = "gdpu";

pub fn gdpu_data_dir() -> Result<PathBuf, AppError> {
    if let Some(override_path) = env_non_empty("GDPU_DATA_DIR") {
        return Ok(PathBuf::from(override_path));
    }

    if cfg!(target_os = "windows") {
        if let Some(appdata) = env_non_empty("APPDATA") {
            return Ok(PathBuf::from(appdata).join(APP_DATA_DIR_NAME));
        }

        if let Some(user_profile) = env_non_empty("USERPROFILE") {
            return Ok(PathBuf::from(user_profile)
                .join("AppData")
                .join("Roaming")
                .join(APP_DATA_DIR_NAME));
        }
    }

    if cfg!(target_os = "macos") {
        if let Some(home) = env_non_empty("HOME") {
            return Ok(PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join(APP_DATA_DIR_NAME));
        }
    }

    if let Some(xdg_data_home) = env_non_empty("XDG_DATA_HOME") {
        return Ok(PathBuf::from(xdg_data_home).join(APP_DATA_DIR_NAME));
    }

    if let Some(home) = env_non_empty("HOME") {
        return Ok(PathBuf::from(home)
            .join(".local")
            .join("share")
            .join(APP_DATA_DIR_NAME));
    }

    Err(AppError::Internal(
        "failed to resolve cross-platform app data directory".to_string(),
    ))
}

fn env_non_empty(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}
