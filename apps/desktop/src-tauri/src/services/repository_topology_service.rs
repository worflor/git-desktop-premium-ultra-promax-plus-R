use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::operations::ConflictStateData;
use crate::models::repository::{RepositoryStatusData, RepositoryStatusFile};
use crate::services::{git_provider, remote_topology_service};

const TOPOLOGY_CACHE_TTL: Duration = Duration::from_millis(750);

#[derive(Debug, Clone)]
pub struct RepositoryTopologySnapshot {
    pub head_hash: String,
    pub status: RepositoryStatusData,
    pub conflict_operation: Option<String>,
    pub default_remote: Option<String>,
}

#[derive(Debug, Clone)]
struct RepositoryTopologyCacheEntry {
    captured_at: Instant,
    snapshot: RepositoryTopologySnapshot,
}

pub fn get_repository_status(repository_path: &str) -> Result<RepositoryStatusData, AppError> {
    Ok(get_repository_topology_snapshot(repository_path)?.status)
}

pub fn get_conflict_state(repository_path: &str) -> Result<ConflictStateData, AppError> {
    let snapshot = get_repository_topology_snapshot(repository_path)?;
    let conflicted_files = collect_conflicted_files(&snapshot.status.files);
    let in_conflict = snapshot.conflict_operation.is_some() || !conflicted_files.is_empty();
    let guidance = build_conflict_guidance(snapshot.conflict_operation.as_deref(), in_conflict);

    Ok(ConflictStateData {
        repository_path: repository_path.to_string(),
        in_conflict,
        operation: snapshot.conflict_operation,
        conflicted_files,
        guidance,
    })
}

pub fn get_repository_topology_snapshot(
    repository_path: &str,
) -> Result<RepositoryTopologySnapshot, AppError> {
    if let Ok(cache) = topology_cache().lock() {
        if let Some(entry) = cache.get(repository_path) {
            if entry.captured_at.elapsed() <= TOPOLOGY_CACHE_TTL {
                return Ok(entry.snapshot.clone());
            }
        }
    }

    let status = git_provider::get_repository_status(repository_path)?;
    let head_hash = git_provider::get_head_commit_hash(repository_path)?;
    let conflict_operation = git_provider::get_conflict_operation(repository_path)?;
    let remotes = remote_topology_service::list_repository_remotes(repository_path)?;
    let default_remote = select_default_remote(&remotes);

    let snapshot = RepositoryTopologySnapshot {
        head_hash,
        status,
        conflict_operation,
        default_remote,
    };

    if let Ok(mut cache) = topology_cache().lock() {
        cache.insert(
            repository_path.to_string(),
            RepositoryTopologyCacheEntry {
                captured_at: Instant::now(),
                snapshot: snapshot.clone(),
            },
        );
    }

    Ok(snapshot)
}

pub fn invalidate_repository(repository_path: &str) {
    if let Ok(mut cache) = topology_cache().lock() {
        cache.remove(repository_path);
    }
}

fn collect_conflicted_files(files: &[RepositoryStatusFile]) -> Vec<String> {
    files
        .iter()
        .filter(|file| file.staged == "unmerged" || file.unstaged == "unmerged")
        .map(|file| file.path.clone())
        .collect()
}

fn build_conflict_guidance(operation: Option<&str>, in_conflict: bool) -> Vec<String> {
    if !in_conflict {
        return vec!["No conflicts detected.".to_string()];
    }

    match operation.unwrap_or("merge") {
        "merge" => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git merge --continue.".to_string(),
            "Use Abort to run git merge --abort.".to_string(),
        ],
        "rebase" => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git rebase --continue.".to_string(),
            "Use Abort to run git rebase --abort.".to_string(),
        ],
        "cherry-pick" => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git cherry-pick --continue.".to_string(),
            "Use Abort to run git cherry-pick --abort.".to_string(),
        ],
        "revert" => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git revert --continue.".to_string(),
            "Use Abort to run git revert --abort.".to_string(),
        ],
        _ => vec![
            "Conflicted files were detected, but no active merge/rebase operation was identified."
                .to_string(),
            "Resolve files, stage them, then continue manually with the appropriate git command."
                .to_string(),
        ],
    }
}

fn select_default_remote(remotes: &[remote_topology_service::RepositoryRemote]) -> Option<String> {
    if remotes.is_empty() {
        return None;
    }

    if let Some(origin) = remotes.iter().find(|remote| remote.remote == "origin") {
        return Some(origin.remote.clone());
    }

    Some(remotes[0].remote.clone())
}

fn topology_cache() -> &'static Mutex<HashMap<String, RepositoryTopologyCacheEntry>> {
    static CACHE: OnceLock<Mutex<HashMap<String, RepositoryTopologyCacheEntry>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}
