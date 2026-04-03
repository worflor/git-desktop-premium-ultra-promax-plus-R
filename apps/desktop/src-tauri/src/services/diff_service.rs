use std::time::{Duration, Instant};

use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{DiffHunkData, FileDiffChunkData, FileDiffManifestData};
use crate::runtime::state::{AppState, DiffPayloadRecord};
use crate::services::{git_provider, logging_service, telemetry_service};

const DEFAULT_CHUNK_SIZE_BYTES: usize = 64 * 1024;
const MIN_CHUNK_SIZE_BYTES: usize = 4 * 1024;
const MAX_CHUNK_SIZE_BYTES: usize = 512 * 1024;
const MAX_DIFF_BYTES: usize = 20 * 1024 * 1024;
const DIFF_CACHE_TTL: Duration = Duration::from_secs(10 * 60);
const MAX_RETAINED_DIFFS: usize = 24;

pub fn prepare_file_diff_chunks(
    state: &AppState,
    repository_path: &str,
    path: &str,
    staged: bool,
    context_lines: usize,
    chunk_size_bytes: Option<usize>,
) -> Result<FileDiffManifestData, AppError> {
    let started_at = Instant::now();
    let request_id = logging_service::current_request_context();

    let result = (|| {
        let chunk_size = chunk_size_bytes
            .unwrap_or(DEFAULT_CHUNK_SIZE_BYTES)
            .clamp(MIN_CHUNK_SIZE_BYTES, MAX_CHUNK_SIZE_BYTES);

        let diff_text = git_provider::get_file_diff(repository_path, path, staged, context_lines)?;
        let total_bytes = diff_text.len();
        if total_bytes > MAX_DIFF_BYTES {
            return Err(AppError::DiffTooLarge {
                bytes: total_bytes as u64,
                max_bytes: MAX_DIFF_BYTES as u64,
            });
        }

        let hunks = parse_hunks(&diff_text);
        let (additions, deletions) = count_changed_lines(&diff_text);
        let chunks = split_text_chunks(&diff_text, chunk_size);
        let diff_id = Uuid::new_v4().to_string();

        let manifest = FileDiffManifestData {
            diff_id: diff_id.clone(),
            path: path.trim().to_string(),
            staged,
            context_lines: context_lines as u32,
            chunk_size_bytes: chunk_size as u32,
            chunk_count: chunks.len() as u32,
            total_bytes: total_bytes as u32,
            total_lines: diff_text.lines().count() as u32,
            changed_lines: additions.saturating_add(deletions),
            additions,
            deletions,
            hunk_count: hunks.len() as u32,
            hunks,
        };

        let now = Instant::now();
        let mut payloads = state
            .diff_payloads
            .lock()
            .map_err(|_| AppError::Internal("failed to lock diff payload cache".to_string()))?;

        prune_diff_payloads(&mut payloads, now);
        payloads.insert(
            diff_id,
            DiffPayloadRecord {
                created_at: now,
                expires_at: now + DIFF_CACHE_TTL,
                manifest: manifest.clone(),
                chunks,
            },
        );

        trim_diff_payloads(&mut payloads);

        Ok(manifest)
    })();

    let mut error_code = None::<String>;
    let message = match &result {
        Ok(manifest) => Some(format!(
            "renderer_mode=backend-chunking payload_bytes={} changed_lines={} hunk_count={} chunk_count={}",
            manifest.total_bytes, manifest.changed_lines, manifest.hunk_count, manifest.chunk_count
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
    state: &AppState,
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
        let mut payloads = state
            .diff_payloads
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

fn prune_diff_payloads(
    payloads: &mut std::collections::HashMap<String, DiffPayloadRecord>,
    now: Instant,
) {
    payloads.retain(|_, record| record.expires_at > now);
}

fn trim_diff_payloads(payloads: &mut std::collections::HashMap<String, DiffPayloadRecord>) {
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
        payloads.remove(&diff_id);
    }
}

fn split_text_chunks(value: &str, chunk_size: usize) -> Vec<String> {
    if value.is_empty() {
        return vec![String::new()];
    }

    let mut chunks = Vec::new();
    let mut current = String::new();

    for line in value.split_inclusive('\n') {
        if current.len() + line.len() <= chunk_size {
            current.push_str(line);
            continue;
        }

        if !current.is_empty() {
            chunks.push(current);
            current = String::new();
        }

        if line.len() <= chunk_size {
            current.push_str(line);
            continue;
        }

        let mut line_chunk = String::new();
        for ch in line.chars() {
            if line_chunk.len() + ch.len_utf8() > chunk_size && !line_chunk.is_empty() {
                chunks.push(line_chunk);
                line_chunk = String::new();
            }
            line_chunk.push(ch);
        }

        if !line_chunk.is_empty() {
            chunks.push(line_chunk);
        }
    }

    if !current.is_empty() {
        chunks.push(current);
    }

    if chunks.is_empty() {
        chunks.push(String::new());
    }

    chunks
}

fn count_changed_lines(diff_text: &str) -> (u32, u32) {
    let mut additions = 0_u32;
    let mut deletions = 0_u32;

    for line in diff_text.lines() {
        if line.starts_with('+') && !line.starts_with("+++") {
            additions = additions.saturating_add(1);
        } else if line.starts_with('-') && !line.starts_with("---") {
            deletions = deletions.saturating_add(1);
        }
    }

    (additions, deletions)
}

fn parse_hunks(diff_text: &str) -> Vec<DiffHunkData> {
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

    let mut hunks = Vec::<DiffHunkData>::new();
    let mut current: Option<HunkDraft> = None;

    for line in diff_text.lines() {
        if let Some((old_start, old_lines, new_start, new_lines)) = parse_hunk_header(line) {
            if let Some(previous) = current.take() {
                hunks.push(DiffHunkData {
                    hunk_index: previous.hunk_index,
                    header: previous.header,
                    old_start: previous.old_start,
                    old_lines: previous.old_lines,
                    new_start: previous.new_start,
                    new_lines: previous.new_lines,
                    added_lines: previous.added_lines,
                    deleted_lines: previous.deleted_lines,
                });
            }

            current = Some(HunkDraft {
                hunk_index: hunks.len() as u32,
                header: line.to_string(),
                old_start,
                old_lines,
                new_start,
                new_lines,
                added_lines: 0,
                deleted_lines: 0,
            });
            continue;
        }

        if let Some(active) = current.as_mut() {
            if line.starts_with('+') && !line.starts_with("+++") {
                active.added_lines = active.added_lines.saturating_add(1);
            } else if line.starts_with('-') && !line.starts_with("---") {
                active.deleted_lines = active.deleted_lines.saturating_add(1);
            }
        }
    }

    if let Some(last) = current.take() {
        hunks.push(DiffHunkData {
            hunk_index: last.hunk_index,
            header: last.header,
            old_start: last.old_start,
            old_lines: last.old_lines,
            new_start: last.new_start,
            new_lines: last.new_lines,
            added_lines: last.added_lines,
            deleted_lines: last.deleted_lines,
        });
    }

    hunks
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
    use super::{count_changed_lines, parse_hunks, split_text_chunks};

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
}
