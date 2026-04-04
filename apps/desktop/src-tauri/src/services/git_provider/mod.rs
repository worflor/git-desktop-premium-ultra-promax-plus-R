mod cli;

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::git::GitCapabilities;
use crate::models::operations::{
    BranchInfoData, BranchListData, CommitDetailData, CommitFileStatData, CommitHistoryData,
    CommitHistoryEntryData, ConflictResolutionData, StashEntryData, StashListData,
    StashOperationData, SyncData, WorktreeData, WorktreeListData,
};
use crate::models::repository::{RepositoryStatusData, RepositoryStatusFile};

pub use cli::{run_git, GitCommandOutput};

const MIN_GIT_MAJOR: u32 = 2;
const MIN_GIT_MINOR: u32 = 39;
const GIT_READY_CACHE_TTL: Duration = Duration::from_secs(5 * 60);

#[derive(Debug, Clone, Copy)]
struct GitReadyCacheEntry {
    checked_at: Instant,
}

struct SyncTarget {
    branch: String,
    upstream: Option<String>,
    remote: String,
    remote_branch: String,
    ahead: u32,
    behind: u32,
}

pub fn detect_capabilities() -> Result<GitCapabilities, AppError> {
    let output = run_git(None, &["--version"])?;

    let version = output
        .stdout
        .trim()
        .strip_prefix("git version ")
        .map(|value| value.to_string());
    ensure_minimum_version(version.as_deref())?;

    let supports_partial_clone = version
        .as_deref()
        .and_then(parse_git_major_minor)
        .map(|(major, minor)| major > 2 || (major == 2 && minor >= 19))
        .unwrap_or(false);
    let supports_sparse_checkout = version
        .as_deref()
        .and_then(parse_git_major_minor)
        .map(|(major, minor)| major > 2 || (major == 2 && minor >= 25))
        .unwrap_or(false);

    Ok(GitCapabilities {
        git_installed: true,
        git_version: version,
        git_executable_path: resolve_git_executable_path(),
        supports_partial_clone,
        supports_sparse_checkout,
    })
}

fn resolve_git_executable_path() -> Option<String> {
    let lookup = if cfg!(target_os = "windows") {
        Command::new("where").arg("git").output()
    } else {
        Command::new("which").arg("git").output()
    }
    .ok()?;

    if !lookup.status.success() {
        return None;
    }

    first_non_empty_line(&lookup.stdout)
}

fn first_non_empty_line(payload: &[u8]) -> Option<String> {
    String::from_utf8_lossy(payload)
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(|line| line.to_string())
}

fn ensure_git_ready() -> Result<(), AppError> {
    if let Ok(cache) = git_ready_cache().lock() {
        if let Some(entry) = cache.as_ref() {
            if entry.checked_at.elapsed() < GIT_READY_CACHE_TTL {
                return Ok(());
            }
        }
    }

    let output = run_git(None, &["--version"])?;
    let version = output.stdout.trim().strip_prefix("git version ");
    ensure_minimum_version(version)?;

    if let Ok(mut cache) = git_ready_cache().lock() {
        *cache = Some(GitReadyCacheEntry {
            checked_at: Instant::now(),
        });
    }

    Ok(())
}

fn git_ready_cache() -> &'static Mutex<Option<GitReadyCacheEntry>> {
    static CACHE: OnceLock<Mutex<Option<GitReadyCacheEntry>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

fn ensure_minimum_version(version: Option<&str>) -> Result<(), AppError> {
    let minimum = format!("{MIN_GIT_MAJOR}.{MIN_GIT_MINOR}");
    let Some(version_text) = version else {
        return Err(AppError::UnsupportedGitVersion {
            found: "unknown".to_string(),
            minimum,
        });
    };

    let Some((major, minor)) = parse_git_major_minor(version_text) else {
        return Err(AppError::UnsupportedGitVersion {
            found: version_text.to_string(),
            minimum,
        });
    };

    if major < MIN_GIT_MAJOR || (major == MIN_GIT_MAJOR && minor < MIN_GIT_MINOR) {
        return Err(AppError::UnsupportedGitVersion {
            found: version_text.to_string(),
            minimum,
        });
    }

    Ok(())
}

fn parse_git_major_minor(version: &str) -> Option<(u32, u32)> {
    let mut sections = version.split('.');
    let major = sections.next()?.parse::<u32>().ok()?;
    let minor = sections.next()?.parse::<u32>().ok()?;
    Some((major, minor))
}

pub fn get_repository_status(repository_path: &str) -> Result<RepositoryStatusData, AppError> {
    ensure_git_ready()?;

    let output = run_git(
        Some(repository_path),
        &[
            "status",
            "--porcelain=2",
            "--branch",
            "--untracked-files=all",
        ],
    )?;

    let mut branch = "detached".to_string();
    let mut upstream = None::<String>;
    let mut ahead = 0_u32;
    let mut behind = 0_u32;
    let mut files = Vec::new();
    let mut seen = HashMap::<String, bool>::new();

    for line in output.stdout.lines() {
        if let Some(value) = line.strip_prefix("# branch.head ") {
            branch = value.to_string();
            continue;
        }

        if let Some(value) = line.strip_prefix("# branch.upstream ") {
            upstream = trimmed_non_empty(value).map(str::to_string);
            continue;
        }

        if let Some(value) = line.strip_prefix("# branch.ab ") {
            for part in value.split_whitespace() {
                if let Some(parsed) = part
                    .strip_prefix('+')
                    .and_then(|num| num.parse::<u32>().ok())
                {
                    ahead = parsed;
                }
                if let Some(parsed) = part
                    .strip_prefix('-')
                    .and_then(|num| num.parse::<u32>().ok())
                {
                    behind = parsed;
                }
            }
            continue;
        }

        if let Some(path) = line.strip_prefix("? ") {
            files.push(RepositoryStatusFile {
                path: path.to_string(),
                staged: "clean".to_string(),
                unstaged: "untracked".to_string(),
            });
            continue;
        }

        if line.starts_with("1 ") || line.starts_with("2 ") || line.starts_with("u ") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            let xy = parts.get(1).copied().unwrap_or("??");
            let path = parts.last().copied().unwrap_or("").to_string();

            if seen.insert(path.clone(), true).is_none() {
                files.push(RepositoryStatusFile {
                    path,
                    staged: normalize_status_code(xy.chars().next()),
                    unstaged: normalize_status_code(xy.chars().nth(1)),
                });
            }
        }
    }

    Ok(RepositoryStatusData {
        branch,
        upstream,
        ahead,
        behind,
        files,
    })
}

pub fn stage_paths(repository_path: &str, paths: &[String]) -> Result<usize, AppError> {
    ensure_git_ready()?;

    if paths.is_empty() {
        return Err(AppError::InvalidInput(
            "at least one path is required for stage operation".to_string(),
        ));
    }

    let mut args: Vec<&str> = Vec::with_capacity(paths.len() + 2);
    args.push("add");
    args.push("--");

    for path in paths {
        if path.trim().is_empty() {
            return Err(AppError::InvalidInput(
                "paths must not contain empty values".to_string(),
            ));
        }
        args.push(path.as_str());
    }

    run_git(Some(repository_path), &args)?;
    Ok(paths.len())
}

pub fn unstage_paths(repository_path: &str, paths: &[String]) -> Result<usize, AppError> {
    ensure_git_ready()?;

    if paths.is_empty() {
        return Err(AppError::InvalidInput(
            "at least one path is required for unstage operation".to_string(),
        ));
    }

    let mut args: Vec<&str> = Vec::with_capacity(paths.len() + 3);
    args.push("restore");
    args.push("--staged");
    args.push("--");

    for path in paths {
        if path.trim().is_empty() {
            return Err(AppError::InvalidInput(
                "paths must not contain empty values".to_string(),
            ));
        }
        args.push(path.as_str());
    }

    run_git(Some(repository_path), &args)?;
    Ok(paths.len())
}

pub fn create_commit(
    repository_path: &str,
    message: &str,
    amend: bool,
    signoff: bool,
) -> Result<String, AppError> {
    ensure_git_ready()?;

    let message = message.trim().to_string();
    if message.is_empty() {
        return Err(AppError::InvalidInput(
            "commit message cannot be empty".to_string(),
        ));
    }

    let mut args: Vec<&str> = vec!["commit", "-m", message.as_str()];
    if amend {
        args.push("--amend");
    }
    if signoff {
        args.push("--signoff");
    }

    let output = run_git(Some(repository_path), &args)?;
    Ok(output
        .stdout
        .lines()
        .next()
        .filter(|line| !line.trim().is_empty())
        .unwrap_or("Commit created")
        .to_string())
}

pub fn get_head_commit_hash(repository_path: &str) -> Result<String, AppError> {
    ensure_git_ready()?;

    let output = run_git(Some(repository_path), &["rev-parse", "HEAD"])?;
    Ok(output.stdout)
}

pub fn get_conflict_operation(repository_path: &str) -> Result<Option<String>, AppError> {
    ensure_git_ready()?;
    detect_conflict_operation(repository_path)
}

pub fn get_file_diff(
    repository_path: &str,
    path: &str,
    staged: bool,
    context_lines: usize,
) -> Result<String, AppError> {
    ensure_git_ready()?;

    let path = path.trim().to_string();
    if path.is_empty() {
        return Err(AppError::InvalidInput(
            "path is required for diff retrieval".to_string(),
        ));
    }

    let context_flag = format!("-U{context_lines}");
    let mut args: Vec<&str> = vec!["diff"];
    if staged {
        args.push("--staged");
    }
    args.push(context_flag.as_str());
    args.push("--");
    args.push(path.as_str());

    let output = run_git(Some(repository_path), &args)?;
    Ok(output.stdout)
}

pub fn fetch_remote(
    repository_path: &str,
    remote: Option<&str>,
    prune: bool,
) -> Result<String, AppError> {
    ensure_git_ready()?;

    let mut args: Vec<&str> = vec!["fetch"];
    if prune {
        args.push("--prune");
    }
    if let Some(remote_name) = remote.and_then(trimmed_non_empty) {
        args.push(remote_name);
    }

    let output = run_git(Some(repository_path), &args)?;
    Ok(render_command_output(&output, "Fetch completed"))
}

pub fn pull_remote(
    repository_path: &str,
    remote: Option<&str>,
    branch: Option<&str>,
    rebase: bool,
) -> Result<String, AppError> {
    ensure_git_ready()?;

    let mut args: Vec<&str> = vec!["pull"];
    if rebase {
        args.push("--rebase");
    }
    if let Some(remote_name) = remote.and_then(trimmed_non_empty) {
        args.push(remote_name);
    }
    if let Some(branch_name) = branch.and_then(trimmed_non_empty) {
        args.push(branch_name);
    }

    let output = run_git(Some(repository_path), &args)?;
    Ok(render_command_output(&output, "Pull completed"))
}

pub fn push_remote(
    repository_path: &str,
    remote: Option<&str>,
    branch: Option<&str>,
    force_with_lease: bool,
) -> Result<String, AppError> {
    ensure_git_ready()?;

    let mut args: Vec<&str> = vec!["push"];
    if force_with_lease {
        args.push("--force-with-lease");
    }
    if let Some(remote_name) = remote.and_then(trimmed_non_empty) {
        args.push(remote_name);
    }
    if let Some(branch_name) = branch.and_then(trimmed_non_empty) {
        args.push(branch_name);
    }

    let output = run_git(Some(repository_path), &args)?;
    Ok(render_command_output(&output, "Push completed"))
}

pub fn sync_remote(repository_path: &str) -> Result<SyncData, AppError> {
    ensure_git_ready()?;

    let fetch_output = run_git(Some(repository_path), &["fetch", "--prune"])?;
    let initial_target = resolve_current_sync_target(repository_path)?;
    let mut notes = Vec::<String>::new();
    let fetch_message = render_command_output(&fetch_output, "");
    if !fetch_message.is_empty() {
        notes.push(fetch_message);
    }

    let mut operation = "fetch".to_string();
    let mut active_target = initial_target;

    if active_target.upstream.is_none() {
        let publish_output = run_git(
            Some(repository_path),
            &[
                "push",
                "--set-upstream",
                active_target.remote.as_str(),
                active_target.branch.as_str(),
            ],
        )?;
        notes.push(render_command_output(
            &publish_output,
            "Published branch and set upstream",
        ));
        operation = "publish".to_string();
    } else {
        let should_pull = active_target.behind > 0;
        let should_push = active_target.ahead > 0;

        if should_pull {
            let pull_output = run_git(
                Some(repository_path),
                &[
                    "pull",
                    "--rebase",
                    active_target.remote.as_str(),
                    active_target.remote_branch.as_str(),
                ],
            )?;
            notes.push(render_command_output(&pull_output, "Pull completed"));
            active_target = resolve_current_sync_target(repository_path)?;
            operation = "pull".to_string();
        }

        if active_target.ahead > 0 || should_push {
            let push_output = run_git(
                Some(repository_path),
                &[
                    "push",
                    active_target.remote.as_str(),
                    active_target.branch.as_str(),
                ],
            )?;
            notes.push(render_command_output(&push_output, "Push completed"));
            operation = if should_pull {
                "sync".to_string()
            } else {
                "push".to_string()
            };
        } else if !should_pull {
            notes.push("Remote refs refreshed. No local commits needed syncing.".to_string());
        }
    }

    Ok(SyncData {
        operation,
        remote: active_target.remote,
        branch: Some(active_target.branch),
        output: notes
            .into_iter()
            .filter(|entry| !entry.trim().is_empty())
            .collect::<Vec<_>>()
            .join("\n\n"),
    })
}

pub fn start_rebase(
    repository_path: &str,
    onto_ref: &str,
) -> Result<ConflictResolutionData, AppError> {
    ensure_git_ready()?;

    let onto_ref = onto_ref.trim();
    if onto_ref.is_empty() {
        return Err(AppError::InvalidInput(
            "onto ref is required to start rebase".to_string(),
        ));
    }

    let output = run_git(Some(repository_path), &["rebase", onto_ref])?;
    let resolved_output = if output.stdout.is_empty() {
        format!("rebase start completed onto {onto_ref}")
    } else {
        output.stdout
    };

    Ok(ConflictResolutionData {
        repository_path: repository_path.to_string(),
        operation: "rebase".to_string(),
        action: "start".to_string(),
        output: resolved_output,
    })
}

pub fn continue_rebase(repository_path: &str) -> Result<ConflictResolutionData, AppError> {
    continue_conflict_resolution(repository_path, Some("rebase"))
}

pub fn abort_rebase(repository_path: &str) -> Result<ConflictResolutionData, AppError> {
    abort_conflict_resolution(repository_path, Some("rebase"))
}

pub fn start_cherry_pick(
    repository_path: &str,
    commit_ref: &str,
    mainline: Option<u32>,
) -> Result<ConflictResolutionData, AppError> {
    ensure_git_ready()?;

    let commit_ref = commit_ref.trim();
    if commit_ref.is_empty() {
        return Err(AppError::InvalidInput(
            "commit ref is required to start cherry-pick".to_string(),
        ));
    }

    let mut args = vec!["cherry-pick".to_string()];
    if let Some(mainline) = mainline {
        if mainline == 0 {
            return Err(AppError::InvalidInput(
                "mainline parent must be >= 1 for cherry-pick".to_string(),
            ));
        }

        args.push("-m".to_string());
        args.push(mainline.to_string());
    }
    args.push(commit_ref.to_string());

    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let output = run_git(Some(repository_path), &refs)?;
    let resolved_output = if output.stdout.is_empty() {
        format!("cherry-pick start completed for {commit_ref}")
    } else {
        output.stdout
    };

    Ok(ConflictResolutionData {
        repository_path: repository_path.to_string(),
        operation: "cherry-pick".to_string(),
        action: "start".to_string(),
        output: resolved_output,
    })
}

pub fn continue_cherry_pick(repository_path: &str) -> Result<ConflictResolutionData, AppError> {
    continue_conflict_resolution(repository_path, Some("cherry-pick"))
}

pub fn abort_cherry_pick(repository_path: &str) -> Result<ConflictResolutionData, AppError> {
    abort_conflict_resolution(repository_path, Some("cherry-pick"))
}

pub fn continue_conflict_resolution(
    repository_path: &str,
    operation: Option<&str>,
) -> Result<ConflictResolutionData, AppError> {
    ensure_git_ready()?;

    let resolved_operation = resolve_conflict_operation(repository_path, operation, "continue")?;
    let args = conflict_action_args(&resolved_operation, "continue")?;
    let output = run_git(Some(repository_path), &args)?;
    let resolved_output = if output.stdout.is_empty() {
        format!("{} continue completed", resolved_operation)
    } else {
        output.stdout
    };

    Ok(ConflictResolutionData {
        repository_path: repository_path.to_string(),
        operation: resolved_operation,
        action: "continue".to_string(),
        output: resolved_output,
    })
}

pub fn abort_conflict_resolution(
    repository_path: &str,
    operation: Option<&str>,
) -> Result<ConflictResolutionData, AppError> {
    ensure_git_ready()?;

    let resolved_operation = resolve_conflict_operation(repository_path, operation, "abort")?;
    let args = conflict_action_args(&resolved_operation, "abort")?;
    let output = run_git(Some(repository_path), &args)?;
    let resolved_output = if output.stdout.is_empty() {
        format!("{} abort completed", resolved_operation)
    } else {
        output.stdout
    };

    Ok(ConflictResolutionData {
        repository_path: repository_path.to_string(),
        operation: resolved_operation,
        action: "abort".to_string(),
        output: resolved_output,
    })
}

pub fn list_branches(repository_path: &str) -> Result<BranchListData, AppError> {
    ensure_git_ready()?;

    let args = [
        "branch",
        "--list",
        "--format=%(refname:short)|%(HEAD)|%(upstream:short)|%(upstream:track)",
    ];
    let output = run_git(Some(repository_path), &args)?;

    let mut branches = Vec::new();
    let mut current_branch = None;

    for line in output.stdout.lines() {
        if line.trim().is_empty() {
            continue;
        }

        let mut fields = line.splitn(4, '|');
        let name = fields.next().unwrap_or_default().trim().to_string();
        if name.is_empty() {
            continue;
        }

        let is_current = fields.next().unwrap_or_default().trim() == "*";
        let upstream_raw = fields.next().unwrap_or_default().trim();
        let track = fields.next().unwrap_or_default().trim();
        let (ahead, behind) = parse_branch_track(track);
        let upstream = if upstream_raw.is_empty() {
            None
        } else {
            Some(upstream_raw.to_string())
        };

        if is_current {
            current_branch = Some(name.clone());
        }

        branches.push(BranchInfoData {
            name,
            current: is_current,
            upstream,
            ahead,
            behind,
        });
    }

    Ok(BranchListData {
        current_branch,
        branches,
    })
}

pub fn list_worktrees(repository_path: &str) -> Result<WorktreeListData, AppError> {
    ensure_git_ready()?;

    let output = run_git(Some(repository_path), &["worktree", "list", "--porcelain"])?;
    let mut worktrees = Vec::<WorktreeData>::new();

    let mut path = None::<String>;
    let mut branch = None::<String>;
    let mut head = None::<String>;
    let mut bare = false;
    let mut detached = false;
    let mut locked = false;
    let mut prunable = false;

    for line in output.stdout.lines() {
        let row = line.trim();
        if row.is_empty() {
            if let Some(worktree_path) = path.take() {
                worktrees.push(WorktreeData {
                    path: worktree_path,
                    branch: branch.take(),
                    head: head.take(),
                    bare,
                    detached,
                    locked,
                    prunable,
                });
            }

            bare = false;
            detached = false;
            locked = false;
            prunable = false;
            continue;
        }

        if let Some(value) = row.strip_prefix("worktree ") {
            path = Some(value.to_string());
            continue;
        }

        if let Some(value) = row.strip_prefix("HEAD ") {
            head = Some(value.to_string());
            continue;
        }

        if let Some(value) = row.strip_prefix("branch ") {
            branch = Some(value.trim_start_matches("refs/heads/").to_string());
            detached = false;
            continue;
        }

        if row == "detached" {
            detached = true;
            branch = None;
            continue;
        }

        if row == "bare" {
            bare = true;
            continue;
        }

        if row.starts_with("locked") {
            locked = true;
            continue;
        }

        if row.starts_with("prunable") {
            prunable = true;
        }
    }

    if let Some(worktree_path) = path.take() {
        worktrees.push(WorktreeData {
            path: worktree_path,
            branch,
            head,
            bare,
            detached,
            locked,
            prunable,
        });
    }

    Ok(WorktreeListData {
        repository_path: repository_path.to_string(),
        worktrees,
    })
}

pub fn create_worktree(
    repository_path: &str,
    worktree_path: &str,
    branch_name: &str,
    start_point: Option<&str>,
) -> Result<(), AppError> {
    ensure_git_ready()?;

    let worktree_path = worktree_path.trim();
    let branch_name = branch_name.trim();
    if worktree_path.is_empty() || branch_name.is_empty() {
        return Err(AppError::InvalidInput(
            "worktree path and branch name are required".to_string(),
        ));
    }

    let mut args = vec![
        "worktree".to_string(),
        "add".to_string(),
        worktree_path.to_string(),
        "-b".to_string(),
        branch_name.to_string(),
    ];
    if let Some(reference) = start_point.and_then(trimmed_non_empty) {
        args.push(reference.to_string());
    }

    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    run_git(Some(repository_path), &refs)?;
    Ok(())
}

pub fn remove_worktree(
    repository_path: &str,
    worktree_path: &str,
    force: bool,
) -> Result<(), AppError> {
    ensure_git_ready()?;

    let worktree_path = worktree_path.trim();
    if worktree_path.is_empty() {
        return Err(AppError::InvalidInput(
            "worktree path is required".to_string(),
        ));
    }

    let mut args = vec!["worktree", "remove"];
    if force {
        args.push("--force");
    }
    args.push(worktree_path);

    run_git(Some(repository_path), &args)?;
    Ok(())
}

pub fn create_branch(
    repository_path: &str,
    branch_name: &str,
    from_ref: Option<&str>,
) -> Result<(), AppError> {
    ensure_git_ready()?;

    let branch_name = branch_name.trim();
    if branch_name.is_empty() {
        return Err(AppError::InvalidInput(
            "branch name is required for create operation".to_string(),
        ));
    }

    let mut args = vec!["branch".to_string(), branch_name.to_string()];
    if let Some(reference) = from_ref.and_then(trimmed_non_empty) {
        args.push(reference.to_string());
    }

    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    run_git(Some(repository_path), &refs)?;
    Ok(())
}

pub fn checkout_branch(repository_path: &str, branch_name: &str) -> Result<(), AppError> {
    ensure_git_ready()?;

    let branch_name = branch_name.trim();
    if branch_name.is_empty() {
        return Err(AppError::InvalidInput(
            "branch name is required for checkout operation".to_string(),
        ));
    }

    let args = ["checkout", branch_name];
    run_git(Some(repository_path), &args)?;
    Ok(())
}

pub fn delete_branch(
    repository_path: &str,
    branch_name: &str,
    force: bool,
) -> Result<(), AppError> {
    ensure_git_ready()?;

    let branch_name = branch_name.trim();
    if branch_name.is_empty() {
        return Err(AppError::InvalidInput(
            "branch name is required for delete operation".to_string(),
        ));
    }

    let mode = if force { "-D" } else { "-d" };
    let args = ["branch", mode, branch_name];
    run_git(Some(repository_path), &args)?;
    Ok(())
}

pub fn rename_branch(
    repository_path: &str,
    old_branch_name: &str,
    new_branch_name: &str,
) -> Result<(), AppError> {
    ensure_git_ready()?;

    let old_branch_name = old_branch_name.trim();
    let new_branch_name = new_branch_name.trim();
    if old_branch_name.is_empty() || new_branch_name.is_empty() {
        return Err(AppError::InvalidInput(
            "old and new branch names are required for rename operation".to_string(),
        ));
    }
    if old_branch_name == new_branch_name {
        return Err(AppError::InvalidInput(
            "old and new branch names must differ".to_string(),
        ));
    }

    run_git(
        Some(repository_path),
        &["branch", "-m", old_branch_name, new_branch_name],
    )?;
    Ok(())
}

pub fn set_branch_upstream(
    repository_path: &str,
    branch_name: &str,
    upstream_ref: &str,
) -> Result<(), AppError> {
    ensure_git_ready()?;

    let branch_name = branch_name.trim();
    let upstream_ref = upstream_ref.trim();
    if branch_name.is_empty() || upstream_ref.is_empty() {
        return Err(AppError::InvalidInput(
            "branch name and upstream ref are required for tracking operation".to_string(),
        ));
    }

    run_git(
        Some(repository_path),
        &["branch", "--set-upstream-to", upstream_ref, branch_name],
    )?;
    Ok(())
}

pub fn list_stashes(repository_path: &str, limit: usize) -> Result<StashListData, AppError> {
    ensure_git_ready()?;

    let limit = limit.clamp(1, 500);
    let args = [
        "stash".to_string(),
        "list".to_string(),
        format!("-n{limit}"),
        "--format=%gd%x1f%gs".to_string(),
    ];
    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let output = run_git(Some(repository_path), &refs)?;

    let mut entries = Vec::<StashEntryData>::new();
    for row in output.stdout.lines() {
        let trimmed = row.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut fields = trimmed.splitn(2, '\x1f');
        let stash_ref = fields.next().unwrap_or_default().trim().to_string();
        let summary_raw = fields.next().unwrap_or_default().trim();
        if stash_ref.is_empty() {
            continue;
        }

        let (branch, summary) = parse_stash_branch_and_summary(summary_raw);
        entries.push(StashEntryData {
            stash_ref,
            branch,
            summary,
        });
    }

    Ok(StashListData {
        repository_path: repository_path.to_string(),
        entries,
    })
}

pub fn create_stash(
    repository_path: &str,
    message: Option<&str>,
    include_untracked: bool,
) -> Result<StashOperationData, AppError> {
    ensure_git_ready()?;

    let mut args = vec!["stash".to_string(), "push".to_string()];
    if include_untracked {
        args.push("--include-untracked".to_string());
    }
    if let Some(message) = message.and_then(trimmed_non_empty) {
        args.push("-m".to_string());
        args.push(message.to_string());
    }

    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let output = run_git(Some(repository_path), &refs)?;

    Ok(StashOperationData {
        repository_path: repository_path.to_string(),
        operation: "create".to_string(),
        stash_ref: resolve_latest_stash_ref(repository_path),
        output: if output.stdout.is_empty() {
            "Stash created".to_string()
        } else {
            output.stdout
        },
    })
}

pub fn pop_stash(
    repository_path: &str,
    stash_ref: Option<&str>,
) -> Result<StashOperationData, AppError> {
    ensure_git_ready()?;

    let mut args = vec!["stash", "pop"];
    if let Some(value) = stash_ref.and_then(trimmed_non_empty) {
        args.push(value);
    }

    let output = run_git(Some(repository_path), &args)?;

    Ok(StashOperationData {
        repository_path: repository_path.to_string(),
        operation: "pop".to_string(),
        stash_ref: stash_ref
            .and_then(trimmed_non_empty)
            .map(|value| value.to_string()),
        output: if output.stdout.is_empty() {
            "Stash popped".to_string()
        } else {
            output.stdout
        },
    })
}

pub fn drop_stash(repository_path: &str, stash_ref: &str) -> Result<StashOperationData, AppError> {
    ensure_git_ready()?;

    let stash_ref = stash_ref.trim();
    if stash_ref.is_empty() {
        return Err(AppError::InvalidInput(
            "stash ref is required for drop operation".to_string(),
        ));
    }

    let output = run_git(Some(repository_path), &["stash", "drop", stash_ref])?;

    Ok(StashOperationData {
        repository_path: repository_path.to_string(),
        operation: "drop".to_string(),
        stash_ref: Some(stash_ref.to_string()),
        output: if output.stdout.is_empty() {
            "Stash dropped".to_string()
        } else {
            output.stdout
        },
    })
}

pub fn list_commit_history(
    repository_path: &str,
    limit: usize,
    branch: Option<&str>,
) -> Result<CommitHistoryData, AppError> {
    ensure_git_ready()?;

    if limit == 0 {
        return Err(AppError::InvalidInput(
            "history limit must be greater than zero".to_string(),
        ));
    }

    let bounded_limit = limit.min(500);
    let mut args = vec![
        "log".to_string(),
        format!("-n{bounded_limit}"),
        "--date=iso-strict".to_string(),
        "--decorate=short".to_string(),
        "--pretty=format:%H%x1f%h%x1f%P%x1f%D%x1f%an%x1f%ae%x1f%ad%x1f%s%x1e".to_string(),
    ];
    if let Some(branch_name) = branch.and_then(trimmed_non_empty) {
        args.push(branch_name.to_string());
    }

    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    let output = run_git(Some(repository_path), &refs)?;

    let mut entries = Vec::new();
    for record in output.stdout.split('\x1e') {
        let row = record.trim();
        if row.is_empty() {
            continue;
        }

        let mut fields = row.splitn(8, '\x1f');
        let commit_hash = fields.next().unwrap_or_default().trim().to_string();
        let short_hash = fields.next().unwrap_or_default().trim().to_string();
        let parent_hashes = fields
            .next()
            .unwrap_or_default()
            .split_whitespace()
            .map(str::trim)
            .filter(|hash| !hash.is_empty())
            .map(|hash| hash.to_string())
            .collect::<Vec<_>>();
        let ref_names = fields
            .next()
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .map(|name| name.to_string())
            .collect::<Vec<_>>();
        let author_name = fields.next().unwrap_or_default().trim().to_string();
        let author_email = fields.next().unwrap_or_default().trim().to_string();
        let authored_at = fields.next().unwrap_or_default().trim().to_string();
        let subject = fields.next().unwrap_or_default().trim().to_string();

        if commit_hash.is_empty() {
            continue;
        }

        entries.push(CommitHistoryEntryData {
            commit_hash,
            short_hash,
            is_merge: parent_hashes.len() > 1,
            parent_hashes,
            ref_names,
            subject,
            author_name,
            author_email,
            authored_at,
        });
    }

    Ok(CommitHistoryData { entries })
}

pub fn get_commit_detail(
    repository_path: &str,
    commit_hash: &str,
) -> Result<CommitDetailData, AppError> {
    let details = get_commit_details(repository_path, &[commit_hash.to_string()])?;
    details.into_iter().next().ok_or_else(|| {
        AppError::Internal("failed to resolve commit detail from git output".to_string())
    })
}

pub fn get_commit_details(
    repository_path: &str,
    commit_hashes: &[String],
) -> Result<Vec<CommitDetailData>, AppError> {
    ensure_git_ready()?;

    let normalized_hashes: Vec<String> = commit_hashes
        .iter()
        .map(|hash| hash.trim())
        .filter(|hash| !hash.is_empty())
        .map(ToOwned::to_owned)
        .collect();
    if normalized_hashes.is_empty() {
        return Ok(Vec::new());
    }

    let mut meta_args = vec![
        "show".to_string(),
        "--no-patch".to_string(),
        "--date=iso-strict".to_string(),
        "--pretty=format:%x1e%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%s%x1f%b".to_string(),
    ];
    meta_args.extend(normalized_hashes.iter().cloned());
    let meta_refs: Vec<&str> = meta_args.iter().map(String::as_str).collect();
    let meta_output = run_git(Some(repository_path), &meta_refs)?;

    let mut details_by_hash = HashMap::<String, CommitDetailData>::new();
    for record in meta_output.stdout.split('\x1e') {
        let row = record.trim();
        if row.is_empty() {
            continue;
        }

        let mut fields = row.splitn(7, '\x1f');
        let parsed_commit_hash = fields.next().unwrap_or_default().trim().to_string();
        if parsed_commit_hash.is_empty() {
            continue;
        }

        details_by_hash.insert(
            parsed_commit_hash.clone(),
            CommitDetailData {
                commit_hash: parsed_commit_hash,
                short_hash: fields.next().unwrap_or_default().trim().to_string(),
                author_name: fields.next().unwrap_or_default().trim().to_string(),
                author_email: fields.next().unwrap_or_default().trim().to_string(),
                authored_at: fields.next().unwrap_or_default().trim().to_string(),
                subject: fields.next().unwrap_or_default().trim().to_string(),
                body: fields.next().unwrap_or_default().trim().to_string(),
                files_changed: 0,
                additions: 0,
                deletions: 0,
                files: Vec::new(),
            },
        );
    }

    if details_by_hash.is_empty() {
        return Err(AppError::Internal(
            "failed to parse commit metadata from git output".to_string(),
        ));
    }

    let mut stats_args = vec![
        "show".to_string(),
        "--numstat".to_string(),
        "--format=%x1e%H".to_string(),
    ];
    stats_args.extend(normalized_hashes.iter().cloned());
    let stats_refs: Vec<&str> = stats_args.iter().map(String::as_str).collect();
    let stats_output = run_git(Some(repository_path), &stats_refs)?;

    for record in stats_output.stdout.split('\x1e') {
        let row = record.trim();
        if row.is_empty() {
            continue;
        }

        let mut lines = row.lines();
        let Some(commit_hash) = lines
            .next()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            continue;
        };

        let Some(detail) = details_by_hash.get_mut(commit_hash) else {
            continue;
        };

        let mut additions = 0_u32;
        let mut deletions = 0_u32;
        let mut files = Vec::new();

        for line in lines {
            let stat_row = line.trim();
            if stat_row.is_empty() {
                continue;
            }

            let mut parts = stat_row.splitn(3, '\t');
            let add_raw = parts.next().unwrap_or_default().trim();
            let del_raw = parts.next().unwrap_or_default().trim();
            let path = parts.next().unwrap_or_default().trim().to_string();
            if path.is_empty() {
                continue;
            }

            let file_additions = parse_numstat_count(add_raw);
            let file_deletions = parse_numstat_count(del_raw);
            additions = additions.saturating_add(file_additions);
            deletions = deletions.saturating_add(file_deletions);

            files.push(CommitFileStatData {
                path,
                additions: file_additions,
                deletions: file_deletions,
            });
        }

        detail.files_changed = files.len() as u32;
        detail.additions = additions;
        detail.deletions = deletions;
        detail.files = files;
    }

    let mut details = Vec::with_capacity(normalized_hashes.len());
    for commit_hash in normalized_hashes {
        if let Some(detail) = details_by_hash.remove(commit_hash.as_str()) {
            details.push(detail);
        }
    }

    Ok(details)
}

fn trimmed_non_empty(value: &str) -> Option<&str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed)
}

fn render_command_output(output: &GitCommandOutput, fallback: &str) -> String {
    let mut sections = Vec::<String>::new();
    if let Some(stdout) = trimmed_non_empty(output.stdout.as_str()) {
        sections.push(stdout.to_string());
    }
    if let Some(stderr) = trimmed_non_empty(output.stderr.as_str()) {
        sections.push(stderr.to_string());
    }

    if sections.is_empty() {
        return fallback.to_string();
    }

    sections.join("\n")
}

fn is_detached_head(branch: &str) -> bool {
    let normalized = branch.trim();
    normalized.is_empty()
        || normalized.eq_ignore_ascii_case("detached")
        || normalized.eq_ignore_ascii_case("(detached)")
}

fn split_upstream_ref(upstream: &str) -> Option<(String, String)> {
    let (remote, branch) = upstream.trim().split_once('/')?;
    let remote = remote.trim();
    let branch = branch.trim();
    if remote.is_empty() || branch.is_empty() {
        return None;
    }

    Some((remote.to_string(), branch.to_string()))
}

fn resolve_current_sync_target(repository_path: &str) -> Result<SyncTarget, AppError> {
    let snapshot =
        crate::services::repository_root_service::get_repository_root_snapshot(repository_path)?;
    if is_detached_head(snapshot.current_branch.as_str()) {
        return Err(AppError::InvalidInput(
            "sync is unavailable while HEAD is detached".to_string(),
        ));
    }

    let (remote, remote_branch) = if let Some(upstream) = snapshot.upstream.as_deref() {
        split_upstream_ref(upstream).ok_or_else(|| {
            AppError::Internal(format!("failed to parse upstream ref: {upstream}"))
        })?
    } else {
        let remote = snapshot.default_remote.ok_or_else(|| {
            AppError::InvalidInput("no remote is configured for this repository".to_string())
        })?;
        (remote, snapshot.current_branch.clone())
    };

    Ok(SyncTarget {
        branch: snapshot.current_branch,
        upstream: snapshot.upstream,
        remote,
        remote_branch,
        ahead: snapshot.ahead,
        behind: snapshot.behind,
    })
}

fn normalize_status_code(code: Option<char>) -> String {
    match code.unwrap_or('?') {
        '.' => "clean".to_string(),
        'M' => "modified".to_string(),
        'A' => "added".to_string(),
        'D' => "deleted".to_string(),
        'R' => "renamed".to_string(),
        'C' => "copied".to_string(),
        'U' => "unmerged".to_string(),
        '?' => "unknown".to_string(),
        other => format!("state-{other}"),
    }
}

fn parse_branch_track(track: &str) -> (u32, u32) {
    let trimmed = track
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .trim();
    if trimmed.is_empty() {
        return (0, 0);
    }

    let mut ahead = 0_u32;
    let mut behind = 0_u32;
    for segment in trimmed.split(',') {
        let value = segment.trim();
        if let Some(parsed) = value
            .strip_prefix("ahead ")
            .and_then(|item| item.parse::<u32>().ok())
        {
            ahead = parsed;
            continue;
        }
        if let Some(parsed) = value
            .strip_prefix("behind ")
            .and_then(|item| item.parse::<u32>().ok())
        {
            behind = parsed;
        }
    }

    (ahead, behind)
}

fn parse_numstat_count(value: &str) -> u32 {
    if value == "-" {
        return 0;
    }
    value.parse::<u32>().unwrap_or(0)
}

fn parse_stash_branch_and_summary(raw_summary: &str) -> (Option<String>, String) {
    let summary = raw_summary.trim();
    if let Some(rest) = summary.strip_prefix("On ") {
        if let Some((branch, message)) = rest.split_once(':') {
            return (Some(branch.trim().to_string()), message.trim().to_string());
        }
    }

    if let Some(rest) = summary.strip_prefix("WIP on ") {
        if let Some((branch, message)) = rest.split_once(':') {
            return (Some(branch.trim().to_string()), message.trim().to_string());
        }
    }

    (None, summary.to_string())
}

fn resolve_latest_stash_ref(repository_path: &str) -> Option<String> {
    run_git(
        Some(repository_path),
        &["stash", "list", "-n1", "--format=%gd"],
    )
    .ok()
    .and_then(|output| {
        output
            .stdout
            .lines()
            .next()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| value.to_string())
    })
}

fn detect_conflict_operation(repository_path: &str) -> Result<Option<String>, AppError> {
    let git_dir = resolve_git_dir_path(repository_path)?;

    if has_git_ref(repository_path, "MERGE_HEAD") {
        return Ok(Some("merge".to_string()));
    }

    let rebase_in_progress = has_git_ref(repository_path, "REBASE_HEAD")
        || git_dir.join("rebase-merge").exists()
        || git_dir.join("rebase-apply").exists();
    if rebase_in_progress {
        return Ok(Some("rebase".to_string()));
    }

    if has_git_ref(repository_path, "CHERRY_PICK_HEAD") {
        return Ok(Some("cherry-pick".to_string()));
    }

    if has_git_ref(repository_path, "REVERT_HEAD") {
        return Ok(Some("revert".to_string()));
    }

    Ok(None)
}

fn has_git_ref(repository_path: &str, ref_name: &str) -> bool {
    run_git(
        Some(repository_path),
        &["rev-parse", "--verify", "--quiet", ref_name],
    )
    .is_ok()
}

fn resolve_git_dir_path(repository_path: &str) -> Result<PathBuf, AppError> {
    let output = run_git(Some(repository_path), &["rev-parse", "--absolute-git-dir"])?;
    let git_dir = output.stdout.trim();
    if git_dir.is_empty() {
        return Err(AppError::Internal(
            "failed to resolve git directory while checking conflict state".to_string(),
        ));
    }

    Ok(PathBuf::from(git_dir))
}

fn resolve_conflict_operation(
    repository_path: &str,
    requested_operation: Option<&str>,
    action: &str,
) -> Result<String, AppError> {
    if let Some(requested) = requested_operation.and_then(normalize_conflict_operation) {
        return Ok(requested.to_string());
    }

    if requested_operation.is_some() {
        return Err(AppError::InvalidInput(
            "unsupported conflict operation; expected merge, rebase, cherry-pick, or revert"
                .to_string(),
        ));
    }

    detect_conflict_operation(repository_path)?.ok_or_else(|| {
        AppError::InvalidInput(format!("no active conflict operation found for {action}"))
    })
}

fn normalize_conflict_operation(operation: &str) -> Option<&'static str> {
    match operation.trim().to_ascii_lowercase().as_str() {
        "merge" => Some("merge"),
        "rebase" => Some("rebase"),
        "cherry-pick" => Some("cherry-pick"),
        "revert" => Some("revert"),
        _ => None,
    }
}

fn conflict_action_args(operation: &str, action: &str) -> Result<Vec<&'static str>, AppError> {
    match (operation, action) {
        ("merge", "continue") => Ok(vec!["merge", "--continue"]),
        ("merge", "abort") => Ok(vec!["merge", "--abort"]),
        ("rebase", "continue") => Ok(vec!["rebase", "--continue"]),
        ("rebase", "abort") => Ok(vec!["rebase", "--abort"]),
        ("cherry-pick", "continue") => Ok(vec!["cherry-pick", "--continue"]),
        ("cherry-pick", "abort") => Ok(vec!["cherry-pick", "--abort"]),
        ("revert", "continue") => Ok(vec!["revert", "--continue"]),
        ("revert", "abort") => Ok(vec!["revert", "--abort"]),
        _ => Err(AppError::InvalidInput(format!(
            "unsupported conflict action '{action}' for operation '{operation}'"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use std::time::Instant;

    use uuid::Uuid;

    use crate::services::repository_topology_service;

    use super::{
        abort_conflict_resolution, conflict_action_args, continue_conflict_resolution,
        create_stash, create_worktree, drop_stash, get_commit_detail, get_repository_status,
        list_branches, list_commit_history, list_stashes, list_worktrees,
        normalize_conflict_operation, remove_worktree, set_branch_upstream, stage_paths,
        start_cherry_pick, start_rebase, sync_remote, unstage_paths,
    };

    struct FixtureRepo {
        path: PathBuf,
    }

    impl FixtureRepo {
        fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!("gdpu-fixture-{name}-{}", Uuid::new_v4()));
            fs::create_dir_all(&path).expect("failed to create fixture directory");

            run_fixture_git(&path, &["init", "-b", "main"]);
            run_fixture_git(&path, &["config", "user.name", "Fixture User"]);
            run_fixture_git(&path, &["config", "user.email", "fixture@example.com"]);
            run_fixture_git(&path, &["config", "commit.gpgsign", "false"]);

            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }

        fn path_str(&self) -> &str {
            self.path
                .to_str()
                .expect("fixture path should be valid utf-8")
        }
    }

    impl Drop for FixtureRepo {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn run_fixture_git(repository_path: &Path, args: &[&str]) -> String {
        let (success, stdout, stderr) = run_fixture_git_with_status(repository_path, args);
        assert!(
            success,
            "git command failed for args {:?}\nstdout:\n{}\nstderr:\n{}",
            args, stdout, stderr
        );
        stdout
    }

    fn run_fixture_git_with_status(
        repository_path: &Path,
        args: &[&str],
    ) -> (bool, String, String) {
        let output = Command::new("git")
            .args(args)
            .current_dir(repository_path)
            .output()
            .expect("failed to execute git command for fixture");

        (
            output.status.success(),
            String::from_utf8_lossy(&output.stdout).trim().to_string(),
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        )
    }

    fn write_repo_file(repository_path: &Path, relative_path: &str, contents: &str) {
        let full_path = repository_path.join(relative_path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent).expect("failed to create fixture file parent directories");
        }
        fs::write(full_path, contents).expect("failed to write fixture file");
    }

    fn commit_all(repository_path: &Path, message: &str) {
        run_fixture_git(repository_path, &["add", "--all"]);
        run_fixture_git(repository_path, &["commit", "-m", message]);
    }

    fn parse_branch_track_fixture(track: &str) -> (u32, u32) {
        let trimmed = track
            .trim()
            .trim_start_matches('[')
            .trim_end_matches(']')
            .trim();
        if trimmed.is_empty() {
            return (0, 0);
        }

        let mut ahead = 0_u32;
        let mut behind = 0_u32;

        for segment in trimmed.split(',') {
            let value = segment.trim();
            if let Some(parsed) = value
                .strip_prefix("ahead ")
                .and_then(|item| item.parse::<u32>().ok())
            {
                ahead = parsed;
                continue;
            }

            if let Some(parsed) = value
                .strip_prefix("behind ")
                .and_then(|item| item.parse::<u32>().ok())
            {
                behind = parsed;
            }
        }

        (ahead, behind)
    }

    fn expected_status_label(status: Option<char>) -> String {
        match status.unwrap_or('?') {
            '.' => "clean".to_string(),
            'M' => "modified".to_string(),
            'A' => "added".to_string(),
            'D' => "deleted".to_string(),
            'R' => "renamed".to_string(),
            'C' => "copied".to_string(),
            'U' => "unmerged".to_string(),
            '?' => "unknown".to_string(),
            other => format!("state-{other}"),
        }
    }

    fn git_status_snapshot(
        repository_path: &Path,
    ) -> (String, Option<String>, HashMap<String, String>) {
        let output = run_fixture_git(
            repository_path,
            &[
                "status",
                "--porcelain=2",
                "--branch",
                "--untracked-files=all",
            ],
        );

        let mut branch = "detached".to_string();
        let mut upstream = None::<String>;
        let mut files = HashMap::<String, String>::new();
        for line in output.lines() {
            if let Some(value) = line.strip_prefix("# branch.head ") {
                branch = value.to_string();
                continue;
            }

            if let Some(value) = line.strip_prefix("# branch.upstream ") {
                let trimmed = value.trim();
                if !trimmed.is_empty() {
                    upstream = Some(trimmed.to_string());
                }
                continue;
            }

            if let Some(path) = line.strip_prefix("? ") {
                files.insert(path.to_string(), "??".to_string());
                continue;
            }

            if line.starts_with("1 ") || line.starts_with("2 ") || line.starts_with("u ") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                let xy = parts.get(1).copied().unwrap_or("??").to_string();
                let path = parts.last().copied().unwrap_or_default().to_string();
                if !path.is_empty() {
                    files.insert(path, xy);
                }
            }
        }

        (branch, upstream, files)
    }

    fn assert_provider_matches_git_status(repository_path: &Path) {
        let expected = git_status_snapshot(repository_path);
        let actual = get_repository_status(
            repository_path
                .to_str()
                .expect("fixture path should be valid utf-8"),
        )
        .expect("expected provider status result");

        assert_eq!(actual.branch, expected.0);
        assert_eq!(actual.upstream, expected.1);
        assert_eq!(actual.files.len(), expected.2.len());

        for file in actual.files {
            let xy = expected
                .2
                .get(&file.path)
                .unwrap_or_else(|| panic!("missing fixture status for path {}", file.path));
            if xy == "??" {
                assert_eq!(file.staged, "untracked");
                assert_eq!(file.unstaged, "untracked");
                continue;
            }
            assert_eq!(file.staged, expected_status_label(xy.chars().next()));
            assert_eq!(file.unstaged, expected_status_label(xy.chars().nth(1)));
        }
    }

    fn parse_numstat_fixture(output: &str) -> (u32, u32, u32) {
        let mut additions = 0_u32;
        let mut deletions = 0_u32;
        let mut files_changed = 0_u32;

        for line in output.lines() {
            let row = line.trim();
            if row.is_empty() {
                continue;
            }

            let mut parts = row.splitn(3, '\t');
            let add_raw = parts.next().unwrap_or_default().trim();
            let del_raw = parts.next().unwrap_or_default().trim();
            let path = parts.next().unwrap_or_default().trim();
            if path.is_empty() {
                continue;
            }

            let add = if add_raw == "-" {
                0
            } else {
                add_raw.parse::<u32>().unwrap_or(0)
            };
            let del = if del_raw == "-" {
                0
            } else {
                del_raw.parse::<u32>().unwrap_or(0)
            };

            additions = additions.saturating_add(add);
            deletions = deletions.saturating_add(del);
            files_changed = files_changed.saturating_add(1);
        }

        (additions, deletions, files_changed)
    }

    fn percentile_duration_ms(values: &[u128], percentile: u8) -> u128 {
        if values.is_empty() {
            return 0;
        }

        let mut sorted = values.to_vec();
        sorted.sort_unstable();
        let scaled = (sorted.len() as u128) * (percentile as u128);
        let rank = scaled.div_ceil(100) as usize;
        let index = rank.saturating_sub(1).min(sorted.len() - 1);
        sorted[index]
    }

    fn perf_budget_from_env(name: &str) -> Option<u128> {
        std::env::var(name)
            .ok()
            .and_then(|value| value.trim().parse::<u128>().ok())
            .filter(|value| *value >= 1)
    }

    #[test]
    fn normalizes_supported_conflict_operations() {
        assert_eq!(normalize_conflict_operation("merge"), Some("merge"));
        assert_eq!(normalize_conflict_operation(" REBASE "), Some("rebase"));
        assert_eq!(
            normalize_conflict_operation("cherry-pick"),
            Some("cherry-pick")
        );
        assert_eq!(normalize_conflict_operation("revert"), Some("revert"));
    }

    #[test]
    fn rejects_unknown_conflict_operation() {
        assert_eq!(normalize_conflict_operation("stash"), None);
    }

    #[test]
    fn maps_merge_continue_conflict_args() {
        let args = conflict_action_args("merge", "continue").expect("expected merge continue args");
        assert_eq!(args, vec!["merge", "--continue"]);
    }

    #[test]
    fn start_rebase_requires_non_empty_onto_ref() {
        let fixture = FixtureRepo::new("rebase-validate");
        let error = start_rebase(fixture.path_str(), "  ")
            .expect_err("expected invalid input for blank rebase onto ref");
        assert!(error.to_string().contains("onto ref is required"));
    }

    #[test]
    fn start_cherry_pick_requires_non_empty_commit_ref() {
        let fixture = FixtureRepo::new("cherry-pick-validate");
        let error = start_cherry_pick(fixture.path_str(), "", None)
            .expect_err("expected invalid input for blank cherry-pick commit ref");
        assert!(error.to_string().contains("commit ref is required"));
    }

    #[test]
    fn start_cherry_pick_rejects_zero_mainline_parent() {
        let fixture = FixtureRepo::new("cherry-pick-mainline");
        let error = start_cherry_pick(fixture.path_str(), "deadbeef", Some(0))
            .expect_err("expected invalid input for zero cherry-pick mainline parent");
        assert!(error.to_string().contains("mainline parent must be >= 1"));
    }

    #[test]
    fn fixture_status_stage_unstage_matches_git_porcelain() {
        let fixture = FixtureRepo::new("status-stage-unstage");
        write_repo_file(fixture.path(), "tracked.txt", "line one\n");
        commit_all(fixture.path(), "initial fixture commit");

        write_repo_file(fixture.path(), "tracked.txt", "line one\nline two\n");
        write_repo_file(fixture.path(), "notes/untracked.txt", "draft notes\n");
        assert_provider_matches_git_status(fixture.path());

        let staged = stage_paths(fixture.path_str(), &["tracked.txt".to_string()])
            .expect("expected stage operation to succeed");
        assert_eq!(staged, 1);
        assert_provider_matches_git_status(fixture.path());

        let unstaged = unstage_paths(fixture.path_str(), &["tracked.txt".to_string()])
            .expect("expected unstage operation to succeed");
        assert_eq!(unstaged, 1);
        assert_provider_matches_git_status(fixture.path());
    }

    #[test]
    fn fixture_branch_listing_matches_git_cli() {
        let fixture = FixtureRepo::new("branch-list");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        run_fixture_git(fixture.path(), &["checkout", "-b", "feature/alpha"]);
        write_repo_file(fixture.path(), "tracked.txt", "feature alpha\n");
        commit_all(fixture.path(), "feature alpha commit");
        run_fixture_git(fixture.path(), &["checkout", "main"]);

        let provider = list_branches(fixture.path_str()).expect("expected provider branch list");
        let expected_output = run_fixture_git(
            fixture.path(),
            &[
                "branch",
                "--list",
                "--format=%(refname:short)|%(HEAD)|%(upstream:short)|%(upstream:track)",
            ],
        );

        let mut expected = HashMap::<String, (bool, Option<String>, u32, u32)>::new();
        let mut expected_current = None::<String>;
        for line in expected_output.lines() {
            if line.trim().is_empty() {
                continue;
            }

            let mut fields = line.splitn(4, '|');
            let name = fields.next().unwrap_or_default().trim().to_string();
            let is_current = fields.next().unwrap_or_default().trim() == "*";
            let upstream_raw = fields.next().unwrap_or_default().trim();
            let track = fields.next().unwrap_or_default().trim();
            let upstream = if upstream_raw.is_empty() {
                None
            } else {
                Some(upstream_raw.to_string())
            };
            let (ahead, behind) = parse_branch_track_fixture(track);

            if is_current {
                expected_current = Some(name.clone());
            }

            expected.insert(name, (is_current, upstream, ahead, behind));
        }

        assert_eq!(provider.current_branch, expected_current);
        assert_eq!(provider.branches.len(), expected.len());

        for branch in provider.branches {
            let expected_branch = expected
                .get(&branch.name)
                .unwrap_or_else(|| panic!("missing branch fixture for {}", branch.name));
            assert_eq!(branch.current, expected_branch.0);
            assert_eq!(branch.upstream, expected_branch.1);
            assert_eq!(branch.ahead, expected_branch.2);
            assert_eq!(branch.behind, expected_branch.3);
        }
    }

    #[test]
    fn fixture_set_branch_upstream_matches_git_cli() {
        let fixture = FixtureRepo::new("branch-upstream");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        let remote_path = std::env::temp_dir().join(format!("gdpu-remote-{}", Uuid::new_v4()));
        let remote_path_str = remote_path
            .to_str()
            .expect("remote path should be valid utf-8")
            .to_string();

        run_fixture_git(
            fixture.path(),
            &["init", "--bare", remote_path_str.as_str()],
        );
        run_fixture_git(
            fixture.path(),
            &["remote", "add", "origin", remote_path_str.as_str()],
        );
        run_fixture_git(fixture.path(), &["push", "-u", "origin", "main"]);

        run_fixture_git(fixture.path(), &["checkout", "-b", "feature/upstream"]);
        write_repo_file(fixture.path(), "tracked.txt", "base\nfeature\n");
        commit_all(fixture.path(), "feature commit");
        run_fixture_git(fixture.path(), &["push", "origin", "feature/upstream"]);

        let _ = run_fixture_git_with_status(fixture.path(), &["branch", "--unset-upstream"]);

        set_branch_upstream(
            fixture.path_str(),
            "feature/upstream",
            "origin/feature/upstream",
        )
        .expect("expected set branch upstream to succeed");

        let provider = list_branches(fixture.path_str()).expect("expected provider branch list");
        let feature_branch = provider
            .branches
            .iter()
            .find(|branch| branch.name == "feature/upstream")
            .expect("expected feature/upstream branch in provider result");
        assert_eq!(
            feature_branch.upstream.as_deref(),
            Some("origin/feature/upstream")
        );

        let expected_tracking = run_fixture_git(
            fixture.path(),
            &[
                "for-each-ref",
                "--format=%(upstream:short)|%(upstream:track)",
                "refs/heads/feature/upstream",
            ],
        );
        let mut fields = expected_tracking.splitn(2, '|');
        let expected_upstream = fields.next().unwrap_or_default().trim();
        let expected_track = fields.next().unwrap_or_default().trim();
        let (expected_ahead, expected_behind) = parse_branch_track_fixture(expected_track);

        assert_eq!(feature_branch.upstream.as_deref(), Some(expected_upstream));
        assert_eq!(feature_branch.ahead, expected_ahead);
        assert_eq!(feature_branch.behind, expected_behind);

        let _ = fs::remove_dir_all(remote_path);
    }

    #[test]
    fn fixture_sync_remote_publishes_branch_and_sets_upstream() {
        let fixture = FixtureRepo::new("sync-publish");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        let remote_path = std::env::temp_dir().join(format!("gdpu-sync-remote-{}", Uuid::new_v4()));
        let remote_path_str = remote_path
            .to_str()
            .expect("remote path should be valid utf-8")
            .to_string();

        run_fixture_git(
            fixture.path(),
            &["init", "--bare", remote_path_str.as_str()],
        );
        run_fixture_git(
            fixture.path(),
            &["remote", "add", "origin", remote_path_str.as_str()],
        );

        let sync_result =
            sync_remote(fixture.path_str()).expect("expected sync remote publish to succeed");
        assert_eq!(sync_result.operation, "publish");
        assert_eq!(sync_result.remote, "origin");
        assert_eq!(sync_result.branch.as_deref(), Some("main"));

        let provider_status =
            get_repository_status(fixture.path_str()).expect("expected provider status after sync");
        assert_eq!(provider_status.upstream.as_deref(), Some("origin/main"));

        let remote_head = run_fixture_git(
            fixture.path(),
            &[
                "--git-dir",
                remote_path_str.as_str(),
                "rev-parse",
                "refs/heads/main",
            ],
        );
        let local_head = run_fixture_git(fixture.path(), &["rev-parse", "HEAD"]);
        assert_eq!(remote_head, local_head);

        let _ = fs::remove_dir_all(remote_path);
    }

    #[test]
    fn fixture_commit_history_and_detail_match_git_cli() {
        let fixture = FixtureRepo::new("commit-detail");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        write_repo_file(fixture.path(), "tracked.txt", "base\nnext\n");
        write_repo_file(fixture.path(), "second.txt", "added\n");
        commit_all(fixture.path(), "second commit");

        let head_hash = run_fixture_git(fixture.path(), &["rev-parse", "HEAD"]);
        let detail = get_commit_detail(fixture.path_str(), &head_hash)
            .expect("expected commit detail result");
        let history = list_commit_history(fixture.path_str(), 10, None)
            .expect("expected commit history result");

        let expected_subject = run_fixture_git(
            fixture.path(),
            &[
                "show",
                "--no-patch",
                "--pretty=format:%s",
                head_hash.as_str(),
            ],
        );
        let expected_numstat = run_fixture_git(
            fixture.path(),
            &["show", "--numstat", "--format=", head_hash.as_str()],
        );
        let expected_log = run_fixture_git(
            fixture.path(),
            &[
                "log",
                "-n10",
                "--date=iso-strict",
                "--pretty=format:%H%x1f%s%x1e",
            ],
        );

        let (expected_additions, expected_deletions, expected_files_changed) =
            parse_numstat_fixture(&expected_numstat);
        assert_eq!(detail.commit_hash, head_hash);
        assert_eq!(detail.subject, expected_subject);
        assert_eq!(detail.additions, expected_additions);
        assert_eq!(detail.deletions, expected_deletions);
        assert_eq!(detail.files_changed, expected_files_changed);

        let expected_log_entries = expected_log
            .split('\x1e')
            .filter_map(|record| {
                let row = record.trim();
                if row.is_empty() {
                    return None;
                }

                let mut fields = row.splitn(2, '\x1f');
                let commit_hash = fields.next().unwrap_or_default().trim().to_string();
                let subject = fields.next().unwrap_or_default().trim().to_string();
                if commit_hash.is_empty() {
                    return None;
                }

                Some((commit_hash, subject))
            })
            .collect::<Vec<(String, String)>>();

        assert_eq!(history.entries.len(), expected_log_entries.len());
        for (entry, expected_entry) in history.entries.iter().zip(expected_log_entries.iter()) {
            assert_eq!(entry.commit_hash, expected_entry.0);
            assert_eq!(entry.subject, expected_entry.1);
        }
    }

    #[test]
    fn fixture_merge_conflict_state_and_abort_match_git_cli() {
        let fixture = FixtureRepo::new("merge-conflict");
        write_repo_file(fixture.path(), "conflict.txt", "base line\n");
        commit_all(fixture.path(), "base commit");

        run_fixture_git(fixture.path(), &["checkout", "-b", "feature/conflict"]);
        write_repo_file(fixture.path(), "conflict.txt", "feature line\n");
        commit_all(fixture.path(), "feature edit");

        run_fixture_git(fixture.path(), &["checkout", "main"]);
        write_repo_file(fixture.path(), "conflict.txt", "main line\n");
        commit_all(fixture.path(), "main edit");

        let merge_attempt =
            run_fixture_git_with_status(fixture.path(), &["merge", "feature/conflict"]);
        assert!(
            !merge_attempt.0,
            "expected merge to fail with conflict, but it succeeded"
        );

        let conflict_state = repository_topology_service::get_conflict_state(fixture.path_str())
            .expect("expected provider conflict state result");
        assert!(conflict_state.in_conflict);
        assert_eq!(conflict_state.operation.as_deref(), Some("merge"));

        let expected_files_output =
            run_fixture_git(fixture.path(), &["diff", "--name-only", "--diff-filter=U"]);
        let mut expected_files = expected_files_output
            .lines()
            .map(|line| line.trim().to_string())
            .filter(|line| !line.is_empty())
            .collect::<Vec<String>>();
        expected_files.sort();

        assert_eq!(conflict_state.conflicted_files, expected_files);

        let resolution = abort_conflict_resolution(fixture.path_str(), None)
            .expect("expected conflict abort operation to succeed");
        assert_eq!(resolution.operation, "merge");
        assert_eq!(resolution.action, "abort");

        let post_state = repository_topology_service::get_conflict_state(fixture.path_str())
            .expect("expected post-abort conflict state");
        assert!(!post_state.in_conflict);
        assert!(post_state.operation.is_none());
    }

    #[test]
    fn fixture_merge_conflict_continue_matches_git_cli() {
        let fixture = FixtureRepo::new("merge-conflict-continue");
        write_repo_file(fixture.path(), "conflict.txt", "base line\n");
        commit_all(fixture.path(), "base commit");

        run_fixture_git(
            fixture.path(),
            &["checkout", "-b", "feature/conflict-continue"],
        );
        write_repo_file(fixture.path(), "conflict.txt", "feature line\n");
        commit_all(fixture.path(), "feature edit");

        run_fixture_git(fixture.path(), &["checkout", "main"]);
        write_repo_file(fixture.path(), "conflict.txt", "main line\n");
        commit_all(fixture.path(), "main edit");

        let merge_attempt =
            run_fixture_git_with_status(fixture.path(), &["merge", "feature/conflict-continue"]);
        assert!(
            !merge_attempt.0,
            "expected merge to fail with conflict, but it succeeded"
        );

        write_repo_file(fixture.path(), "conflict.txt", "resolved line\n");
        run_fixture_git(fixture.path(), &["add", "conflict.txt"]);

        let resolution = continue_conflict_resolution(fixture.path_str(), Some("merge"))
            .expect("expected conflict continue operation to succeed");
        assert_eq!(resolution.operation, "merge");
        assert_eq!(resolution.action, "continue");

        let post_state = repository_topology_service::get_conflict_state(fixture.path_str())
            .expect("expected post-continue conflict state");
        assert!(!post_state.in_conflict);
        assert!(post_state.operation.is_none());

        let merge_parent_hashes =
            run_fixture_git(fixture.path(), &["log", "-1", "--pretty=format:%P"]);
        assert!(
            merge_parent_hashes.split_whitespace().count() >= 2,
            "expected merge continue to produce a merge commit"
        );
    }

    #[test]
    fn fixture_rebase_conflict_abort_matches_git_cli() {
        let fixture = FixtureRepo::new("rebase-conflict-abort");
        write_repo_file(fixture.path(), "conflict.txt", "base line\n");
        commit_all(fixture.path(), "base commit");

        run_fixture_git(fixture.path(), &["checkout", "-b", "feature/rebase-abort"]);
        write_repo_file(fixture.path(), "conflict.txt", "feature line\n");
        commit_all(fixture.path(), "feature edit");
        let feature_head_before_rebase = run_fixture_git(fixture.path(), &["rev-parse", "HEAD"]);

        run_fixture_git(fixture.path(), &["checkout", "main"]);
        write_repo_file(fixture.path(), "conflict.txt", "main line\n");
        commit_all(fixture.path(), "main edit");

        run_fixture_git(fixture.path(), &["checkout", "feature/rebase-abort"]);
        let rebase_attempt = run_fixture_git_with_status(fixture.path(), &["rebase", "main"]);
        assert!(
            !rebase_attempt.0,
            "expected rebase to fail with conflict, but it succeeded"
        );

        let conflict_state = repository_topology_service::get_conflict_state(fixture.path_str())
            .expect("expected provider conflict state result");
        assert!(conflict_state.in_conflict);
        assert_eq!(conflict_state.operation.as_deref(), Some("rebase"));

        let resolution = abort_conflict_resolution(fixture.path_str(), Some("rebase"))
            .expect("expected rebase abort operation to succeed");
        assert_eq!(resolution.operation, "rebase");
        assert_eq!(resolution.action, "abort");

        let post_state = repository_topology_service::get_conflict_state(fixture.path_str())
            .expect("expected post-abort conflict state");
        assert!(!post_state.in_conflict);
        assert!(post_state.operation.is_none());

        let feature_head_after_abort = run_fixture_git(fixture.path(), &["rev-parse", "HEAD"]);
        assert_eq!(feature_head_after_abort, feature_head_before_rebase);
    }

    #[test]
    fn fixture_stash_lifecycle_matches_git_cli() {
        let fixture = FixtureRepo::new("stash-lifecycle");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        write_repo_file(fixture.path(), "tracked.txt", "base\nnext\n");
        write_repo_file(fixture.path(), "notes/untracked.txt", "draft\n");

        let stash = create_stash(fixture.path_str(), Some("fixture stash"), true)
            .expect("expected stash creation to succeed");
        assert_eq!(stash.operation, "create");
        let stash_ref = stash
            .stash_ref
            .clone()
            .expect("created stash should return a stash ref");

        let provider_list =
            list_stashes(fixture.path_str(), 20).expect("expected provider stash list to succeed");
        let expected_list_output = run_fixture_git(
            fixture.path(),
            &["stash", "list", "-n20", "--format=%gd%x1f%gs"],
        );

        let expected_refs = expected_list_output
            .lines()
            .filter_map(|line| {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    return None;
                }
                let stash_ref = trimmed.split('\x1f').next().unwrap_or_default().trim();
                if stash_ref.is_empty() {
                    return None;
                }
                Some(stash_ref.to_string())
            })
            .collect::<Vec<String>>();

        let provider_refs = provider_list
            .entries
            .iter()
            .map(|entry| entry.stash_ref.clone())
            .collect::<Vec<String>>();
        assert_eq!(provider_refs, expected_refs);

        drop_stash(fixture.path_str(), stash_ref.as_str()).expect("expected stash drop to succeed");

        let post_drop = list_stashes(fixture.path_str(), 20)
            .expect("expected provider stash list after drop to succeed");
        assert!(post_drop.entries.is_empty());
    }

    #[test]
    fn fixture_worktree_create_remove_matches_git_cli() {
        let fixture = FixtureRepo::new("worktree-lifecycle");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        let worktree_path = std::env::temp_dir()
            .join(format!("gdpu-worktree-{}", Uuid::new_v4()))
            .to_string_lossy()
            .to_string();
        let branch_name = "feature/worktree";

        let baseline_list =
            list_worktrees(fixture.path_str()).expect("expected baseline worktree list to succeed");
        let baseline_count = baseline_list.worktrees.len();

        create_worktree(
            fixture.path_str(),
            worktree_path.as_str(),
            branch_name,
            Some("main"),
        )
        .expect("expected worktree creation to succeed");

        let provider_list =
            list_worktrees(fixture.path_str()).expect("expected provider worktree list to succeed");
        assert!(provider_list.worktrees.len() >= baseline_count.saturating_add(1));
        assert!(provider_list
            .worktrees
            .iter()
            .any(|item| item.branch.as_deref() == Some(branch_name)));

        remove_worktree(fixture.path_str(), worktree_path.as_str(), true)
            .expect("expected worktree removal to succeed");

        let post_remove = list_worktrees(fixture.path_str())
            .expect("expected provider worktree list after remove to succeed");
        assert!(post_remove.worktrees.len() <= provider_list.worktrees.len());
        assert!(!post_remove
            .worktrees
            .iter()
            .any(|item| item.branch.as_deref() == Some(branch_name)));
    }

    #[test]
    fn perf_budget_status_p95_within_threshold() {
        let fixture = FixtureRepo::new("status-perf-budget");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");
        write_repo_file(fixture.path(), "tracked.txt", "base\nnext\n");

        let Some(budget_ms) = perf_budget_from_env("GDPU_STATUS_P95_BUDGET_MS") else {
            eprintln!("skipping status perf budget test: GDPU_STATUS_P95_BUDGET_MS is not set");
            return;
        };

        // Warm the path before sampling to reduce one-time setup variance.
        for _ in 0..3 {
            let _ = get_repository_status(fixture.path_str())
                .expect("expected status warm-up call to succeed");
        }

        let mut durations_ms = Vec::<u128>::new();
        for _ in 0..20 {
            let started_at = Instant::now();
            let _ = get_repository_status(fixture.path_str())
                .expect("expected status benchmark call to succeed");
            durations_ms.push(started_at.elapsed().as_millis());
        }

        let p95_ms = percentile_duration_ms(&durations_ms, 95);
        assert!(
            p95_ms <= budget_ms,
            "status p95 exceeded budget: p95={}ms budget={}ms samples={:?}",
            p95_ms,
            budget_ms,
            durations_ms
        );
    }
}
