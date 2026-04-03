use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use chrono::{DateTime, Duration, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{
    CommandTelemetrySampleData, CommandTelemetrySnapshotData, CommandTelemetrySummaryData,
};
use crate::services::settings_service;

const TELEMETRY_FILE_NAME: &str = "command_telemetry.jsonl";
const DEFAULT_RETENTION_DAYS: u32 = 30;
const DEFAULT_RETENTION_MB: u32 = 128;
const DEFAULT_RECENT_LIMIT: usize = 200;
const MAX_RECENT_LIMIT: usize = 1_000;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StoredCommandTelemetrySample {
    id: String,
    scope: String,
    command: String,
    ok: bool,
    error_code: Option<String>,
    duration_ms: u64,
    created_at: String,
}

#[derive(Debug, Clone, Copy)]
struct RetentionPolicy {
    max_age_days: u32,
    max_bytes: u64,
}

pub fn record_command_sample(
    scope: &str,
    command: &str,
    ok: bool,
    duration_ms: u64,
    error_code: Option<&str>,
) -> Result<(), AppError> {
    let scope = normalize_scope(scope);
    let command = normalize_command(command)?;

    let mut samples = load_samples()?;
    let policy = load_retention_policy();
    apply_retention_policy(&mut samples, policy);

    samples.push(StoredCommandTelemetrySample {
        id: Uuid::new_v4().to_string(),
        scope,
        command,
        ok,
        error_code: error_code.map(|value| value.trim().to_string()),
        duration_ms,
        created_at: now_iso8601_string(),
    });

    apply_retention_policy(&mut samples, policy);
    persist_samples(&samples)
}

pub fn get_command_telemetry_snapshot(
    recent_limit: Option<usize>,
) -> Result<CommandTelemetrySnapshotData, AppError> {
    let mut samples = load_samples()?;
    let policy = load_retention_policy();
    apply_retention_policy(&mut samples, policy);
    persist_samples(&samples)?;

    let limit = recent_limit
        .unwrap_or(DEFAULT_RECENT_LIMIT)
        .clamp(1, MAX_RECENT_LIMIT);

    let mut recent_samples: Vec<CommandTelemetrySampleData> = samples
        .iter()
        .rev()
        .take(limit)
        .cloned()
        .map(to_sample_data)
        .collect();
    recent_samples.reverse();

    Ok(CommandTelemetrySnapshotData {
        generated_at: now_iso8601_string(),
        sample_count: samples.len() as u32,
        summaries: summarize_samples(&samples),
        recent_samples,
    })
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

fn normalize_scope(value: &str) -> String {
    let normalized = value.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return "backend".to_string();
    }

    normalized
}

fn normalize_command(value: &str) -> Result<String, AppError> {
    let normalized = value.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return Err(AppError::InvalidInput(
            "telemetry command label is required".to_string(),
        ));
    }

    Ok(normalized)
}

fn summarize_samples(samples: &[StoredCommandTelemetrySample]) -> Vec<CommandTelemetrySummaryData> {
    #[derive(Default)]
    struct Aggregate {
        durations: Vec<u64>,
        failure_count: u32,
        last_duration_ms: u64,
        last_seen_at: String,
    }

    let mut grouped = BTreeMap::<(String, String), Aggregate>::new();

    for sample in samples {
        let key = (sample.scope.clone(), sample.command.clone());
        let entry = grouped.entry(key).or_default();
        entry.durations.push(sample.duration_ms);
        if !sample.ok {
            entry.failure_count += 1;
        }
        entry.last_duration_ms = sample.duration_ms;
        entry.last_seen_at = sample.created_at.clone();
    }

    grouped
        .into_iter()
        .map(|((scope, command), mut aggregate)| {
            aggregate.durations.sort_unstable();
            CommandTelemetrySummaryData {
                scope,
                command,
                sample_count: aggregate.durations.len() as u32,
                failure_count: aggregate.failure_count,
                p50_ms: percentile(&aggregate.durations, 50),
                p95_ms: percentile(&aggregate.durations, 95),
                last_duration_ms: aggregate.last_duration_ms,
                last_seen_at: aggregate.last_seen_at,
            }
        })
        .collect()
}

fn percentile(sorted_durations: &[u64], percentile: u8) -> u64 {
    if sorted_durations.is_empty() {
        return 0;
    }

    let rank = ((percentile as f64 / 100.0) * sorted_durations.len() as f64).ceil() as usize;
    let index = rank.saturating_sub(1).min(sorted_durations.len() - 1);
    sorted_durations[index]
}

fn apply_retention_policy(samples: &mut Vec<StoredCommandTelemetrySample>, policy: RetentionPolicy) {
    let cutoff = Utc::now() - Duration::days(policy.max_age_days as i64);
    samples.retain(|sample| {
        parse_iso8601(&sample.created_at)
            .map(|timestamp| timestamp >= cutoff)
            .unwrap_or(false)
    });

    if samples.is_empty() {
        return;
    }

    let max_bytes = policy.max_bytes.max(1024);
    let mut kept_bytes = 0_u64;
    let mut kept = Vec::new();

    for sample in samples.iter().rev() {
        let sample_bytes = serialized_size(sample) as u64 + 1;
        if kept_bytes.saturating_add(sample_bytes) > max_bytes {
            continue;
        }

        kept_bytes = kept_bytes.saturating_add(sample_bytes);
        kept.push(sample.clone());
    }

    kept.reverse();
    *samples = kept;
}

fn serialized_size(sample: &StoredCommandTelemetrySample) -> usize {
    serde_json::to_string(sample)
        .map(|payload| payload.len())
        .unwrap_or(0)
}

fn parse_iso8601(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|timestamp| timestamp.with_timezone(&Utc))
}

fn load_samples() -> Result<Vec<StoredCommandTelemetrySample>, AppError> {
    let path = telemetry_file_path()?;
    if !path.exists() {
        return Ok(Vec::new());
    }

    let payload = fs::read_to_string(path).map_err(|error| {
        AppError::Internal(format!(
            "failed to read telemetry storage file: {error}"
        ))
    })?;

    let mut samples = Vec::new();
    for line in payload.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if let Ok(sample) = serde_json::from_str::<StoredCommandTelemetrySample>(trimmed) {
            samples.push(sample);
        }
    }

    Ok(samples)
}

fn persist_samples(samples: &[StoredCommandTelemetrySample]) -> Result<(), AppError> {
    let path = telemetry_file_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| AppError::Internal("telemetry storage path is invalid".to_string()))?;

    fs::create_dir_all(parent).map_err(|error| {
        AppError::Internal(format!(
            "failed to create telemetry storage directory: {error}"
        ))
    })?;

    let mut payload = String::new();
    for sample in samples {
        let line = serde_json::to_string(sample).map_err(|error| {
            AppError::Internal(format!("failed to serialize telemetry sample: {error}"))
        })?;
        payload.push_str(&line);
        payload.push('\n');
    }

    fs::write(path, payload).map_err(|error| {
        AppError::Internal(format!(
            "failed to persist telemetry storage file: {error}"
        ))
    })
}

fn telemetry_file_path() -> Result<PathBuf, AppError> {
    let appdata = std::env::var("APPDATA")
        .map_err(|_| AppError::Internal("APPDATA environment variable is unavailable".to_string()))?;
    Ok(PathBuf::from(appdata)
        .join("gdpu")
        .join(TELEMETRY_FILE_NAME))
}

fn to_sample_data(sample: StoredCommandTelemetrySample) -> CommandTelemetrySampleData {
    CommandTelemetrySampleData {
        id: sample.id,
        scope: sample.scope,
        command: sample.command,
        ok: sample.ok,
        error_code: sample.error_code,
        duration_ms: sample.duration_ms,
        created_at: sample.created_at,
    }
}

fn now_iso8601_string() -> String {
    Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true)
}

#[cfg(test)]
mod tests {
    use super::{
        apply_retention_policy, now_iso8601_string, percentile, summarize_samples,
        RetentionPolicy, StoredCommandTelemetrySample,
    };
    use chrono::{Duration, SecondsFormat, Utc};

    fn sample(command: &str, duration_ms: u64, ok: bool, created_at: String) -> StoredCommandTelemetrySample {
        StoredCommandTelemetrySample {
            id: format!("sample-{command}-{duration_ms}"),
            scope: "backend".to_string(),
            command: command.to_string(),
            ok,
            error_code: if ok {
                None
            } else {
                Some("git.command_failed".to_string())
            },
            duration_ms,
            created_at,
        }
    }

    #[test]
    fn percentile_returns_expected_rank_values() {
        let durations = vec![10_u64, 20_u64, 30_u64, 100_u64];
        assert_eq!(percentile(&durations, 50), 20);
        assert_eq!(percentile(&durations, 95), 100);
    }

    #[test]
    fn retention_policy_drops_expired_samples() {
        let old = (Utc::now() - Duration::days(90)).to_rfc3339_opts(SecondsFormat::Secs, true);
        let now = now_iso8601_string();
        let mut samples = vec![
            sample("git.status", 12, true, old),
            sample("git.status", 14, true, now),
        ];

        apply_retention_policy(
            &mut samples,
            RetentionPolicy {
                max_age_days: 30,
                max_bytes: 1_000_000,
            },
        );

        assert_eq!(samples.len(), 1);
        assert_eq!(samples[0].duration_ms, 14);
    }

    #[test]
    fn summary_aggregates_counts_and_failures() {
        let now = now_iso8601_string();
        let samples = vec![
            sample("git.status", 10, true, now.clone()),
            sample("git.status", 30, false, now.clone()),
            sample("git.status", 20, true, now.clone()),
            sample("git.fetch", 50, true, now),
        ];

        let summaries = summarize_samples(&samples);
        assert_eq!(summaries.len(), 2);

        let status_summary = summaries
            .iter()
            .find(|summary| summary.command == "git.status")
            .expect("status summary should exist");

        assert_eq!(status_summary.sample_count, 3);
        assert_eq!(status_summary.failure_count, 1);
        assert_eq!(status_summary.p50_ms, 20);
        assert_eq!(status_summary.p95_ms, 30);
    }
}
