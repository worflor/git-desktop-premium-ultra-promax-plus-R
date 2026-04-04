use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::operations::{BranchListData, CommitDetailData};
use crate::models::repository::RepositoryStatusData;
use crate::services::git_provider;

const MAX_CACHED_COMMIT_DETAILS: usize = 512;
const REPOSITORY_STATUS_CACHE_TTL: Duration = Duration::from_millis(750);
const BRANCH_LIST_CACHE_TTL: Duration = Duration::from_secs(3);

#[derive(Debug, Clone)]
struct RepositoryStatusSnapshot {
    captured_at: Instant,
    data: RepositoryStatusData,
}

#[derive(Debug, Clone)]
struct BranchListSnapshot {
    captured_at: Instant,
    data: BranchListData,
}

pub fn get_repository_status(repository_path: &str) -> Result<RepositoryStatusData, AppError> {
    if let Ok(cache) = repository_status_cache().lock() {
        if let Some(entry) = cache.get(repository_path) {
            if entry.captured_at.elapsed() <= REPOSITORY_STATUS_CACHE_TTL {
                return Ok(entry.data.clone());
            }
        }
    }

    let data = git_provider::get_repository_status(repository_path)?;
    if let Ok(mut cache) = repository_status_cache().lock() {
        cache.insert(
            repository_path.to_string(),
            RepositoryStatusSnapshot {
                captured_at: Instant::now(),
                data: data.clone(),
            },
        );
    }
    Ok(data)
}

pub fn list_branches(repository_path: &str) -> Result<BranchListData, AppError> {
    if let Ok(cache) = branch_list_cache().lock() {
        if let Some(entry) = cache.get(repository_path) {
            if entry.captured_at.elapsed() <= BRANCH_LIST_CACHE_TTL {
                return Ok(entry.data.clone());
            }
        }
    }

    let data = git_provider::list_branches(repository_path)?;
    if let Ok(mut cache) = branch_list_cache().lock() {
        cache.insert(
            repository_path.to_string(),
            BranchListSnapshot {
                captured_at: Instant::now(),
                data: data.clone(),
            },
        );
    }
    Ok(data)
}

pub fn get_commit_detail(
    repository_path: &str,
    commit_hash: &str,
) -> Result<CommitDetailData, AppError> {
    if let Some(cached) = get_cached_commit_detail(repository_path, commit_hash)? {
        return Ok(cached);
    }

    let data = git_provider::get_commit_detail(repository_path, commit_hash)?;
    cache_commit_details(repository_path, std::slice::from_ref(&data))?;
    Ok(data)
}

pub fn prime_commit_details(
    repository_path: &str,
    commit_hashes: &[String],
) -> Result<Vec<CommitDetailData>, AppError> {
    let mut entries = Vec::<CommitDetailData>::new();
    let mut missing_hashes = Vec::<String>::new();

    for commit_hash in commit_hashes {
        match get_cached_commit_detail(repository_path, commit_hash)? {
            Some(entry) => entries.push(entry),
            None => missing_hashes.push(commit_hash.clone()),
        }
    }

    if !missing_hashes.is_empty() {
        let fetched_entries = git_provider::get_commit_details(repository_path, &missing_hashes)?;
        cache_commit_details(repository_path, &fetched_entries)?;
        entries.extend(fetched_entries);
    }

    Ok(entries)
}

pub fn invalidate_repository(repository_path: &str) {
    if let Ok(mut cache) = repository_status_cache().lock() {
        cache.remove(repository_path);
    }
    if let Ok(mut cache) = branch_list_cache().lock() {
        cache.remove(repository_path);
    }
}

fn get_cached_commit_detail(
    repository_path: &str,
    commit_hash: &str,
) -> Result<Option<CommitDetailData>, AppError> {
    let cache = commit_detail_cache()
        .lock()
        .map_err(|_| AppError::Internal("failed to lock commit detail cache".to_string()))?;
    Ok(cache
        .get(commit_detail_cache_key(repository_path, commit_hash).as_str())
        .cloned())
}

fn cache_commit_details(
    repository_path: &str,
    entries: &[CommitDetailData],
) -> Result<(), AppError> {
    let mut cache = commit_detail_cache()
        .lock()
        .map_err(|_| AppError::Internal("failed to lock commit detail cache".to_string()))?;

    for entry in entries {
        cache.insert(
            commit_detail_cache_key(repository_path, entry.commit_hash.as_str()),
            entry.clone(),
        );
    }

    while cache.len() > MAX_CACHED_COMMIT_DETAILS {
        let Some(first_key) = cache.keys().next().cloned() else {
            break;
        };
        cache.remove(first_key.as_str());
    }

    Ok(())
}

fn commit_detail_cache_key(repository_path: &str, commit_hash: &str) -> String {
    format!("{repository_path}::{commit_hash}")
}

fn commit_detail_cache() -> &'static Mutex<HashMap<String, CommitDetailData>> {
    static CACHE: OnceLock<Mutex<HashMap<String, CommitDetailData>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn repository_status_cache() -> &'static Mutex<HashMap<String, RepositoryStatusSnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, RepositoryStatusSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn branch_list_cache() -> &'static Mutex<HashMap<String, BranchListSnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, BranchListSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}
