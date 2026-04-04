use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::Instant;

use chrono::{SecondsFormat, Utc};

use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{StartupReadinessCheckData, StartupReadinessSnapshotData};
use crate::services::{ai_service, auth_service, forge_service, git_provider, logging_service};

type StartupCheckOperation = fn() -> Result<(), AppError>;

const STARTUP_CHECKS: [(&str, StartupCheckOperation); 4] = [
    ("startup.git.capabilities", check_git_capabilities),
    ("startup.auth.baseline", check_auth_baseline),
    ("startup.forge.adapters", check_forge_adapters),
    ("startup.ai.providers", check_ai_providers),
];

pub fn get_startup_readiness_snapshot(
    refresh: bool,
) -> Result<StartupReadinessSnapshotData, AppError> {
    if refresh {
        return run_probe_with_new_request_id();
    }

    if let Some(snapshot) = load_last_snapshot()? {
        return Ok(snapshot);
    }

    run_probe_with_new_request_id()
}

fn run_probe_with_new_request_id() -> Result<StartupReadinessSnapshotData, AppError> {
    let request_id = format!("startup-{}", Uuid::new_v4());
    let snapshot = logging_service::with_request_context(request_id.as_str(), || {
        capture_startup_readiness_snapshot(request_id.as_str())
    });
    save_last_snapshot(snapshot.clone())?;
    Ok(snapshot)
}

fn capture_startup_readiness_snapshot(request_id: &str) -> StartupReadinessSnapshotData {
    let started_at = Instant::now();
    let started_at_utc = Utc::now();
    let checks = run_checks_parallel(request_id);

    let degraded_checks = checks.iter().filter(|check| !check.ok).count() as u32;
    let ok = degraded_checks == 0;
    let duration_ms = started_at.elapsed().as_millis() as u64;
    let completed_at = Utc::now();

    let message = if ok {
        Some("startup readiness probe completed".to_string())
    } else {
        Some(format!(
            "startup readiness probe completed with {degraded_checks} degraded checks"
        ))
    };

    let _ = logging_service::record_operation_span(
        "bootstrap",
        "startup.readiness",
        Some(request_id),
        started_at,
        ok,
        if ok { None } else { Some("bootstrap.degraded") },
        message.as_deref(),
    );

    StartupReadinessSnapshotData {
        request_id: request_id.to_string(),
        started_at: started_at_utc.to_rfc3339_opts(SecondsFormat::Secs, true),
        completed_at: completed_at.to_rfc3339_opts(SecondsFormat::Secs, true),
        duration_ms,
        ok,
        degraded_checks,
        checks,
    }
}

fn run_checks_parallel(request_id: &str) -> Vec<StartupReadinessCheckData> {
    let mut handles = Vec::with_capacity(STARTUP_CHECKS.len());

    for (index, (check_id, operation)) in STARTUP_CHECKS.iter().copied().enumerate() {
        let request_id = request_id.to_string();
        handles.push(thread::spawn(move || {
            (index, run_check(check_id, request_id.as_str(), operation))
        }));
    }

    let mut checks: Vec<Option<StartupReadinessCheckData>> = vec![None; STARTUP_CHECKS.len()];

    for (handle_index, handle) in handles.into_iter().enumerate() {
        match handle.join() {
            Ok((index, check)) => {
                checks[index] = Some(check);
            }
            Err(_) => {
                let check_id = STARTUP_CHECKS[handle_index].0;
                let message = "startup check thread panicked";
                let _ = logging_service::record_operation_span(
                    "bootstrap",
                    check_id,
                    Some(request_id),
                    Instant::now(),
                    false,
                    Some("bootstrap.thread_panicked"),
                    Some(message),
                );
                checks[handle_index] = Some(StartupReadinessCheckData {
                    id: check_id.to_string(),
                    ok: false,
                    duration_ms: 0,
                    error_code: Some("bootstrap.thread_panicked".to_string()),
                    message: Some(message.to_string()),
                });
            }
        }
    }

    checks
        .into_iter()
        .enumerate()
        .map(|(index, check)| {
            check.unwrap_or_else(|| StartupReadinessCheckData {
                id: STARTUP_CHECKS[index].0.to_string(),
                ok: false,
                duration_ms: 0,
                error_code: Some("bootstrap.check_missing".to_string()),
                message: Some("startup check did not produce a result".to_string()),
            })
        })
        .collect()
}

fn check_git_capabilities() -> Result<(), AppError> {
    git_provider::detect_capabilities().map(|_| ())
}

fn check_auth_baseline() -> Result<(), AppError> {
    auth_service::get_auth_status(None).map(|_| ())
}

fn check_forge_adapters() -> Result<(), AppError> {
    forge_service::list_forge_adapters().map(|_| ())
}

fn check_ai_providers() -> Result<(), AppError> {
    ai_service::list_providers().map(|_| ())
}

fn run_check(
    check_id: &str,
    request_id: &str,
    operation: impl FnOnce() -> Result<(), AppError>,
) -> StartupReadinessCheckData {
    let started_at = Instant::now();

    match operation() {
        Ok(()) => {
            let _ = logging_service::record_operation_span(
                "bootstrap",
                check_id,
                Some(request_id),
                started_at,
                true,
                None,
                None,
            );
            StartupReadinessCheckData {
                id: check_id.to_string(),
                ok: true,
                duration_ms: started_at.elapsed().as_millis() as u64,
                error_code: None,
                message: None,
            }
        }
        Err(error) => {
            let command_error = error.to_command_error();
            let _ = logging_service::record_operation_span(
                "bootstrap",
                check_id,
                Some(request_id),
                started_at,
                false,
                Some(command_error.code.as_str()),
                Some(command_error.message.as_str()),
            );
            StartupReadinessCheckData {
                id: check_id.to_string(),
                ok: false,
                duration_ms: started_at.elapsed().as_millis() as u64,
                error_code: Some(command_error.code),
                message: Some(command_error.message),
            }
        }
    }
}

fn save_last_snapshot(snapshot: StartupReadinessSnapshotData) -> Result<(), AppError> {
    let mut guard = startup_snapshot_store().lock().map_err(|_| {
        AppError::Internal("startup readiness snapshot state is poisoned".to_string())
    })?;
    *guard = Some(snapshot);
    Ok(())
}

fn load_last_snapshot() -> Result<Option<StartupReadinessSnapshotData>, AppError> {
    let guard = startup_snapshot_store().lock().map_err(|_| {
        AppError::Internal("startup readiness snapshot state is poisoned".to_string())
    })?;
    Ok(guard.clone())
}

fn startup_snapshot_store() -> &'static Mutex<Option<StartupReadinessSnapshotData>> {
    static STARTUP_SNAPSHOT: OnceLock<Mutex<Option<StartupReadinessSnapshotData>>> =
        OnceLock::new();
    STARTUP_SNAPSHOT.get_or_init(|| Mutex::new(None))
}
