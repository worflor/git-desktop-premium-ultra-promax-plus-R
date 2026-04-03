use std::time::Instant;

use uuid::Uuid;

use crate::errors::AppError;
use crate::services::{ai_service, auth_service, forge_service, git_provider, logging_service};

pub fn run_startup_readiness_probe() {
    let request_id = format!("startup-{}", Uuid::new_v4());

    logging_service::with_request_context(request_id.as_str(), || {
        let started_at = Instant::now();
        let mut failed_checks = 0_u32;

        if !run_check("startup.git.capabilities", request_id.as_str(), || {
            git_provider::detect_capabilities().map(|_| ())
        }) {
            failed_checks = failed_checks.saturating_add(1);
        }

        if !run_check("startup.auth.baseline", request_id.as_str(), || {
            auth_service::get_auth_status(None).map(|_| ())
        }) {
            failed_checks = failed_checks.saturating_add(1);
        }

        if !run_check("startup.forge.adapters", request_id.as_str(), || {
            forge_service::list_forge_adapters().map(|_| ())
        }) {
            failed_checks = failed_checks.saturating_add(1);
        }

        if !run_check("startup.ai.providers", request_id.as_str(), || {
            ai_service::list_providers().map(|_| ())
        }) {
            failed_checks = failed_checks.saturating_add(1);
        }

        let ok = failed_checks == 0;
        let message = if ok {
            Some("startup readiness probe completed".to_string())
        } else {
            Some(format!(
                "startup readiness probe completed with {failed_checks} degraded checks"
            ))
        };

        let _ = logging_service::record_operation_span(
            "bootstrap",
            "startup.readiness",
            Some(request_id.as_str()),
            started_at,
            ok,
            if ok { None } else { Some("bootstrap.degraded") },
            message.as_deref(),
        );
    });
}

fn run_check(
    command: &str,
    request_id: &str,
    operation: impl FnOnce() -> Result<(), AppError>,
) -> bool {
    let started_at = Instant::now();

    match operation() {
        Ok(()) => {
            let _ = logging_service::record_operation_span(
                "bootstrap",
                command,
                Some(request_id),
                started_at,
                true,
                None,
                None,
            );
            true
        }
        Err(error) => {
            let command_error = error.to_command_error();
            let _ = logging_service::record_operation_span(
                "bootstrap",
                command,
                Some(request_id),
                started_at,
                false,
                Some(command_error.code.as_str()),
                Some(command_error.message.as_str()),
            );
            false
        }
    }
}
