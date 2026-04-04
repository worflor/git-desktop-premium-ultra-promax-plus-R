use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use crate::errors::AppError;
use crate::models::operations::{DiffHunkData, FileDiffChunkData, FileDiffManifestData};
use crate::services::{git_provider, logging_service, pretext_service, telemetry_service};

const DEFAULT_CHUNK_SIZE_BYTES: usize = 64 * 1024;
const MIN_CHUNK_SIZE_BYTES: usize = 4 * 1024;
const MAX_CHUNK_SIZE_BYTES: usize = 512 * 1024;
const MAX_DIFF_BYTES: usize = 20 * 1024 * 1024;
const DIFF_CACHE_TTL: Duration = Duration::from_secs(10 * 60);
const MAX_RETAINED_DIFFS: usize = 24;
const DEFAULT_MODE_A_MAX_CHANGED_LINES: u32 = 15_000;
const DEFAULT_MODE_A_MAX_PAYLOAD_BYTES: usize = 3 * 1024 * 1024;

pub struct PrepareFileDiffChunksInput<'a> {
    pub repository_path: &'a str,
    pub path: &'a str,
    pub staged: bool,
    pub context_lines: usize,
    pub chunk_size_bytes: Option<usize>,
    pub layout_width_px: Option<u32>,
    pub font_profile: Option<&'a str>,
    pub line_height_px: Option<u32>,
}

#[derive(Debug, Clone)]
struct DiffPayloadRecord {
    repository_path: String,
    created_at: Instant,
    expires_at: Instant,
    manifest: FileDiffManifestData,
    chunks: Vec<String>,
}

#[derive(Debug)]
struct DiffAnalysis {
    total_lines: u32,
    additions: u32,
    deletions: u32,
    hunks: Vec<DiffHunkData>,
    chunks: Vec<String>,
}

#[derive(Debug)]
struct HunkDraft {
    hunk_index: u32,
    header: String,
    old_start: u32,
    old_lines: u32,
    new_start: u32,
    new_lines: u32,
    added_lines: u32,
    deleted_lines: u32,
}

pub fn prepare_file_diff_chunks(
    input: PrepareFileDiffChunksInput<'_>,
) -> Result<FileDiffManifestData, AppError> {
    let started_at = Instant::now();
    let request_id = logging_service::current_request_context();

    let result = (|| {
        let chunk_size = input
            .chunk_size_bytes
            .unwrap_or(DEFAULT_CHUNK_SIZE_BYTES)
            .clamp(MIN_CHUNK_SIZE_BYTES, MAX_CHUNK_SIZE_BYTES);

        let diff_text = git_provider::get_file_diff(
            input.repository_path,
            input.path,
            input.staged,
            input.context_lines,
        )?;
        let total_bytes = diff_text.len();
        if total_bytes > MAX_DIFF_BYTES {
            return Err(AppError::DiffTooLarge {
                bytes: total_bytes as u64,
                max_bytes: MAX_DIFF_BYTES as u64,
            });
        }

        let layout_options = pretext_service::LayoutOptions::from_command_inputs(
            input.layout_width_px,
            input.font_profile,
            input.line_height_px,
        );
        let diff_id = build_diff_id(
            input.repository_path,
            input.path.trim(),
            input.staged,
            input.context_lines,
            chunk_size,
            &layout_options,
            diff_text.as_str(),
        );

        let now = Instant::now();
        let mut payloads = diff_payload_cache()
            .lock()
            .map_err(|_| AppError::Internal("failed to lock diff payload cache".to_string()))?;
        prune_diff_payloads(&mut payloads, now);
        if let Some(record) = payloads.get_mut(diff_id.as_str()) {
            record.created_at = now;
            record.expires_at = now + DIFF_CACHE_TTL;
            return Ok(record.manifest.clone());
        }

        let analysis = analyze_diff_text(diff_text.as_str(), chunk_size);
        let layout = pretext_service::prepare_layout(&diff_id, &diff_text, &layout_options);

        let mode_threshold_max_changed_lines = mode_a_max_changed_lines();
        let mode_threshold_max_payload_bytes = mode_a_max_payload_bytes();
        let changed_lines = analysis.additions.saturating_add(analysis.deletions);
        let renderer_mode = select_renderer_mode(
            changed_lines,
            total_bytes,
            layout.fallback_activated,
            mode_threshold_max_changed_lines,
            mode_threshold_max_payload_bytes,
        );

        let manifest = FileDiffManifestData {
            diff_id: diff_id.clone(),
            path: input.path.trim().to_string(),
            staged: input.staged,
            context_lines: input.context_lines as u32,
            chunk_size_bytes: chunk_size as u32,
            chunk_count: analysis.chunks.len() as u32,
            total_bytes: total_bytes as u32,
            total_lines: analysis.total_lines,
            changed_lines,
            additions: analysis.additions,
            deletions: analysis.deletions,
            hunk_count: analysis.hunks.len() as u32,
            renderer_mode,
            mode_threshold_max_changed_lines,
            mode_threshold_max_payload_bytes: mode_threshold_max_payload_bytes as u32,
            pretext_version: layout.pretext_version,
            pretext_prepare_ms: layout.prepare_ms,
            pretext_layout_ms: layout.layout_ms,
            fallback_activated: layout.fallback_activated,
            fallback_reason: layout.fallback_reason,
            visual_row_count: layout.visual_row_count,
            layout_cache_key: layout.layout_cache_key,
            initial_chunk_text: analysis.chunks.first().cloned().unwrap_or_default(),
            hunks: analysis.hunks,
        };

        payloads.insert(
            diff_id,
            DiffPayloadRecord {
                repository_path: input.repository_path.to_string(),
                created_at: now,
                expires_at: now + DIFF_CACHE_TTL,
                manifest: manifest.clone(),
                chunks: analysis.chunks,
            },
        );
        trim_diff_payloads(&mut payloads);

        Ok(manifest)
    })();

    let mut error_code = None::<String>;
    let message = match &result {
        Ok(manifest) => Some(format!(
            "renderer_mode={} payload_bytes={} changed_lines={} hunk_count={} chunk_count={} pretext_version={} prepare_ms={} layout_ms={} fallback_activated={} visual_rows={}",
            manifest.renderer_mode,
            manifest.total_bytes,
            manifest.changed_lines,
            manifest.hunk_count,
            manifest.chunk_count,
            manifest.pretext_version,
            manifest.pretext_prepare_ms,
            manifest.pretext_layout_ms,
            manifest.fallback_activated,
            manifest.visual_row_count
        )),
        Err(error) => {
            error_code = Some(error.to_command_error().code);
            Some(error.to_string())
        }
    };

    let duration_ms = started_at.elapsed().as_millis() as u64;
    let _ = telemetry_service::record_command_sample(
        "diff",
        "diff.prepare_file_chunks",
        result.is_ok(),
        duration_ms,
        error_code.as_deref(),
    );

    if let Ok(manifest) = &result {
        let _ = telemetry_service::record_command_sample(
            "diff",
            "diff.pretext.prepare",
            true,
            manifest.pretext_prepare_ms,
            None,
        );
        let _ = telemetry_service::record_command_sample(
            "diff",
            "diff.pretext.layout",
            true,
            manifest.pretext_layout_ms,
            None,
        );
        let _ = telemetry_service::record_command_sample(
            "diff",
            "diff.pretext.fallback",
            !manifest.fallback_activated,
            duration_ms,
            if manifest.fallback_activated {
                Some("diff.pretext_fallback")
            } else {
                None
            },
        );
    }

    let _ = logging_service::record_operation_span(
        "diff",
        "diff.prepare_file_chunks",
        request_id.as_deref(),
        started_at,
        result.is_ok(),
        error_code.as_deref(),
        message.as_deref(),
    );

    result
}

pub fn get_file_diff_chunk(
    diff_id: &str,
    chunk_index: usize,
) -> Result<FileDiffChunkData, AppError> {
    let started_at = Instant::now();
    let request_id = logging_service::current_request_context();

    let result = (|| {
        let diff_id = diff_id.trim();
        if diff_id.is_empty() {
            return Err(AppError::InvalidInput(
                "diff id is required for chunk retrieval".to_string(),
            ));
        }

        let now = Instant::now();
        let mut payloads = diff_payload_cache()
            .lock()
            .map_err(|_| AppError::Internal("failed to lock diff payload cache".to_string()))?;
        prune_diff_payloads(&mut payloads, now);

        let record = payloads
            .get(diff_id)
            .ok_or_else(|| AppError::InvalidInput(format!("unknown diff id: {diff_id}")))?;

        if chunk_index >= record.chunks.len() {
            return Err(AppError::InvalidInput(format!(
                "chunk index {chunk_index} is out of range for diff {diff_id}"
            )));
        }

        Ok(FileDiffChunkData {
            diff_id: diff_id.to_string(),
            chunk_index: chunk_index as u32,
            chunk_count: record.manifest.chunk_count,
            has_more: chunk_index + 1 < record.chunks.len(),
            chunk_text: record.chunks[chunk_index].clone(),
        })
    })();

    let mut error_code = None::<String>;
    let message = match &result {
        Ok(chunk) => Some(format!(
            "renderer_mode=backend-chunking chunk_index={} chunk_count={} has_more={}",
            chunk.chunk_index, chunk.chunk_count, chunk.has_more
        )),
        Err(error) => {
            error_code = Some(error.to_command_error().code);
            Some(error.to_string())
        }
    };

    let duration_ms = started_at.elapsed().as_millis() as u64;
    let _ = telemetry_service::record_command_sample(
        "diff",
        "diff.get_file_chunk",
        result.is_ok(),
        duration_ms,
        error_code.as_deref(),
    );
    let _ = logging_service::record_operation_span(
        "diff",
        "diff.get_file_chunk",
        request_id.as_deref(),
        started_at,
        result.is_ok(),
        error_code.as_deref(),
        message.as_deref(),
    );

    result
}

pub fn invalidate_repository(repository_path: &str) {
    if let Ok(mut payloads) = diff_payload_cache().lock() {
        payloads.retain(|_, record| record.repository_path != repository_path);
    }
}

fn diff_payload_cache() -> &'static Mutex<HashMap<String, DiffPayloadRecord>> {
    static CACHE: OnceLock<Mutex<HashMap<String, DiffPayloadRecord>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn prune_diff_payloads(payloads: &mut HashMap<String, DiffPayloadRecord>, now: Instant) {
    payloads.retain(|_, record| record.expires_at > now);
}

fn trim_diff_payloads(payloads: &mut HashMap<String, DiffPayloadRecord>) {
    if payloads.len() <= MAX_RETAINED_DIFFS {
        return;
    }

    let mut records = payloads
        .iter()
        .map(|(diff_id, record)| (diff_id.clone(), record.created_at))
        .collect::<Vec<(String, Instant)>>();
    records.sort_unstable_by_key(|(_, created_at)| *created_at);

    let drop_count = records.len().saturating_sub(MAX_RETAINED_DIFFS);
    for (diff_id, _) in records.into_iter().take(drop_count) {
        payloads.remove(diff_id.as_str());
    }
}

fn build_diff_id(
    repository_path: &str,
    path: &str,
    staged: bool,
    context_lines: usize,
    chunk_size: usize,
    layout_options: &pretext_service::LayoutOptions,
    diff_text: &str,
) -> String {
    let mut hasher = DefaultHasher::new();
    repository_path.hash(&mut hasher);
    path.hash(&mut hasher);
    staged.hash(&mut hasher);
    context_lines.hash(&mut hasher);
    chunk_size.hash(&mut hasher);
    layout_options.width_px.hash(&mut hasher);
    layout_options.font_profile.hash(&mut hasher);
    layout_options.line_height_px.hash(&mut hasher);
    diff_text.hash(&mut hasher);
    format!("diff:{:016x}", hasher.finish())
}

fn analyze_diff_text(diff_text: &str, chunk_size: usize) -> DiffAnalysis {
    if diff_text.is_empty() {
        return DiffAnalysis {
            total_lines: 0,
            additions: 0,
            deletions: 0,
            hunks: Vec::new(),
            chunks: vec![String::new()],
        };
    }

    let mut additions = 0_u32;
    let mut deletions = 0_u32;
    let mut total_lines = 0_u32;
    let mut hunks = Vec::<DiffHunkData>::new();
    let mut current_hunk = None::<HunkDraft>;
    let mut chunks = Vec::<String>::new();
    let mut current_chunk = String::new();

    for line in diff_text.split_inclusive('\n') {
        total_lines = total_lines.saturating_add(1);

        if let Some((old_start, old_lines, new_start, new_lines)) = parse_hunk_header(line) {
            if let Some(previous) = current_hunk.take() {
                hunks.push(finish_hunk(previous));
            }
            current_hunk = Some(HunkDraft {
                hunk_index: hunks.len() as u32,
                header: line.trim_end_matches('\n').to_string(),
                old_start,
                old_lines,
                new_start,
                new_lines,
                added_lines: 0,
                deleted_lines: 0,
            });
        } else if line.starts_with('+') && !line.starts_with("+++") {
            additions = additions.saturating_add(1);
            if let Some(active) = current_hunk.as_mut() {
                active.added_lines = active.added_lines.saturating_add(1);
            }
        } else if line.starts_with('-') && !line.starts_with("---") {
            deletions = deletions.saturating_add(1);
            if let Some(active) = current_hunk.as_mut() {
                active.deleted_lines = active.deleted_lines.saturating_add(1);
            }
        }

        append_chunk(&mut chunks, &mut current_chunk, line, chunk_size);
    }

    if !diff_text.ends_with('\n') {
        total_lines = total_lines.saturating_add(1);
    }

    if let Some(last) = current_hunk.take() {
        hunks.push(finish_hunk(last));
    }

    if !current_chunk.is_empty() {
        chunks.push(current_chunk);
    }

    if chunks.is_empty() {
        chunks.push(String::new());
    }

    DiffAnalysis {
        total_lines,
        additions,
        deletions,
        hunks,
        chunks,
    }
}

fn append_chunk(
    chunks: &mut Vec<String>,
    current_chunk: &mut String,
    line: &str,
    chunk_size: usize,
) {
    if current_chunk.len() + line.len() <= chunk_size {
        current_chunk.push_str(line);
        return;
    }

    if !current_chunk.is_empty() {
        chunks.push(std::mem::take(current_chunk));
    }

    if line.len() <= chunk_size {
        current_chunk.push_str(line);
        return;
    }

    let mut line_chunk = String::new();
    for ch in line.chars() {
        if line_chunk.len() + ch.len_utf8() > chunk_size && !line_chunk.is_empty() {
            chunks.push(std::mem::take(&mut line_chunk));
        }
        line_chunk.push(ch);
    }

    if !line_chunk.is_empty() {
        *current_chunk = line_chunk;
    }
}

fn finish_hunk(hunk: HunkDraft) -> DiffHunkData {
    DiffHunkData {
        hunk_index: hunk.hunk_index,
        header: hunk.header,
        old_start: hunk.old_start,
        old_lines: hunk.old_lines,
        new_start: hunk.new_start,
        new_lines: hunk.new_lines,
        added_lines: hunk.added_lines,
        deleted_lines: hunk.deleted_lines,
    }
}

fn mode_a_max_changed_lines() -> u32 {
    std::env::var("GDPU_DIFF_MODE_A_MAX_CHANGED_LINES")
        .ok()
        .and_then(|value| value.trim().parse::<u32>().ok())
        .filter(|value| *value >= 100)
        .unwrap_or(DEFAULT_MODE_A_MAX_CHANGED_LINES)
}

fn mode_a_max_payload_bytes() -> usize {
    std::env::var("GDPU_DIFF_MODE_A_MAX_PAYLOAD_BYTES")
        .ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
        .filter(|value| *value >= 64 * 1024)
        .unwrap_or(DEFAULT_MODE_A_MAX_PAYLOAD_BYTES)
}

fn select_renderer_mode(
    changed_lines: u32,
    payload_bytes: usize,
    fallback_activated: bool,
    mode_a_max_changed_lines: u32,
    mode_a_max_payload_bytes: usize,
) -> String {
    if fallback_activated {
        return "fallback".to_string();
    }

    if changed_lines < mode_a_max_changed_lines && payload_bytes < mode_a_max_payload_bytes {
        return "dom".to_string();
    }

    "canvas".to_string()
}

#[cfg(test)]
fn split_text_chunks(value: &str, chunk_size: usize) -> Vec<String> {
    analyze_diff_text(value, chunk_size).chunks
}

#[cfg(test)]
fn count_changed_lines(diff_text: &str) -> (u32, u32) {
    let analysis = analyze_diff_text(diff_text, DEFAULT_CHUNK_SIZE_BYTES);
    (analysis.additions, analysis.deletions)
}

#[cfg(test)]
fn parse_hunks(diff_text: &str) -> Vec<DiffHunkData> {
    analyze_diff_text(diff_text, DEFAULT_CHUNK_SIZE_BYTES).hunks
}

fn parse_hunk_header(line: &str) -> Option<(u32, u32, u32, u32)> {
    if !line.starts_with("@@ ") {
        return None;
    }

    let closing = line.find(" @@")?;
    let descriptor = line.get(3..closing)?.trim();
    let mut parts = descriptor.split_whitespace();

    let old = parts.next()?;
    let new = parts.next()?;

    let (old_start, old_lines) = parse_hunk_range(old, '-')?;
    let (new_start, new_lines) = parse_hunk_range(new, '+')?;

    Some((old_start, old_lines, new_start, new_lines))
}

fn parse_hunk_range(value: &str, prefix: char) -> Option<(u32, u32)> {
    let body = value.strip_prefix(prefix)?;
    let mut sections = body.splitn(2, ',');
    let start = sections.next()?.parse::<u32>().ok()?;
    let count = sections
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .unwrap_or(1);
    Some((start, count))
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use std::time::{Duration, Instant};

    use uuid::Uuid;

    use super::{
        count_changed_lines, diff_payload_cache, get_file_diff_chunk, parse_hunks,
        prepare_file_diff_chunks, split_text_chunks, PrepareFileDiffChunksInput,
        MAX_RETAINED_DIFFS,
    };

    struct FixtureRepo {
        path: PathBuf,
    }

    impl FixtureRepo {
        fn new(name: &str) -> Self {
            let path =
                std::env::temp_dir().join(format!("gdpu-diff-fixture-{name}-{}", Uuid::new_v4()));
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
        let output = Command::new("git")
            .args(args)
            .current_dir(repository_path)
            .output()
            .expect("failed to execute git command for fixture");

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        assert!(
            output.status.success(),
            "git command failed for args {:?}\nstdout:\n{}\nstderr:\n{}",
            args,
            stdout,
            stderr
        );

        stdout
    }

    fn write_repo_file(repository_path: &Path, relative_path: &str, contents: &str) {
        let full_path = repository_path.join(relative_path);
        if let Some(parent) = full_path.parent() {
            fs::create_dir_all(parent).expect("failed to create fixture parent directories");
        }
        fs::write(full_path, contents).expect("failed to write fixture file");
    }

    fn commit_all(repository_path: &Path, message: &str) {
        run_fixture_git(repository_path, &["add", "--all"]);
        run_fixture_git(repository_path, &["commit", "-m", message]);
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
    fn split_text_chunks_preserves_text_and_limits_chunk_size() {
        let payload = "alpha\nbeta\ngamma\ndelta\n";
        let chunks = split_text_chunks(payload, 8);

        assert!(chunks.iter().all(|chunk| chunk.len() <= 8));
        assert_eq!(chunks.join(""), payload);
    }

    #[test]
    fn count_changed_lines_ignores_patch_headers() {
        let diff = "diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n-line one\n+line one updated\n line two\n";
        let (additions, deletions) = count_changed_lines(diff);

        assert_eq!(additions, 1);
        assert_eq!(deletions, 1);
    }

    #[test]
    fn parse_hunks_extracts_header_ranges_and_line_counts() {
        let diff = "@@ -10,3 +10,4 @@ fn main()\n line1\n-line2\n+line2a\n+line2b\n line3\n@@ -20 +21 @@ fn helper()\n-old\n+new\n";
        let hunks = parse_hunks(diff);

        assert_eq!(hunks.len(), 2);
        assert_eq!(hunks[0].old_start, 10);
        assert_eq!(hunks[0].old_lines, 3);
        assert_eq!(hunks[0].new_start, 10);
        assert_eq!(hunks[0].new_lines, 4);
        assert_eq!(hunks[0].added_lines, 2);
        assert_eq!(hunks[0].deleted_lines, 1);

        assert_eq!(hunks[1].old_start, 20);
        assert_eq!(hunks[1].old_lines, 1);
        assert_eq!(hunks[1].new_start, 21);
        assert_eq!(hunks[1].new_lines, 1);
        assert_eq!(hunks[1].added_lines, 1);
        assert_eq!(hunks[1].deleted_lines, 1);
    }

    #[test]
    fn diff_cache_retrieval_respects_expiry_pruning() {
        let fixture = FixtureRepo::new("cache-expiry");
        write_repo_file(
            fixture.path(),
            "src/app.rs",
            "fn main() {\n    println!(\"base\");\n}\n",
        );
        commit_all(fixture.path(), "base commit");

        write_repo_file(
            fixture.path(),
            "src/app.rs",
            "fn main() {\n    println!(\"updated\");\n}\n",
        );

        let manifest = prepare_file_diff_chunks(PrepareFileDiffChunksInput {
            repository_path: fixture.path_str(),
            path: "src/app.rs",
            staged: false,
            context_lines: 3,
            chunk_size_bytes: Some(16 * 1024),
            layout_width_px: None,
            font_profile: None,
            line_height_px: None,
        })
        .expect("expected diff manifest generation to succeed");

        let first_chunk = {
            let payloads = diff_payload_cache()
                .lock()
                .expect("expected diff payload lock to be available");
            payloads
                .get(&manifest.diff_id)
                .and_then(|record| record.chunks.first().cloned())
                .expect("expected cached first diff chunk")
        };
        assert_eq!(manifest.initial_chunk_text, first_chunk);

        {
            let mut payloads = diff_payload_cache()
                .lock()
                .expect("expected diff payload lock to be available");
            let record = payloads
                .get_mut(&manifest.diff_id)
                .expect("expected payload record for manifest id");
            record.expires_at = Instant::now() - Duration::from_secs(1);
        }

        let error = get_file_diff_chunk(manifest.diff_id.as_str(), 0)
            .expect_err("expected expired payload to be pruned before chunk retrieval");
        assert!(error.to_string().contains("unknown diff id"));
    }

    #[test]
    fn diff_cache_evicts_oldest_records_when_capacity_exceeded() {
        let fixture = FixtureRepo::new("cache-eviction");
        write_repo_file(fixture.path(), "src/cache.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        let mut first_diff_id = None::<String>;

        for index in 0..(MAX_RETAINED_DIFFS + 4) {
            write_repo_file(
                fixture.path(),
                "src/cache.txt",
                format!("base\nupdate-{index}\n").as_str(),
            );
            let manifest = prepare_file_diff_chunks(PrepareFileDiffChunksInput {
                repository_path: fixture.path_str(),
                path: "src/cache.txt",
                staged: false,
                context_lines: 3,
                chunk_size_bytes: Some(8 * 1024),
                layout_width_px: None,
                font_profile: None,
                line_height_px: None,
            })
            .expect("expected diff manifest generation to succeed");

            if first_diff_id.is_none() {
                first_diff_id = Some(manifest.diff_id.clone());
            }
        }

        let payloads = diff_payload_cache()
            .lock()
            .expect("expected diff payload lock to be available");
        assert!(payloads.len() <= MAX_RETAINED_DIFFS);

        let oldest = first_diff_id.expect("expected first diff id to exist");
        assert!(
            !payloads.contains_key(oldest.as_str()),
            "oldest payload should be evicted after capacity limit"
        );
    }

    #[test]
    fn identical_diff_requests_reuse_stable_diff_id() {
        let fixture = FixtureRepo::new("stable-id");
        write_repo_file(fixture.path(), "src/reused.txt", "base\n");
        commit_all(fixture.path(), "base commit");
        write_repo_file(fixture.path(), "src/reused.txt", "base\nchanged\n");

        let first = prepare_file_diff_chunks(PrepareFileDiffChunksInput {
            repository_path: fixture.path_str(),
            path: "src/reused.txt",
            staged: false,
            context_lines: 3,
            chunk_size_bytes: Some(16 * 1024),
            layout_width_px: Some(1080),
            font_profile: Some("ui-mono-13"),
            line_height_px: Some(18),
        })
        .expect("expected first diff manifest");

        let second = prepare_file_diff_chunks(PrepareFileDiffChunksInput {
            repository_path: fixture.path_str(),
            path: "src/reused.txt",
            staged: false,
            context_lines: 3,
            chunk_size_bytes: Some(16 * 1024),
            layout_width_px: Some(1080),
            font_profile: Some("ui-mono-13"),
            line_height_px: Some(18),
        })
        .expect("expected second diff manifest");

        assert_eq!(first.diff_id, second.diff_id);
    }

    #[test]
    fn perf_budget_diff_prepare_p95_within_threshold() {
        let fixture = FixtureRepo::new("prepare-perf-budget");
        write_repo_file(fixture.path(), "src/large.txt", "base\n");
        commit_all(fixture.path(), "base commit");

        let large_payload = (0..7000)
            .map(|index| format!("line-{index:05} = {}", "x".repeat(48)))
            .collect::<Vec<String>>()
            .join("\n");
        write_repo_file(fixture.path(), "src/large.txt", large_payload.as_str());

        let Some(budget_ms) = perf_budget_from_env("GDPU_DIFF_PREPARE_P95_BUDGET_MS") else {
            eprintln!(
                "skipping diff prepare perf budget test: GDPU_DIFF_PREPARE_P95_BUDGET_MS is not set"
            );
            return;
        };

        for _ in 0..3 {
            let _ = prepare_file_diff_chunks(PrepareFileDiffChunksInput {
                repository_path: fixture.path_str(),
                path: "src/large.txt",
                staged: false,
                context_lines: 3,
                chunk_size_bytes: Some(64 * 1024),
                layout_width_px: Some(1080),
                font_profile: Some("ui-mono-13"),
                line_height_px: Some(18),
            })
            .expect("expected warm-up diff preparation to succeed");
        }

        let mut durations_ms = Vec::<u128>::new();
        for _ in 0..20 {
            let started_at = Instant::now();
            let _ = prepare_file_diff_chunks(PrepareFileDiffChunksInput {
                repository_path: fixture.path_str(),
                path: "src/large.txt",
                staged: false,
                context_lines: 3,
                chunk_size_bytes: Some(64 * 1024),
                layout_width_px: Some(1080),
                font_profile: Some("ui-mono-13"),
                line_height_px: Some(18),
            })
            .expect("expected diff preparation benchmark call to succeed");
            durations_ms.push(started_at.elapsed().as_millis());
        }

        let p95_ms = percentile_duration_ms(&durations_ms, 95);
        assert!(
            p95_ms <= budget_ms,
            "diff prepare p95 exceeded budget: p95={}ms budget={}ms samples={:?}",
            p95_ms,
            budget_ms,
            durations_ms
        );
    }
}
