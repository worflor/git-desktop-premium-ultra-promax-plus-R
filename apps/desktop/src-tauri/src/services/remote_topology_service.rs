use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::services::{git_provider, local_store};

const REMOTE_TOPOLOGY_CACHE_TTL: Duration = Duration::from_secs(15);

#[derive(Debug, Clone)]
pub struct RepositoryRemote {
    pub remote: String,
    pub url: String,
    pub protocol: String,
    pub host: Option<String>,
    pub host_kind: String,
    pub normalized_path: Option<String>,
}

#[derive(Debug, Clone)]
struct RemoteTopologyCacheEntry {
    captured_at: Instant,
    remotes: Vec<RepositoryRemote>,
}

pub fn list_repository_remotes(repository_path: &str) -> Result<Vec<RepositoryRemote>, AppError> {
    if let Ok(cache) = remote_topology_cache().lock() {
        if let Some(entry) = cache.get(repository_path) {
            if entry.captured_at.elapsed() <= REMOTE_TOPOLOGY_CACHE_TTL {
                return Ok(entry.remotes.clone());
            }
        }
    }

    local_store::ensure_git_repository(repository_path)?;
    let output = git_provider::run_git(Some(repository_path), &["remote", "-v"])?;

    let mut remotes = Vec::<RepositoryRemote>::new();
    let mut seen = HashSet::<String>::new();
    for line in output.stdout.lines() {
        if !line.contains("(fetch)") {
            continue;
        }

        let mut fields = line.split_whitespace();
        let remote = fields.next().unwrap_or_default().trim().to_string();
        let url = fields.next().unwrap_or_default().trim().to_string();
        if remote.is_empty() || url.is_empty() {
            continue;
        }

        let dedupe_key = format!("{remote}|{url}");
        if !seen.insert(dedupe_key) {
            continue;
        }

        let protocol = detect_protocol(url.as_str());
        let parsed = parse_remote_url(url.as_str());
        let host = parsed.as_ref().map(|(host, _)| host.clone());
        let normalized_path = parsed.as_ref().map(|(_, path)| path.clone());
        let host_kind = host
            .as_deref()
            .map(detect_host_kind_from_host)
            .unwrap_or_else(|| detect_host_kind_from_url(url.as_str()))
            .to_string();

        remotes.push(RepositoryRemote {
            remote,
            url,
            protocol,
            host,
            host_kind,
            normalized_path,
        });
    }

    if let Ok(mut cache) = remote_topology_cache().lock() {
        cache.insert(
            repository_path.to_string(),
            RemoteTopologyCacheEntry {
                captured_at: Instant::now(),
                remotes: remotes.clone(),
            },
        );
    }

    Ok(remotes)
}

pub fn resolve_remote_for_host_kind(
    repository_path: &str,
    host_kind: &str,
) -> Result<RepositoryRemote, AppError> {
    let remotes = list_repository_remotes(repository_path)?;
    remotes
        .into_iter()
        .find(|remote| remote.host_kind == host_kind)
        .ok_or_else(|| AppError::ForgeAdapterUnavailable(host_kind.to_string()))
}

#[allow(dead_code)]
pub fn invalidate_repository(repository_path: &str) {
    if let Ok(mut cache) = remote_topology_cache().lock() {
        cache.remove(repository_path);
    }
}

pub fn detect_protocol(url: &str) -> String {
    if url.starts_with("git@") || url.starts_with("ssh://") {
        return "ssh".to_string();
    }
    if url.starts_with("https://") || url.starts_with("http://") {
        return "https".to_string();
    }
    if url.starts_with("file://")
        || url.starts_with('/')
        || url.starts_with("./")
        || url.starts_with("../")
        || url.contains(":\\")
    {
        return "local".to_string();
    }
    "other".to_string()
}

pub fn detect_host_kind_from_url(url: &str) -> &'static str {
    let normalized = url.to_ascii_lowercase();
    if normalized.contains("github.com") || normalized.contains("github") {
        return "github";
    }
    if normalized.contains("gitlab.com") || normalized.contains("gitlab") {
        return "gitlab";
    }
    if normalized.contains("bitbucket.org") || normalized.contains("bitbucket") {
        return "bitbucket";
    }
    if normalized.starts_with("file://")
        || normalized.starts_with('/')
        || normalized.starts_with("./")
        || normalized.starts_with("../")
        || normalized.contains(":\\")
    {
        return "local";
    }
    "generic"
}

pub fn detect_host_kind_from_host(host: &str) -> &'static str {
    let normalized = host.to_ascii_lowercase();
    if normalized.contains("github") {
        return "github";
    }
    if normalized.contains("gitlab") {
        return "gitlab";
    }
    if normalized.contains("bitbucket") {
        return "bitbucket";
    }
    "generic"
}

pub fn parse_remote_url(value: &str) -> Option<(String, String)> {
    let trimmed = value.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return None;
    }

    if let Some(rest) = trimmed.strip_prefix("git@") {
        let (host, path) = rest.split_once(':')?;
        return Some((
            host.trim().to_ascii_lowercase(),
            normalize_remote_path(path),
        ));
    }

    if let Some((_, rest)) = trimmed.split_once("://") {
        let rest = rest.trim();
        let (host_part, path_part) = rest.split_once('/')?;
        let host = host_part.rsplit_once('@').map(|(_, value)| value).unwrap_or(host_part);
        return Some((
            host.trim().to_ascii_lowercase(),
            normalize_remote_path(path_part),
        ));
    }

    None
}

fn normalize_remote_path(value: &str) -> String {
    value
        .trim()
        .trim_start_matches('/')
        .trim_end_matches('/')
        .trim_end_matches(".git")
        .to_string()
}

fn remote_topology_cache() -> &'static Mutex<HashMap<String, RemoteTopologyCacheEntry>> {
    static CACHE: OnceLock<Mutex<HashMap<String, RemoteTopologyCacheEntry>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

#[cfg(test)]
mod tests {
    use super::{
        detect_host_kind_from_host, detect_host_kind_from_url, detect_protocol, parse_remote_url,
    };

    #[test]
    fn parse_remote_url_supports_https_and_ssh() {
        let https = parse_remote_url("https://gitlab.com/group/project.git")
            .expect("expected https remote to parse");
        assert_eq!(https.0, "gitlab.com");
        assert_eq!(https.1, "group/project");

        let ssh = parse_remote_url("git@bitbucket.org:workspace/repo.git")
            .expect("expected ssh remote to parse");
        assert_eq!(ssh.0, "bitbucket.org");
        assert_eq!(ssh.1, "workspace/repo");
    }

    #[test]
    fn detect_host_kind_classifies_supported_hosts() {
        assert_eq!(detect_host_kind_from_host("gitlab.com"), "gitlab");
        assert_eq!(detect_host_kind_from_host("bitbucket.org"), "bitbucket");
        assert_eq!(detect_host_kind_from_host("github.com"), "github");
        assert_eq!(detect_host_kind_from_host("example.com"), "generic");
    }

    #[test]
    fn detect_host_kind_from_url_handles_local_paths() {
        assert_eq!(detect_host_kind_from_url("file:///tmp/repo"), "local");
        assert_eq!(detect_host_kind_from_url("../relative/repo"), "local");
        assert_eq!(detect_host_kind_from_url("ssh://example.com/repo.git"), "generic");
    }

    #[test]
    fn detect_protocol_classifies_transport() {
        assert_eq!(detect_protocol("git@github.com:owner/repo.git"), "ssh");
        assert_eq!(detect_protocol("https://github.com/owner/repo.git"), "https");
        assert_eq!(detect_protocol("file:///tmp/repo"), "local");
        assert_eq!(detect_protocol("custom://repo"), "other");
    }
}
