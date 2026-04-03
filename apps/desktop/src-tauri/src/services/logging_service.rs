use std::cell::RefCell;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use chrono::{DateTime, Duration, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::AppError;
use crate::services::settings_service;

const OPERATION_LOG_FILE_NAME: &str = "operation_events.jsonl";
const DEFAULT_RETENTION_DAYS: u32 = 30;
const DEFAULT_RETENTION_MB: u32 = 64;

thread_local! {
    static REQUEST_CONTEXT: RefCell<Option<String>> = const { RefCell::new(None) };
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoredOperationEvent {
    id: String,
    scope: String,
    command: String,
    event: String,
    level: String,
    request_id: String,
    parent_request_id: Option<String>,
    ok: Option<bool>,
    duration_ms: Option<u64>,
    error_code: Option<String>,
    message: Option<String>,
    attempt: Option<u32>,
    created_at: String,
    #[serde(skip)]
    serialized_len: usize,
}

#[derive(Debug, Clone, Copy)]
struct RetentionPolicy {
    max_age_days: u32,
    max_bytes: u64,
}

pub fn with_request_context<T>(request_id: &str, operation: impl FnOnce() -> T) -> T {
    let previous =
        REQUEST_CONTEXT.with(|context| context.borrow_mut().replace(request_id.to_string()));
    let result = operation();
    REQUEST_CONTEXT.with(|context| {
        let mut current = context.borrow_mut();
        *current = previous;
    });
    result
}

pub fn current_request_context() -> Option<String> {
    REQUEST_CONTEXT.with(|context| context.borrow().clone())
}

pub fn record_operation_span(
    scope: &str,
    command: &str,
    request_id: Option<&str>,
    started_at: Instant,
    ok: bool,
    error_code: Option<&str>,
    message: Option<&str>,
) -> Result<(), AppError> {
    let scope = normalize_scope(scope);
    let command = normalize_command(command)?;
    let request_id = request_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_string())
        .unwrap_or_else(|| Uuid::new_v4().to_string());

    let duration_ms = started_at.elapsed().as_millis() as u64;
    let finished_at = Utc::now();
    let started_at_utc = finished_at - Duration::milliseconds(duration_ms as i64);
    let parent_request_id = current_request_context().filter(|value| value != &request_id);

    let mut start_event = StoredOperationEvent {
        id: Uuid::new_v4().to_string(),
        scope: scope.clone(),
        command: command.clone(),
        event: "start".to_string(),
        level: "info".to_string(),
        request_id: request_id.clone(),
        parent_request_id: parent_request_id.clone(),
        ok: None,
        duration_ms: None,
        error_code: None,
        message: None,
        attempt: None,
        created_at: started_at_utc.to_rfc3339_opts(SecondsFormat::Secs, true),
        serialized_len: 0,
    };
    start_event.serialized_len = compute_serialized_size(&start_event);

    let mut end_event = StoredOperationEvent {
        id: Uuid::new_v4().to_string(),
        scope,
        command,
        event: if ok {
            "success".to_string()
        } else {
            "failure".to_string()
        },
        level: if ok {
            "info".to_string()
        } else {
            "error".to_string()
        },
        request_id,
        parent_request_id,
        ok: Some(ok),
        duration_ms: Some(duration_ms),
        error_code: error_code.map(|value| value.trim().to_string()),
        message: message
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|value| value.to_string()),
        attempt: None,
        created_at: finished_at.to_rfc3339_opts(SecondsFormat::Secs, true),
        serialized_len: 0,
    };
    end_event.serialized_len = compute_serialized_size(&end_event);

    with_io_lock(|| append_events(&[start_event, end_event]))
}

pub fn record_retry_event(
    scope: &str,
    command: &str,
    request_id: Option<&str>,
    attempt: u32,
    error_code: Option<&str>,
    message: &str,
) -> Result<(), AppError> {
    let scope = normalize_scope(scope);
    let command = normalize_command(command)?;
    let request_id = request_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_string())
        .unwrap_or_else(|| Uuid::new_v4().to_string());

    let mut event = StoredOperationEvent {
        id: Uuid::new_v4().to_string(),
        scope,
        command,
        event: "retry".to_string(),
        level: "warn".to_string(),
        request_id,
        parent_request_id: current_request_context(),
        ok: None,
        duration_ms: None,
        error_code: error_code.map(|value| value.trim().to_string()),
        message: Some(message.trim().to_string()),
        attempt: Some(attempt),
        created_at: now_iso8601_string(),
        serialized_len: 0,
    };
    event.serialized_len = compute_serialized_size(&event);

    with_io_lock(|| append_events(&[event]))
}

fn with_io_lock<T>(operation: impl FnOnce() -> Result<T, AppError>) -> Result<T, AppError> {
    let guard = io_lock()
        .lock()
        .map_err(|_| AppError::Internal("operation log storage lock is poisoned".to_string()))?;
    let result = operation();
    drop(guard);
    result
}

fn io_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn normalize_scope(value: &str) -> String {
    let normalized = normalize_ascii_label(value);
    if normalized.is_empty() {
        return "backend".to_string();
    }

    normalized
}

fn normalize_command(value: &str) -> Result<String, AppError> {
    let normalized = normalize_ascii_label(value);
    if normalized.is_empty() {
        return Err(AppError::InvalidInput(
            "operation command label is required".to_string(),
        ));
    }

    Ok(normalized)
}

fn normalize_ascii_label(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    if trimmed
        .as_bytes()
        .iter()
        .all(|byte| !byte.is_ascii_uppercase())
    {
        return trimmed.to_string();
    }

    trimmed.to_ascii_lowercase()
}

fn append_events(events: &[StoredOperationEvent]) -> Result<(), AppError> {
    let mut current = load_events()?;
    current.extend(events.iter().cloned());

    let policy = load_retention_policy();
    apply_retention_policy(&mut current, policy);
    persist_events(&current)
}

fn load_retention_policy() -> RetentionPolicy {
    match settings_service::get_settings() {
        Ok(settings) => RetentionPolicy {
            max_age_days: settings.telemetry_retention_days.clamp(1, 365),
            max_bytes: (settings.telemetry_retention_mb.clamp(16, 4096) as u64) * 1024 * 1024,
        },
        Err(_) => RetentionPolicy {
            max_age_days: DEFAULT_RETENTION_DAYS,
            max_bytes: (DEFAULT_RETENTION_MB as u64) * 1024 * 1024,
        },
    }
}

fn load_events() -> Result<Vec<StoredOperationEvent>, AppError> {
    let path = operation_log_file_path()?;
    if !path.exists() {
        return Ok(Vec::new());
    }

    let file = File::open(path).map_err(|error| {
        AppError::Internal(format!("failed to read operation log file: {error}"))
    })?;
    let reader = BufReader::new(file);

    let mut events = Vec::new();
    for line in reader.lines() {
        let line = line.map_err(|error| {
            AppError::Internal(format!("failed to read operation log file: {error}"))
        })?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if let Ok(mut event) = serde_json::from_str::<StoredOperationEvent>(trimmed) {
            event.serialized_len = trimmed.len();
            events.push(event);
        }
    }

    Ok(events)
}

fn apply_retention_policy(events: &mut Vec<StoredOperationEvent>, policy: RetentionPolicy) {
    let cutoff = Utc::now() - Duration::days(policy.max_age_days as i64);
    events.retain(|event| {
        parse_iso8601(&event.created_at)
            .map(|timestamp| timestamp >= cutoff)
            .unwrap_or(false)
    });

    if events.is_empty() {
        return;
    }

    let max_bytes = policy.max_bytes.max(1024);
    let mut kept_bytes = 0_u64;
    let mut keep_start = events.len();

    for (index, event) in events.iter().enumerate().rev() {
        let bytes = event.serialized_len.saturating_add(1) as u64;
        if bytes > max_bytes {
            keep_start = index.saturating_add(1);
            break;
        }

        if kept_bytes.saturating_add(bytes) > max_bytes {
            break;
        }

        kept_bytes = kept_bytes.saturating_add(bytes);
        keep_start = index;
    }

    if keep_start > 0 {
        events.drain(..keep_start);
    }
}

fn persist_events(events: &[StoredOperationEvent]) -> Result<(), AppError> {
    let path = operation_log_file_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| AppError::Internal("operation log path is invalid".to_string()))?;

    fs::create_dir_all(parent).map_err(|error| {
        AppError::Internal(format!("failed to create operation log directory: {error}"))
    })?;

    let file = File::create(path).map_err(|error| {
        AppError::Internal(format!("failed to persist operation log file: {error}"))
    })?;
    let mut writer = BufWriter::new(file);

    for event in events {
        serde_json::to_writer(&mut writer, event).map_err(|error| {
            AppError::Internal(format!("failed to serialize operation event: {error}"))
        })?;
        writer.write_all(b"\n").map_err(|error| {
            AppError::Internal(format!("failed to persist operation log file: {error}"))
        })?;
    }

    writer.flush().map_err(|error| {
        AppError::Internal(format!("failed to persist operation log file: {error}"))
    })
}

fn operation_log_file_path() -> Result<PathBuf, AppError> {
    let appdata = std::env::var("APPDATA").map_err(|_| {
        AppError::Internal("APPDATA environment variable is unavailable".to_string())
    })?;
    Ok(PathBuf::from(appdata)
        .join("gdpu")
        .join(OPERATION_LOG_FILE_NAME))
}

fn compute_serialized_size(event: &StoredOperationEvent) -> usize {
    serde_json::to_vec(event)
        .map(|payload| payload.len())
        .unwrap_or(0)
}

fn parse_iso8601(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|timestamp| timestamp.with_timezone(&Utc))
}

fn now_iso8601_string() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}
