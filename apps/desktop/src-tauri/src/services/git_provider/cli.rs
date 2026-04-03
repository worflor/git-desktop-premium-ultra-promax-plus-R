use std::process::Command;

use crate::errors::AppError;

pub struct GitCommandOutput {
    pub stdout: String,
}

pub fn run_git(repository_path: Option<&str>, args: &[&str]) -> Result<GitCommandOutput, AppError> {
    let mut command = Command::new("git");
    command.args(args);

    if let Some(path) = repository_path {
        command.current_dir(path);
    }

    let output = command
        .output()
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::NotFound => AppError::GitUnavailable,
            _ => AppError::CommandExecution(error.to_string()),
        })?;

    if !output.status.success() {
        return Err(AppError::GitCommand(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }

    Ok(GitCommandOutput {
        stdout: String::from_utf8_lossy(&output.stdout).trim().to_string(),
    })
}
