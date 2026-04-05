use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::operations::CommitHistoryEntryData;
use crate::services::{repository_read_service, repository_topology_service};

const ROOT_SNAPSHOT_CACHE_TTL: Duration = Duration::from_millis(900);
const HISTORY_WARM_COOLDOWN: Duration = Duration::from_millis(1500);
const MAX_HISTORY_WARM_COMMITS: usize = 8;

#[derive(Debug, Clone)]
pub struct RepositoryRootSnapshot {
    pub head_hash: String,
    pub current_branch: String,
    pub upstream: Option<String>,
    pub ahead: u32,
    pub behind: u32,
    pub conflict_operation: Option<String>,
    pub worktree_dirty: bool,
    pub default_remote: Option<String>,
}

#[derive(Debug, Clone)]
struct RepositoryRootSnapshotCacheEntry {
    captured_at: Instant,
    snapshot: RepositoryRootSnapshot,
}

pub fn get_repository_root_snapshot(
    repository_path: &str,
) -> Result<RepositoryRootSnapshot, AppError> {
    if let Ok(cache) = root_snapshot_cache().lock() {
        if let Some(entry) = cache.get(repository_path) {
            if entry.captured_at.elapsed() <= ROOT_SNAPSHOT_CACHE_TTL {
                return Ok(entry.snapshot.clone());
            }
        }
    }

    let topology = repository_topology_service::get_repository_topology_snapshot(repository_path)?;

    let snapshot = RepositoryRootSnapshot {
        head_hash: topology.head_hash,
        current_branch: topology.status.branch,
        upstream: topology.status.upstream,
        ahead: topology.status.ahead,
        behind: topology.status.behind,
        conflict_operation: topology.conflict_operation,
        worktree_dirty: !topology.status.files.is_empty(),
        default_remote: topology.default_remote,
    };

    if let Ok(mut cache) = root_snapshot_cache().lock() {
        cache.insert(
            repository_path.to_string(),
            RepositoryRootSnapshotCacheEntry {
                captured_at: Instant::now(),
                snapshot: snapshot.clone(),
            },
        );
    }

    Ok(snapshot)
}

pub fn invalidate_repository(repository_path: &str) {
    if let Ok(mut cache) = root_snapshot_cache().lock() {
        cache.remove(repository_path);
    }
}

pub fn schedule_commit_history_warm(
    repository_path: &str,
    entries: &[CommitHistoryEntryData],
) -> Result<(), AppError> {
    if !mark_warm_scheduled(repository_path) {
        return Ok(());
    }

    let repository_path = repository_path.to_string();
    let entries = entries.to_vec();
    thread::spawn(move || {
        let Ok(snapshot) = get_repository_root_snapshot(&repository_path) else {
            return;
        };
        if !should_warm_commit_details(&snapshot) {
            return;
        }

        let hashes = score_commit_history_candidates(snapshot.head_hash.as_str(), &entries);
        if hashes.is_empty() {
            return;
        }

        let _ = repository_read_service::prime_commit_details(&repository_path, &hashes);
    });

    Ok(())
}

fn score_commit_history_candidates(
    head_hash: &str,
    entries: &[CommitHistoryEntryData],
) -> Vec<String> {
    let mut weighted = entries
        .iter()
        .take(12)
        .enumerate()
        .map(|(index, entry)| {
            let positional_score: f64 = match index {
                0 => 1.0,
                1 => 0.9,
                2 => 0.78,
                3 => 0.66,
                4 => 0.54,
                5 => 0.45,
                6 => 0.36,
                7 => 0.28,
                _ => 0.18,
            };
            let score = if entry.commit_hash == head_hash {
                positional_score.max(0.95)
            } else {
                positional_score
            };
            (score, entry.commit_hash.clone())
        })
        .collect::<Vec<_>>();

    weighted.retain(|(score, _)| *score >= 0.28);
    weighted.truncate(MAX_HISTORY_WARM_COMMITS);
    weighted.into_iter().map(|(_, hash)| hash).collect()
}

fn should_warm_commit_details(snapshot: &RepositoryRootSnapshot) -> bool {
    !snapshot.worktree_dirty
        && snapshot.conflict_operation.is_none()
        && !is_detached_head(snapshot.current_branch.as_str())
}

fn is_detached_head(branch: &str) -> bool {
    let normalized = branch.trim().to_ascii_lowercase();
    normalized.is_empty() || normalized == "head" || normalized == "detached"
}

fn mark_warm_scheduled(repository_path: &str) -> bool {
    let Ok(mut cache) = warm_schedule_cache().lock() else {
        return true;
    };

    if let Some(last_scheduled_at) = cache.get(repository_path) {
        if last_scheduled_at.elapsed() <= HISTORY_WARM_COOLDOWN {
            return false;
        }
    }

    cache.insert(repository_path.to_string(), Instant::now());
    true
}

fn root_snapshot_cache() -> &'static Mutex<HashMap<String, RepositoryRootSnapshotCacheEntry>> {
    static CACHE: OnceLock<Mutex<HashMap<String, RepositoryRootSnapshotCacheEntry>>> =
        OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn warm_schedule_cache() -> &'static Mutex<HashMap<String, Instant>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Instant>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}
