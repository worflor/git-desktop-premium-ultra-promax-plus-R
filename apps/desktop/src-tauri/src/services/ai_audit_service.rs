use std::collections::hash_map::DefaultHasher;
use std::fs::{self, File};
use std::hash::{Hash, Hasher};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::Path;

use chrono::{DateTime, Duration, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{AiAuditEntryData, AiAuditListData};

const AI_AUDIT_FILE_NAME: &str = "ai_review_audit.jsonl";
const MAX_AUDIT_ENTRIES: usize = 5_000;
const MAX_AUDIT_BYTES: u64 = 16 * 1024 * 1024;
const RETENTION_DAYS: i64 = 90;
const DEFAULT_LIST_LIMIT: usize = 200;
const MAX_LIST_LIMIT: usize = 1_000;
const PREVIEW_CHAR_LIMIT: usize = 1_200;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoredAiAuditEntry {
    id: String,
    event: String,
    provider_id: String,
    repository_hint: String,
    diff_scope_path: Option<String>,
    prompt_preview: String,
    output_preview: String,
    ok: bool,
    error_code: Option<String>,
    created_at: String,
}

pub struct AiAuditEventInput<'a> {
    pub event: &'a str,
    pub provider_id: &'a str,
    pub repository_path: &'a str,
    pub diff_scope_path: Option<&'a str>,
    pub prompt: &'a str,
    pub output: &'a str,
    pub ok: bool,
    pub error_code: Option<&'a str>,
}

pub fn record_ai_audit_event(input: AiAuditEventInput<'_>) -> Result<(), AppError> {
    let event = input.event.trim().to_ascii_lowercase();
    let provider_id = input.provider_id.trim().to_ascii_lowercase();
    if event.is_empty() || provider_id.is_empty() {
        return Err(AppError::InvalidInput(
            "ai audit event and provider id are required".to_string(),
        ));
    }

    let mut entries = load_entries()?;
    entries.push(StoredAiAuditEntry {
        id: Uuid::new_v4().to_string(),
        event,
        provider_id,
        repository_hint: repository_hint(input.repository_path),
        diff_scope_path: input
            .diff_scope_path
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| value.to_string()),
        prompt_preview: redact_sensitive_text(input.prompt, PREVIEW_CHAR_LIMIT),
        output_preview: redact_sensitive_text(input.output, PREVIEW_CHAR_LIMIT),
        ok: input.ok,
        error_code: input.error_code.map(|value| value.trim().to_string()),
        created_at: now_iso8601_string(),
    });

    apply_retention_policy(&mut entries);
    persist_entries(&entries)
}

pub fn get_ai_audit_entries(limit: Option<usize>) -> Result<AiAuditListData, AppError> {
    let mut entries = load_entries()?;
    apply_retention_policy(&mut entries);
    persist_entries(&entries)?;

    let limit = limit.unwrap_or(DEFAULT_LIST_LIMIT).clamp(1, MAX_LIST_LIMIT);
    let start = entries.len().saturating_sub(limit);

    Ok(AiAuditListData {
        generated_at: now_iso8601_string(),
        sample_count: entries.len() as u32,
        entries: entries[start..].iter().cloned().map(to_data).collect(),
    })
}

fn repository_hint(repository_path: &str) -> String {
    let trimmed = repository_path.trim();
    let name = Path::new(trimmed)
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("repo");

    let mut hasher = DefaultHasher::new();
    trimmed.hash(&mut hasher);
    let fingerprint = hasher.finish() as u32;
    format!("{name}#{fingerprint:08x}")
}

fn redact_sensitive_text(value: &str, limit: usize) -> String {
    let clipped = truncate_chars(value.trim(), limit);
    if clipped.is_empty() {
        return String::new();
    }

    let mut redacted_lines = Vec::new();
    for line in clipped.lines() {
        redacted_lines.push(redact_line(line));
    }

    redacted_lines.join("\n")
}

fn redact_line(line: &str) -> String {
    let mut redacted = line.to_string();
    let lower = line.to_ascii_lowercase();

    if let Some(index) = lower.find("bearer ") {
        return format!("{}Bearer [REDACTED]", &line[..index]);
    }

    for separator in [':', '='] {
        if let Some(index) = line.find(separator) {
            let key = line[..index].trim().to_ascii_lowercase();
            if key.contains("token")
                || key.contains("secret")
                || key.contains("password")
                || key.contains("api_key")
                || key.contains("apikey")
                || key.contains("authorization")
            {
                return format!("{}{} [REDACTED]", &line[..index], separator);
            }
        }
    }

    for marker in ["ghp_", "gho_", "ghu_", "ghs_", "sk-"] {
        if let Some(index) = lower.find(marker) {
            redacted.replace_range(index.., "[REDACTED]");
            break;
        }
    }

    redacted
}

fn truncate_chars(value: &str, limit: usize) -> String {
    if value.is_empty() {
        return String::new();
    }

    let mut iter = value.chars();
    let truncated: String = iter.by_ref().take(limit).collect();
    if iter.next().is_some() {
        return format!("{truncated}\n[...truncated to {limit} chars...]");
    }

    truncated
}

fn apply_retention_policy(entries: &mut Vec<StoredAiAuditEntry>) {
    let cutoff = Utc::now() - Duration::days(RETENTION_DAYS);
    entries.retain(|entry| {
        parse_iso8601(&entry.created_at)
            .map(|timestamp| timestamp >= cutoff)
            .unwrap_or(false)
    });

    if entries.len() > MAX_AUDIT_ENTRIES {
        let drop_count = entries.len() - MAX_AUDIT_ENTRIES;
        entries.drain(..drop_count);
    }

    if entries.is_empty() {
        return;
    }

    let mut kept_bytes = 0_u64;
    let mut keep_start = entries.len();

    for (index, entry) in entries.iter().enumerate().rev() {
        let bytes = serialized_size(entry).saturating_add(1) as u64;
        if bytes > MAX_AUDIT_BYTES {
            keep_start = index.saturating_add(1);
            break;
        }
        if kept_bytes.saturating_add(bytes) > MAX_AUDIT_BYTES {
            break;
        }

        kept_bytes = kept_bytes.saturating_add(bytes);
        keep_start = index;
    }

    if keep_start > 0 {
        entries.drain(..keep_start);
    }
}

fn parse_iso8601(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|timestamp| timestamp.with_timezone(&Utc))
}

fn serialized_size(entry: &StoredAiAuditEntry) -> usize {
    serde_json::to_vec(entry)
        .map(|payload| payload.len())
        .unwrap_or(0)
}

fn load_entries() -> Result<Vec<StoredAiAuditEntry>, AppError> {
    let path = ai_audit_file_path()?;
    if !path.exists() {
        return Ok(Vec::new());
    }

    let file = File::open(path)
        .map_err(|error| AppError::Internal(format!("failed to read ai audit file: {error}")))?;
    let reader = BufReader::new(file);

    let mut entries = Vec::new();
    for line in reader.lines() {
        let line = line.map_err(|error| {
            AppError::Internal(format!("failed to read ai audit file: {error}"))
        })?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if let Ok(entry) = serde_json::from_str::<StoredAiAuditEntry>(trimmed) {
            entries.push(entry);
        }
    }

    Ok(entries)
}

fn persist_entries(entries: &[StoredAiAuditEntry]) -> Result<(), AppError> {
    let path = ai_audit_file_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| AppError::Internal("ai audit storage path is invalid".to_string()))?;

    fs::create_dir_all(parent).map_err(|error| {
        AppError::Internal(format!("failed to create ai audit directory: {error}"))
    })?;

    let file = File::create(path)
        .map_err(|error| AppError::Internal(format!("failed to persist ai audit file: {error}")))?;
    let mut writer = BufWriter::new(file);

    for entry in entries {
        serde_json::to_writer(&mut writer, entry).map_err(|error| {
            AppError::Internal(format!("failed to serialize ai audit entry: {error}"))
        })?;
        writer.write_all(b"\n").map_err(|error| {
            AppError::Internal(format!("failed to persist ai audit file: {error}"))
        })?;
    }

    writer
        .flush()
        .map_err(|error| AppError::Internal(format!("failed to persist ai audit file: {error}")))
}

fn ai_audit_file_path() -> Result<std::path::PathBuf, AppError> {
    let appdata = std::env::var("APPDATA").map_err(|_| {
        AppError::Internal("APPDATA environment variable is unavailable".to_string())
    })?;
    Ok(std::path::PathBuf::from(appdata)
        .join("gdpu")
        .join(AI_AUDIT_FILE_NAME))
}

fn to_data(entry: StoredAiAuditEntry) -> AiAuditEntryData {
    AiAuditEntryData {
        id: entry.id,
        event: entry.event,
        provider_id: entry.provider_id,
        repository_hint: entry.repository_hint,
        diff_scope_path: entry.diff_scope_path,
        prompt_preview: entry.prompt_preview,
        output_preview: entry.output_preview,
        ok: entry.ok,
        error_code: entry.error_code,
        created_at: entry.created_at,
    }
}

fn now_iso8601_string() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}

#[cfg(test)]
mod tests {
    use chrono::{Duration, SecondsFormat, Utc};

    use super::{
        apply_retention_policy, redact_sensitive_text, repository_hint, truncate_chars,
        StoredAiAuditEntry,
    };

    fn sample_entry(created_at: String, preview: String) -> StoredAiAuditEntry {
        StoredAiAuditEntry {
            id: "id-1".to_string(),
            event: "review.run".to_string(),
            provider_id: "codex".to_string(),
            repository_hint: "repo#1234abcd".to_string(),
            diff_scope_path: None,
            prompt_preview: preview.clone(),
            output_preview: preview,
            ok: true,
            error_code: None,
            created_at,
        }
    }

    #[test]
    fn repository_hint_is_stable_for_same_path() {
        let first = repository_hint("C:/work/repo-alpha");
        let second = repository_hint("C:/work/repo-alpha");
        let third = repository_hint("C:/work/repo-beta");

        assert_eq!(first, second);
        assert_ne!(first, third);
    }

    #[test]
    fn redact_sensitive_text_masks_common_secret_shapes() {
        let redacted = redact_sensitive_text(
            "Authorization: bearer abc\napi_key=12345\nraw ghp_abcdef\n",
            200,
        );

        assert!(
            redacted.contains("Authorization: [REDACTED]")
                || redacted.contains("Bearer [REDACTED]")
        );
        assert!(redacted.contains("api_key= [REDACTED]"));
        assert!(redacted.contains("[REDACTED]"));
    }

    #[test]
    fn truncate_chars_appends_marker_when_clipped() {
        let value = truncate_chars("abcdefgh", 4);
        assert!(value.starts_with("abcd"));
        assert!(value.contains("truncated to 4 chars"));
    }

    #[test]
    fn retention_policy_drops_expired_entries() {
        let fresh = (Utc::now() - Duration::days(2)).to_rfc3339_opts(SecondsFormat::Secs, true);
        let expired = (Utc::now() - Duration::days(180)).to_rfc3339_opts(SecondsFormat::Secs, true);
        let mut entries = vec![
            sample_entry(expired, "x".repeat(8)),
            sample_entry(fresh.clone(), "y".repeat(8)),
        ];

        apply_retention_policy(&mut entries);

        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].created_at, fresh);
    }
}
