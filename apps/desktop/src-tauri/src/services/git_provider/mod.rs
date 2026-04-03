mod cli;

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

use crate::errors::AppError;
use crate::models::git::GitCapabilities;
use crate::models::operations::{
    BranchInfoData, BranchListData, CommitDetailData, CommitFileStatData, CommitHistoryData,
    CommitHistoryEntryData, ConflictResolutionData, ConflictStateData, WorktreeData,
    WorktreeListData,
};
use crate::models::repository::{RepositoryStatusData, RepositoryStatusFile};

pub use cli::run_git;

const MIN_GIT_MAJOR: u32 = 2;
const MIN_GIT_MINOR: u32 = 39;

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
        supports_partial_clone,
        supports_sparse_checkout,
    })
}

fn ensure_git_ready() -> Result<(), AppError> {
    let output = run_git(None, &["--version"])?;
    let version = output.stdout.trim().strip_prefix("git version ");
    ensure_minimum_version(version)
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
        &["status", "--porcelain=2", "--branch", "--untracked-files=all"],
    )?;

    let mut branch = "detached".to_string();
    let mut ahead = 0_u32;
    let mut behind = 0_u32;
    let mut files = Vec::new();
    let mut seen = HashMap::<String, bool>::new();

    for line in output.stdout.lines() {
        if let Some(value) = line.strip_prefix("# branch.head ") {
            branch = value.to_string();
            continue;
        }

        if let Some(value) = line.strip_prefix("# branch.ab ") {
            for part in value.split_whitespace() {
                if let Some(parsed) = part.strip_prefix('+').and_then(|num| num.parse::<u32>().ok()) {
                    ahead = parsed;
                }
                if let Some(parsed) = part.strip_prefix('-').and_then(|num| num.parse::<u32>().ok()) {
                    behind = parsed;
                }
            }
            continue;
        }

        if let Some(path) = line.strip_prefix("? ") {
            files.push(RepositoryStatusFile {
                path: path.to_string(),
                staged: "untracked".to_string(),
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

pub fn fetch_remote(repository_path: &str, remote: Option<&str>, prune: bool) -> Result<String, AppError> {
    ensure_git_ready()?;

    let mut args: Vec<&str> = vec!["fetch"];
    if prune {
        args.push("--prune");
    }
    if let Some(remote_name) = remote.and_then(trimmed_non_empty) {
        args.push(remote_name);
    }

    let output = run_git(Some(repository_path), &args)?;
    if output.stdout.is_empty() {
        return Ok("Fetch completed".to_string());
    }

    Ok(output.stdout)
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
    if output.stdout.is_empty() {
        return Ok("Pull completed".to_string());
    }

    Ok(output.stdout)
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
    if output.stdout.is_empty() {
        return Ok("Push completed".to_string());
    }

    Ok(output.stdout)
}

pub fn get_conflict_state(repository_path: &str) -> Result<ConflictStateData, AppError> {
    ensure_git_ready()?;

    let conflicted_files = list_conflicted_files(repository_path)?;
    let operation = detect_conflict_operation(repository_path)?;
    let in_conflict = !conflicted_files.is_empty() || operation.is_some();
    let guidance = build_conflict_guidance(operation.as_deref(), in_conflict);

    Ok(ConflictStateData {
        repository_path: repository_path.to_string(),
        in_conflict,
        operation,
        conflicted_files,
        guidance,
    })
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

pub fn delete_branch(repository_path: &str, branch_name: &str, force: bool) -> Result<(), AppError> {
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
        "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%s%x1e".to_string(),
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

        let mut fields = row.splitn(6, '\x1f');
        let commit_hash = fields.next().unwrap_or_default().trim().to_string();
        let short_hash = fields.next().unwrap_or_default().trim().to_string();
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
            subject,
            author_name,
            author_email,
            authored_at,
        });
    }

    Ok(CommitHistoryData { entries })
}

pub fn get_commit_detail(repository_path: &str, commit_hash: &str) -> Result<CommitDetailData, AppError> {
    ensure_git_ready()?;

    let commit_hash = commit_hash.trim();
    if commit_hash.is_empty() {
        return Err(AppError::InvalidInput(
            "commit hash is required for commit detail".to_string(),
        ));
    }

    let meta_args = vec![
        "show".to_string(),
        "--no-patch".to_string(),
        "--date=iso-strict".to_string(),
        "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%s%x1f%b".to_string(),
        commit_hash.to_string(),
    ];
    let meta_refs: Vec<&str> = meta_args.iter().map(String::as_str).collect();
    let meta_output = run_git(Some(repository_path), &meta_refs)?;
    let metadata = meta_output.stdout;

    let mut fields = metadata.splitn(7, '\x1f');
    let parsed_commit_hash = fields.next().unwrap_or_default().trim().to_string();
    let short_hash = fields.next().unwrap_or_default().trim().to_string();
    let author_name = fields.next().unwrap_or_default().trim().to_string();
    let author_email = fields.next().unwrap_or_default().trim().to_string();
    let authored_at = fields.next().unwrap_or_default().trim().to_string();
    let subject = fields.next().unwrap_or_default().trim().to_string();
    let body = fields.next().unwrap_or_default().trim().to_string();

    if parsed_commit_hash.is_empty() {
        return Err(AppError::Internal(
            "failed to parse commit metadata from git output".to_string(),
        ));
    }

    let stats_args = ["show", "--numstat", "--format=", commit_hash];
    let stats_output = run_git(Some(repository_path), &stats_args)?;

    let mut files = Vec::new();
    let mut additions = 0_u32;
    let mut deletions = 0_u32;

    for line in stats_output.stdout.lines() {
        let row = line.trim();
        if row.is_empty() {
            continue;
        }

        let mut parts = row.splitn(3, '\t');
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

    Ok(CommitDetailData {
        commit_hash: parsed_commit_hash,
        short_hash,
        subject,
        body,
        author_name,
        author_email,
        authored_at,
        files_changed: files.len() as u32,
        additions,
        deletions,
        files,
    })
}

fn trimmed_non_empty(value: &str) -> Option<&str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed)
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

fn list_conflicted_files(repository_path: &str) -> Result<Vec<String>, AppError> {
    let output = run_git(
        Some(repository_path),
        &["status", "--porcelain=2", "--untracked-files=no"],
    )?;

    let mut conflicted_files = Vec::<String>::new();
    let mut seen = HashSet::<String>::new();

    for line in output.stdout.lines() {
        if line.starts_with("u ") {
            let path = line.split_whitespace().last().unwrap_or_default().trim().to_string();
            if !path.is_empty() && seen.insert(path.clone()) {
                conflicted_files.push(path);
            }
            continue;
        }

        if line.starts_with("1 ") || line.starts_with("2 ") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            let xy = parts.get(1).copied().unwrap_or("??");
            let index_status = xy.chars().next();
            let worktree_status = xy.chars().nth(1);
            let is_conflicted = index_status == Some('U') || worktree_status == Some('U');

            if is_conflicted {
                let path = parts.last().copied().unwrap_or_default().trim().to_string();
                if !path.is_empty() && seen.insert(path.clone()) {
                    conflicted_files.push(path);
                }
            }
        }
    }

    conflicted_files.sort();
    Ok(conflicted_files)
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

fn build_conflict_guidance(operation: Option<&str>, in_conflict: bool) -> Vec<String> {
    if !in_conflict {
        return vec!["No conflicts detected.".to_string()];
    }

    match operation {
        Some("merge") => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git merge --continue.".to_string(),
            "Use Abort to run git merge --abort.".to_string(),
        ],
        Some("rebase") => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git rebase --continue.".to_string(),
            "Use Abort to run git rebase --abort.".to_string(),
        ],
        Some("cherry-pick") => vec![
            "Resolve conflicted files and stage the resolved versions.".to_string(),
            "Use Continue to run git cherry-pick --continue.".to_string(),
            "Use Abort to run git cherry-pick --abort.".to_string(),
        ],
        Some("revert") => vec![
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

    use uuid::Uuid;

    use super::{
        abort_conflict_resolution, build_conflict_guidance, conflict_action_args, get_commit_detail,
        get_conflict_state, get_repository_status, list_branches, list_commit_history,
        normalize_conflict_operation, stage_paths, unstage_paths,
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
            args,
            stdout,
            stderr
        );
        stdout
    }

    fn run_fixture_git_with_status(repository_path: &Path, args: &[&str]) -> (bool, String, String) {
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

    fn git_status_snapshot(repository_path: &Path) -> (String, HashMap<String, String>) {
        let output = run_fixture_git(
            repository_path,
            &["status", "--porcelain=2", "--branch", "--untracked-files=all"],
        );

        let mut branch = "detached".to_string();
        let mut files = HashMap::<String, String>::new();
        for line in output.lines() {
            if let Some(value) = line.strip_prefix("# branch.head ") {
                branch = value.to_string();
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

        (branch, files)
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
        assert_eq!(actual.files.len(), expected.1.len());

        for file in actual.files {
            let xy = expected
                .1
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

    #[test]
    fn normalizes_supported_conflict_operations() {
        assert_eq!(normalize_conflict_operation("merge"), Some("merge"));
        assert_eq!(normalize_conflict_operation(" REBASE "), Some("rebase"));
        assert_eq!(normalize_conflict_operation("cherry-pick"), Some("cherry-pick"));
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
    fn merge_guidance_mentions_continue_and_abort() {
        let guidance = build_conflict_guidance(Some("merge"), true);
        assert!(guidance.iter().any(|line| line.contains("git merge --continue")));
        assert!(guidance.iter().any(|line| line.contains("git merge --abort")));
    }

    #[test]
    fn no_conflict_guidance_reports_clean_state() {
        let guidance = build_conflict_guidance(None, false);
        assert_eq!(guidance, vec!["No conflicts detected.".to_string()]);
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
    fn fixture_commit_history_and_detail_match_git_cli() {
        let fixture = FixtureRepo::new("commit-detail");
        write_repo_file(fixture.path(), "tracked.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        write_repo_file(fixture.path(), "tracked.txt", "base\nnext\n");
        write_repo_file(fixture.path(), "second.txt", "added\n");
        commit_all(fixture.path(), "second commit");

        let head_hash = run_fixture_git(fixture.path(), &["rev-parse", "HEAD"]);
        let detail =
            get_commit_detail(fixture.path_str(), &head_hash).expect("expected commit detail result");
        let history = list_commit_history(fixture.path_str(), 10, None)
            .expect("expected commit history result");

        let expected_subject = run_fixture_git(
            fixture.path(),
            &["show", "--no-patch", "--pretty=format:%s", head_hash.as_str()],
        );
        let expected_numstat =
            run_fixture_git(fixture.path(), &["show", "--numstat", "--format=", head_hash.as_str()]);
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

        let merge_attempt = run_fixture_git_with_status(fixture.path(), &["merge", "feature/conflict"]);
        assert!(
            !merge_attempt.0,
            "expected merge to fail with conflict, but it succeeded"
        );

        let conflict_state = get_conflict_state(fixture.path_str())
            .expect("expected provider conflict state result");
        assert!(conflict_state.in_conflict);
        assert_eq!(conflict_state.operation.as_deref(), Some("merge"));

        let expected_files_output = run_fixture_git(
            fixture.path(),
            &["diff", "--name-only", "--diff-filter=U"],
        );
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

        let post_state =
            get_conflict_state(fixture.path_str()).expect("expected post-abort conflict state");
        assert!(!post_state.in_conflict);
        assert!(post_state.operation.is_none());
    }
}
