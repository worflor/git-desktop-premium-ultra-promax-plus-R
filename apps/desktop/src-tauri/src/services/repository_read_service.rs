use std::collections::HashMap;
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::operations::{BranchListData, CommitDetailData, CommitHistoryData};
use crate::models::repository::RepositoryStatusData;
use crate::services::{git_provider, repository_topology_service};

const MAX_CACHED_COMMIT_DETAILS: usize = 512;
const BRANCH_LIST_CACHE_TTL: Duration = Duration::from_secs(3);
const COMMIT_HISTORY_CACHE_TTL: Duration = Duration::from_secs(10);

type PendingCommitDetailSignal = Arc<(Mutex<bool>, Condvar)>;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CommitDetailFetchPriority {
    UserInteractive,
    SpeculativeWarm,
}

#[derive(Debug, Clone)]
struct PendingCommitDetailFetch {
    signal: PendingCommitDetailSignal,
    priority: CommitDetailFetchPriority,
}

#[derive(Debug, Clone)]
struct BranchListSnapshot {
    captured_at: Instant,
    data: BranchListData,
}

#[derive(Debug, Clone)]
struct CommitHistorySnapshot {
    captured_at: Instant,
    data: CommitHistoryData,
}

pub fn get_repository_status(repository_path: &str) -> Result<RepositoryStatusData, AppError> {
    repository_topology_service::get_repository_status(repository_path)
}

pub fn list_branches(repository_path: &str) -> Result<BranchListData, AppError> {
    if let Ok(cache) = branch_list_cache().lock() {
        if let Some(entry) = cache.get(repository_path) {
            if is_cache_snapshot_fresh(entry.captured_at, BRANCH_LIST_CACHE_TTL) {
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

pub fn list_commit_history(
    repository_path: &str,
    limit: usize,
    branch: Option<&str>,
) -> Result<CommitHistoryData, AppError> {
    let cache_key = commit_history_cache_key(repository_path, limit, branch)?;
    if let Ok(cache) = commit_history_cache().lock() {
        if let Some(entry) = cache.get(cache_key.as_str()) {
            if is_cache_snapshot_fresh(entry.captured_at, COMMIT_HISTORY_CACHE_TTL) {
                return Ok(entry.data.clone());
            }
        }
    }

    let data = git_provider::list_commit_history(repository_path, limit, branch)?;
    if let Ok(mut cache) = commit_history_cache().lock() {
        cache.insert(
            cache_key,
            CommitHistorySnapshot {
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

    let cache_key = commit_detail_cache_key(repository_path, commit_hash);
    match reserve_pending_commit_detail_fetch(
        cache_key.as_str(),
        CommitDetailFetchPriority::UserInteractive,
    )? {
        PendingCommitDetailReservation::Wait(fetch) => {
            wait_for_pending_commit_detail(fetch.signal)?;
            if let Some(cached) = get_cached_commit_detail(repository_path, commit_hash)? {
                return Ok(cached);
            }
        }
        PendingCommitDetailReservation::BypassSpeculative => {
            let result = git_provider::get_commit_detail(repository_path, commit_hash);
            if let Ok(data) = &result {
                cache_commit_details(repository_path, std::slice::from_ref(data))?;
            }
            return result;
        }
        PendingCommitDetailReservation::Owner(fetch) => {
            let result = git_provider::get_commit_detail(repository_path, commit_hash);
            let cache_result = if let Ok(data) = &result {
                cache_commit_details(repository_path, std::slice::from_ref(data))
            } else {
                Ok(())
            };
            let finish_result =
                finish_pending_commit_detail_fetch(cache_key.as_str(), fetch.signal);
            cache_result?;
            finish_result?;
            return result;
        }
    }

    let result = git_provider::get_commit_detail(repository_path, commit_hash);
    if let Ok(data) = &result {
        cache_commit_details(repository_path, std::slice::from_ref(data))?;
    }
    result
}

pub fn prime_commit_details(
    repository_path: &str,
    commit_hashes: &[String],
) -> Result<Vec<CommitDetailData>, AppError> {
    let mut entries = Vec::<CommitDetailData>::new();
    let mut missing_hashes = Vec::<String>::new();
    let mut owned_reservations = Vec::<(String, PendingCommitDetailSignal)>::new();

    for commit_hash in commit_hashes {
        match get_cached_commit_detail(repository_path, commit_hash)? {
            Some(entry) => entries.push(entry),
            None => {
                let cache_key = commit_detail_cache_key(repository_path, commit_hash);
                match reserve_pending_commit_detail_fetch(
                    cache_key.as_str(),
                    CommitDetailFetchPriority::SpeculativeWarm,
                )? {
                    PendingCommitDetailReservation::Owner(fetch) => {
                        missing_hashes.push(commit_hash.clone());
                        owned_reservations.push((cache_key, fetch.signal));
                    }
                    PendingCommitDetailReservation::Wait(_)
                    | PendingCommitDetailReservation::BypassSpeculative => {}
                }
            }
        }
    }

    if !missing_hashes.is_empty() {
        let fetched_entries = git_provider::get_commit_details(repository_path, &missing_hashes);
        match fetched_entries {
            Ok(fetched_entries) => {
                let cache_result = cache_commit_details(repository_path, &fetched_entries);
                for (cache_key, signal) in &owned_reservations {
                    finish_pending_commit_detail_fetch(cache_key.as_str(), signal.clone())?;
                }
                cache_result?;
                entries.extend(fetched_entries);
            }
            Err(error) => {
                for (cache_key, signal) in owned_reservations {
                    finish_pending_commit_detail_fetch(cache_key.as_str(), signal)?;
                }
                return Err(error);
            }
        }
    } else {
        for (cache_key, signal) in owned_reservations {
            finish_pending_commit_detail_fetch(cache_key.as_str(), signal)?;
        }
    }

    Ok(entries)
}

pub fn invalidate_repository(repository_path: &str) {
    if let Ok(mut cache) = branch_list_cache().lock() {
        cache.remove(repository_path);
    }
    if let Ok(mut cache) = commit_history_cache().lock() {
        let prefix = format!("{repository_path}::");
        cache.retain(|key, _| !key.starts_with(prefix.as_str()));
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

enum PendingCommitDetailReservation {
    Owner(PendingCommitDetailFetch),
    Wait(PendingCommitDetailFetch),
    BypassSpeculative,
}

fn reserve_pending_commit_detail_fetch(
    cache_key: &str,
    priority: CommitDetailFetchPriority,
) -> Result<PendingCommitDetailReservation, AppError> {
    let mut pending = pending_commit_detail_fetches().lock().map_err(|_| {
        AppError::Internal("failed to lock pending commit detail fetches".to_string())
    })?;

    if let Some(fetch) = pending.get(cache_key) {
        if priority == CommitDetailFetchPriority::UserInteractive
            && fetch.priority == CommitDetailFetchPriority::SpeculativeWarm
        {
            return Ok(PendingCommitDetailReservation::BypassSpeculative);
        }

        return Ok(PendingCommitDetailReservation::Wait(fetch.clone()));
    }

    let fetch = PendingCommitDetailFetch {
        signal: Arc::new((Mutex::new(false), Condvar::new())),
        priority,
    };
    pending.insert(cache_key.to_string(), fetch.clone());
    Ok(PendingCommitDetailReservation::Owner(fetch))
}

fn finish_pending_commit_detail_fetch(
    cache_key: &str,
    signal: PendingCommitDetailSignal,
) -> Result<(), AppError> {
    {
        let mut pending = pending_commit_detail_fetches().lock().map_err(|_| {
            AppError::Internal("failed to lock pending commit detail fetches".to_string())
        })?;
        pending.remove(cache_key);
    }

    let (done_lock, done_condvar) = &*signal;
    let mut done = done_lock.lock().map_err(|_| {
        AppError::Internal("failed to lock pending commit detail signal".to_string())
    })?;
    *done = true;
    done_condvar.notify_all();
    Ok(())
}

fn wait_for_pending_commit_detail(signal: PendingCommitDetailSignal) -> Result<(), AppError> {
    let (done_lock, done_condvar) = &*signal;
    let mut done = done_lock.lock().map_err(|_| {
        AppError::Internal("failed to lock pending commit detail signal".to_string())
    })?;

    while !*done {
        done = done_condvar.wait(done).map_err(|_| {
            AppError::Internal("failed to wait for pending commit detail".to_string())
        })?;
    }

    Ok(())
}

fn pending_commit_detail_fetches() -> &'static Mutex<HashMap<String, PendingCommitDetailFetch>> {
    static CACHE: OnceLock<Mutex<HashMap<String, PendingCommitDetailFetch>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn branch_list_cache() -> &'static Mutex<HashMap<String, BranchListSnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, BranchListSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn normalized_branch_name(branch: Option<&str>) -> Option<&str> {
    branch.and_then(|value| {
        let trimmed = value.trim();
        (!trimmed.is_empty()).then_some(trimmed)
    })
}

fn commit_history_cache_key(
    repository_path: &str,
    limit: usize,
    branch: Option<&str>,
) -> Result<String, AppError> {
    if let Some(branch_name) = normalized_branch_name(branch) {
        return Ok(format!("{repository_path}::{branch_name}::{limit}"));
    }

    let head_hash = git_provider::get_head_commit_hash(repository_path)?;
    Ok(format!("{repository_path}::HEAD:{head_hash}::{limit}"))
}

fn commit_history_cache() -> &'static Mutex<HashMap<String, CommitHistorySnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, CommitHistorySnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn is_cache_snapshot_fresh(captured_at: Instant, ttl: Duration) -> bool {
    captured_at.elapsed() <= ttl
}
