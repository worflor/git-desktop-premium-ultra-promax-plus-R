use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::Value;
use uuid::Uuid;

use crate::errors::AppError;
use crate::models::operations::{
    AiAuditListData, AiDiffReviewCancelData, AiDiffReviewData, AiDiffReviewJobData,
    AiDiffReviewJobStartData, AiProviderListData, AiProviderStatus,
};
use crate::runtime::state::{AiReviewJobRecord, AiReviewJobState, AppState, SharedAiReviewJob};
use crate::services::{ai_audit_service, git_provider, settings_service};

const PROVIDER_BINARIES: [(&str, &str, ProviderKind); 4] = [
    ("codex", "codex", ProviderKind::Codex),
    ("claude", "claude", ProviderKind::Claude),
    ("gemini", "npx", ProviderKind::Gemini),
    ("opencode", "opencode", ProviderKind::OpenCode),
];
const MAX_RETAINED_JOBS: usize = 64;
const MAX_PROVIDER_RUNTIME: Duration = Duration::from_secs(90);
const MAX_STDIN_DIFF_CHARS: usize = 120_000;
#[cfg(test)]
const MAX_INLINE_DIFF_CHARS: usize = 6_000;
const PROVIDER_RESOLUTION_CACHE_TTL: Duration = Duration::from_secs(60);

#[derive(Clone, Copy)]
struct CliProviderAdapter {
    id: &'static str,
    binary: &'static str,
    kind: ProviderKind,
}

#[derive(Clone, Copy)]
enum ProviderKind {
    Codex,
    Claude,
    Gemini,
    OpenCode,
}

trait AiProviderAdapter {
    fn id(&self) -> &'static str;
    fn binary_name(&self) -> &'static str;
    fn kind(&self) -> ProviderKind;
    fn build_attempts(&self, prompt: &str, diff: &str) -> Vec<ProviderAttempt>;
    fn auth_status(&self) -> ProviderAuthStatus;
}

impl AiProviderAdapter for CliProviderAdapter {
    fn id(&self) -> &'static str {
        self.id
    }

    fn binary_name(&self) -> &'static str {
        self.binary
    }

    fn kind(&self) -> ProviderKind {
        self.kind
    }

    fn build_attempts(&self, prompt: &str, diff: &str) -> Vec<ProviderAttempt> {
        build_provider_attempts(self.kind, prompt, diff)
    }

    fn auth_status(&self) -> ProviderAuthStatus {
        provider_auth_status(self.kind)
    }
}

fn provider_adapters() -> [CliProviderAdapter; 4] {
    PROVIDER_BINARIES.map(|(id, binary, kind)| CliProviderAdapter { id, binary, kind })
}

fn provider_adapter(provider_id: &str) -> Option<CliProviderAdapter> {
    provider_adapters()
        .into_iter()
        .find(|adapter| adapter.id() == provider_id)
}

struct ProviderAttempt {
    name: &'static str,
    args: Vec<String>,
    stdin_payload: Option<String>,
    output_mode: ProviderOutputMode,
}

#[derive(Clone, Copy)]
enum ProviderOutputMode {
    PlainText,
    CodexJsonl,
    ClaudeJson,
    GeminiJson,
    OpenCodeJsonl,
}

#[derive(Clone)]
struct ProviderAuthStatus {
    ok: bool,
    detail: String,
    plan_name: Option<String>,
}

#[derive(Clone, Copy)]
enum StreamSource {
    Stdout,
    Stderr,
}

struct StreamChunk {
    source: StreamSource,
    text: String,
}

#[derive(Clone)]
struct ProviderResolution {
    command: String,
    source: String,
    health_check: String,
}

#[derive(Clone)]
struct ProviderAvailability {
    ready: bool,
    resolution: Option<ProviderResolution>,
    auth: ProviderAuthStatus,
}

#[derive(Clone)]
struct ProviderResolutionCacheEntry {
    checked_at: Instant,
    resolution: Option<ProviderResolution>,
}

pub fn list_providers() -> Result<AiProviderListData, AppError> {
    let providers = provider_adapters()
        .into_iter()
        .map(|adapter| {
            let availability = inspect_provider(&adapter);
            AiProviderStatus {
                id: adapter.id().to_string(),
                available: availability.ready,
                binary: adapter.binary_name().to_string(),
                plan_name: availability.auth.plan_name.clone(),
                resolved_binary: availability
                    .resolution
                    .as_ref()
                    .map(|item| item.command.clone()),
                detection_source: availability
                    .resolution
                    .as_ref()
                    .map(|item| item.source.clone()),
                health_check: format_provider_health(&availability),
            }
        })
        .collect();

    Ok(AiProviderListData { providers })
}

pub fn get_audit_entries(limit: Option<usize>) -> Result<AiAuditListData, AppError> {
    ai_audit_service::get_ai_audit_entries(limit)
}

pub fn run_diff_review(
    provider_id: &str,
    repository_path: &str,
    prompt: &str,
    diff_scope_path: Option<&str>,
) -> Result<AiDiffReviewData, AppError> {
    if let Err(error) = enforce_guardrail_for_review(prompt) {
        let code = error.to_command_error().code;
        let _ = ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
            event: "review.guardrail.blocked",
            provider_id,
            repository_path,
            diff_scope_path,
            prompt,
            output: "",
            ok: false,
            error_code: Some(code.as_str()),
        });
        return Err(error);
    }

    validate_review_input(provider_id, repository_path)?;

    let cancel = AtomicBool::new(false);
    let mut response = String::new();
    let result = run_review_pipeline(
        provider_id,
        repository_path,
        prompt,
        diff_scope_path,
        &cancel,
        |chunk| {
            response.push_str(chunk);
        },
    );

    let error_code = result
        .as_ref()
        .err()
        .map(|error| error.to_command_error().code);
    let _ = ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
        event: "review.run",
        provider_id,
        repository_path,
        diff_scope_path,
        prompt,
        output: &response,
        ok: result.is_ok(),
        error_code: error_code.as_deref(),
    });

    result?;

    Ok(AiDiffReviewData {
        provider_id: provider_id.to_string(),
        response,
    })
}

pub fn start_diff_review_job(
    state: &AppState,
    provider_id: &str,
    repository_path: &str,
    prompt: &str,
    diff_scope_path: Option<&str>,
) -> Result<AiDiffReviewJobStartData, AppError> {
    if let Err(error) = enforce_guardrail_for_review(prompt) {
        let code = error.to_command_error().code;
        let _ = ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
            event: "review.guardrail.blocked",
            provider_id,
            repository_path,
            diff_scope_path,
            prompt,
            output: "",
            ok: false,
            error_code: Some(code.as_str()),
        });
        return Err(error);
    }

    validate_review_input(provider_id, repository_path)?;

    let job_id = Uuid::new_v4().to_string();
    let record = Arc::new(Mutex::new(AiReviewJobRecord {
        status: AiReviewJobState::Queued,
        output: String::new(),
        error: None,
        cancel_flag: Arc::new(AtomicBool::new(false)),
        provider_id: provider_id.to_string(),
        repository_path: repository_path.to_string(),
        diff_scope_path: diff_scope_path.map(|value| value.to_string()),
        prompt: prompt.to_string(),
    }));

    {
        let mut jobs = state
            .ai_review_jobs
            .lock()
            .map_err(|_| AppError::Internal("failed to lock AI review job map".to_string()))?;

        jobs.retain(|_, value| {
            value
                .lock()
                .map(|entry| !entry.status.is_terminal())
                .unwrap_or(false)
        });

        if jobs.len() >= MAX_RETAINED_JOBS {
            return Err(AppError::Internal(
                "too many active AI review jobs; try again after some finish".to_string(),
            ));
        }

        jobs.insert(job_id.clone(), Arc::clone(&record));
    }

    let _ = ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
        event: "review.job.start",
        provider_id,
        repository_path,
        diff_scope_path,
        prompt,
        output: "",
        ok: true,
        error_code: None,
    });

    spawn_review_worker(
        record,
        provider_id.to_string(),
        repository_path.to_string(),
        prompt.to_string(),
        diff_scope_path.map(|value| value.to_string()),
    );

    Ok(AiDiffReviewJobStartData { job_id })
}

pub fn get_diff_review_job(
    state: &AppState,
    job_id: &str,
) -> Result<AiDiffReviewJobData, AppError> {
    if job_id.trim().is_empty() {
        return Err(AppError::InvalidInput("job id is required".to_string()));
    }

    let record = {
        let jobs = state
            .ai_review_jobs
            .lock()
            .map_err(|_| AppError::Internal("failed to lock AI review job map".to_string()))?;
        jobs.get(job_id)
            .cloned()
            .ok_or_else(|| AppError::InvalidInput(format!("unknown AI review job id: {job_id}")))?
    };

    let record = record
        .lock()
        .map_err(|_| AppError::Internal("failed to lock AI review job entry".to_string()))?;

    Ok(AiDiffReviewJobData {
        job_id: job_id.to_string(),
        status: record.status.as_str().to_string(),
        output: record.output.clone(),
        error: record.error.clone(),
        done: record.status.is_terminal(),
    })
}

pub fn cancel_diff_review_job(
    state: &AppState,
    job_id: &str,
) -> Result<AiDiffReviewCancelData, AppError> {
    if job_id.trim().is_empty() {
        return Err(AppError::InvalidInput("job id is required".to_string()));
    }

    let record = {
        let jobs = state
            .ai_review_jobs
            .lock()
            .map_err(|_| AppError::Internal("failed to lock AI review job map".to_string()))?;
        jobs.get(job_id)
            .cloned()
            .ok_or_else(|| AppError::InvalidInput(format!("unknown AI review job id: {job_id}")))?
    };

    let mut record = record
        .lock()
        .map_err(|_| AppError::Internal("failed to lock AI review job entry".to_string()))?;

    if record.status.is_terminal() {
        return Ok(AiDiffReviewCancelData {
            job_id: job_id.to_string(),
            canceled: false,
        });
    }

    record.cancel_flag.store(true, Ordering::Relaxed);
    record.status = AiReviewJobState::Canceled;
    record.output.push_str("\nReview canceled by user.\n");

    let _ = ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
        event: "review.job.cancel",
        provider_id: &record.provider_id,
        repository_path: &record.repository_path,
        diff_scope_path: record.diff_scope_path.as_deref(),
        prompt: &record.prompt,
        output: &record.output,
        ok: false,
        error_code: Some("ai.job_canceled"),
    });

    Ok(AiDiffReviewCancelData {
        job_id: job_id.to_string(),
        canceled: true,
    })
}

fn spawn_review_worker(
    record: SharedAiReviewJob,
    provider_id: String,
    repository_path: String,
    prompt: String,
    diff_scope_path: Option<String>,
) {
    thread::spawn(move || {
        if let Ok(mut job) = record.lock() {
            if job.status == AiReviewJobState::Canceled {
                return;
            }
            job.status = AiReviewJobState::Running;
        }

        let cancel_flag = match record.lock() {
            Ok(job) => Arc::clone(&job.cancel_flag),
            Err(_) => return,
        };

        let result = run_review_pipeline(
            &provider_id,
            &repository_path,
            &prompt,
            diff_scope_path.as_deref(),
            &cancel_flag,
            |chunk| {
                if let Ok(mut job) = record.lock() {
                    job.output.push_str(chunk);
                }
            },
        );

        if let Ok(mut job) = record.lock() {
            if job.status == AiReviewJobState::Canceled || cancel_flag.load(Ordering::Relaxed) {
                job.status = AiReviewJobState::Canceled;
                let _ =
                    ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
                        event: "review.job.finish",
                        provider_id: &job.provider_id,
                        repository_path: &job.repository_path,
                        diff_scope_path: job.diff_scope_path.as_deref(),
                        prompt: &job.prompt,
                        output: &job.output,
                        ok: false,
                        error_code: Some("ai.job_canceled"),
                    });
                return;
            }

            let (audit_ok, audit_error_code) = match result {
                Ok(()) => {
                    job.status = AiReviewJobState::Completed;
                    (true, None)
                }
                Err(error) => {
                    job.status = AiReviewJobState::Failed;
                    job.error = Some(error.to_string());
                    (false, Some(error.to_command_error().code))
                }
            };

            let _ = ai_audit_service::record_ai_audit_event(ai_audit_service::AiAuditEventInput {
                event: "review.job.finish",
                provider_id: &job.provider_id,
                repository_path: &job.repository_path,
                diff_scope_path: job.diff_scope_path.as_deref(),
                prompt: &job.prompt,
                output: &job.output,
                ok: audit_ok,
                error_code: audit_error_code.as_deref(),
            });
        }
    });
}

fn validate_review_input(provider_id: &str, repository_path: &str) -> Result<(), AppError> {
    if !Path::new(repository_path).exists() {
        return Err(AppError::RepositoryPathMissing);
    }

    if provider_id.trim().is_empty() {
        return Err(AppError::InvalidInput(
            "provider id is required".to_string(),
        ));
    }

    if provider_adapter(provider_id).is_none() {
        return Err(AppError::AiProviderUnavailable(provider_id.to_string()));
    }

    Ok(())
}

fn enforce_guardrail_for_review(prompt: &str) -> Result<(), AppError> {
    let (guardrail_profile, ai_read_only_default) = match settings_service::get_settings() {
        Ok(settings) => (settings.guardrail_profile, settings.ai_read_only_default),
        Err(_) => ("Balanced".to_string(), true),
    };

    if !ai_read_only_default {
        return Ok(());
    }

    if prompt_requests_write_action(prompt) {
        return Err(AppError::AiGuardrailViolation(format!(
            "{} profile enforces read-only AI reviews; remove write/execute instructions from prompt",
            guardrail_profile
        )));
    }

    Ok(())
}

fn prompt_requests_write_action(prompt: &str) -> bool {
    let normalized = prompt.to_ascii_lowercase();
    let write_intent_markers = [
        "apply patch",
        "write file",
        "edit file",
        "modify file",
        "create file",
        "delete file",
        "run command",
        "execute command",
        "execute shell",
        "git commit",
        "git push",
        "rewrite this file",
    ];

    write_intent_markers
        .iter()
        .any(|marker| normalized.contains(marker))
}

fn run_review_pipeline<F>(
    provider_id: &str,
    repository_path: &str,
    prompt: &str,
    diff_scope_path: Option<&str>,
    cancel_flag: &AtomicBool,
    mut emit: F,
) -> Result<(), AppError>
where
    F: FnMut(&str),
{
    let adapter = provider_adapter(provider_id)
        .ok_or_else(|| AppError::AiProviderUnavailable(provider_id.to_string()))?;
    let availability = inspect_provider(&adapter);
    let normalized_scope_path = diff_scope_path.and_then(trimmed_non_empty);
    let diff = collect_diff(repository_path, normalized_scope_path)?;

    if let Some(scope_path) = normalized_scope_path {
        emit(&format!("Scoped review path: {scope_path}\n"));
    }

    if cancel_flag.load(Ordering::Relaxed) {
        return Err(cancel_error());
    }

    if let Some(resolution) = availability.resolution.as_ref() {
        emit(&format!(
            "Resolved provider binary '{}' via {} ({}).\n",
            resolution.command, resolution.source, resolution.health_check
        ));
        emit(&format!("Provider auth status: {}.\n", availability.auth.detail));
    }

    if availability.ready {
        let resolved_command = availability
            .resolution
            .as_ref()
            .map(|value| value.command.clone())
            .unwrap_or_else(|| adapter.binary_name().to_string());
        match run_provider_review(
            &adapter,
            resolved_command.as_str(),
            repository_path,
            prompt,
            &diff,
            cancel_flag,
            &mut emit,
        ) {
            Ok(true) => return Ok(()),
            Ok(false) => {
                emit("Provider output unavailable or empty; switching to deterministic local fallback review.\n");
            }
            Err(error) => {
                if is_cancel_error(&error) {
                    return Err(error);
                }
                emit(&format!(
                    "Provider execution error ({error}); switching to deterministic local fallback review.\n"
                ));
            }
        }
    } else {
        emit("Provider is not ready for CLI piggybacking; using deterministic local fallback review.\n");
        emit(&format!("Readiness detail: {}\n", format_provider_health(&availability)));
    }

    run_fallback_review(
        adapter.id(),
        adapter.binary_name(),
        prompt,
        &diff,
        cancel_flag,
        emit,
    )
}

fn collect_diff(repository_path: &str, diff_scope_path: Option<&str>) -> Result<String, AppError> {
    if let Some(scope_path) = diff_scope_path {
        let output = git_provider::run_git(
            Some(repository_path),
            &["diff", "--no-color", "--", scope_path],
        )?;
        return Ok(output.stdout);
    }

    let output = git_provider::run_git(Some(repository_path), &["diff", "--no-color"])?;
    Ok(output.stdout)
}

fn run_provider_review<F>(
    adapter: &dyn AiProviderAdapter,
    binary: &str,
    repository_path: &str,
    prompt: &str,
    diff: &str,
    cancel_flag: &AtomicBool,
    emit: &mut F,
) -> Result<bool, AppError>
where
    F: FnMut(&str),
{
    let attempts = adapter.build_attempts(prompt, diff);
    if attempts.is_empty() {
        return Ok(false);
    }

    emit(&format!(
        "AI review started with provider binary '{binary}'.\n"
    ));

    for attempt in attempts {
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(cancel_error());
        }

        emit(&format!(
            "Running provider adapter attempt: {}\n",
            attempt.name
        ));
        match execute_provider_attempt(adapter, binary, repository_path, &attempt, cancel_flag, emit) {
            Ok(true) => {
                emit("Provider review completed.\n");
                return Ok(true);
            }
            Ok(false) => {
                emit("Adapter attempt did not yield usable output.\n");
            }
            Err(error) => {
                if is_cancel_error(&error) {
                    return Err(error);
                }
                emit(&format!("Adapter attempt failed: {error}\n"));
            }
        }
    }

    Ok(false)
}

fn execute_provider_attempt<F>(
    adapter: &dyn AiProviderAdapter,
    binary: &str,
    repository_path: &str,
    attempt: &ProviderAttempt,
    cancel_flag: &AtomicBool,
    emit: &mut F,
) -> Result<bool, AppError>
where
    F: FnMut(&str),
{
    let mut command = Command::new(binary);
    command
        .current_dir(repository_path)
        .args(attempt.args.iter().map(String::as_str))
        .env("NO_COLOR", "1")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    set_provider_environment(adapter.kind(), &mut command);

    if attempt.stdin_payload.is_some() {
        command.stdin(Stdio::piped());
    } else {
        command.stdin(Stdio::null());
    }

    let mut child = command.spawn().map_err(|error| {
        AppError::AiProcessFailed(format!("failed to start provider process: {error}"))
    })?;

    if let Some(payload) = &attempt.stdin_payload {
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(payload.as_bytes()).map_err(|error| {
                AppError::AiProcessFailed(format!("failed to write provider input: {error}"))
            })?;
        }
    }

    let (tx, rx) = mpsc::channel::<StreamChunk>();

    if let Some(stdout) = child.stdout.take() {
        spawn_stream_reader(stdout, StreamSource::Stdout, tx.clone());
    }
    if let Some(stderr) = child.stderr.take() {
        spawn_stream_reader(stderr, StreamSource::Stderr, tx.clone());
    }
    drop(tx);

    let started_at = Instant::now();
    let mut stdout_output = String::new();
    let mut stderr_output = String::new();

    loop {
        if cancel_flag.load(Ordering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(cancel_error());
        }

        while let Ok(chunk) = rx.try_recv() {
            match chunk.source {
                StreamSource::Stdout => {
                    stdout_output.push_str(&chunk.text);
                }
                StreamSource::Stderr => {
                    if stderr_output.len() < 32_768 {
                        stderr_output.push_str(&chunk.text);
                    }
                }
            }
        }

        if started_at.elapsed() > MAX_PROVIDER_RUNTIME {
            let _ = child.kill();
            let _ = child.wait();
            return Ok(false);
        }

        if let Some(status) = child
            .try_wait()
            .map_err(|error| AppError::AiProcessFailed(format!("provider wait failed: {error}")))?
        {
            let drain_until = Instant::now() + Duration::from_millis(200);
            while Instant::now() < drain_until {
                match rx.recv_timeout(Duration::from_millis(25)) {
                    Ok(chunk) => match chunk.source {
                        StreamSource::Stdout => {
                            stdout_output.push_str(&chunk.text);
                        }
                        StreamSource::Stderr => {
                            if stderr_output.len() < 32_768 {
                                stderr_output.push_str(&chunk.text);
                            }
                        }
                    },
                    Err(mpsc::RecvTimeoutError::Timeout) => break,
                    Err(mpsc::RecvTimeoutError::Disconnected) => break,
                }
            }

            let formatted_output = format_provider_output(
                attempt.output_mode,
                &stdout_output,
                &stderr_output,
            );

            if !status.success() {
                if let Some(output) = formatted_output {
                    emit("[provider error]\n");
                    emit(output.trim());
                    emit("\n");
                } else if !stderr_output.trim().is_empty() {
                    emit("[provider error]\n");
                    emit(strip_ansi(stderr_output.trim()).as_str());
                    emit("\n");
                }
                return Ok(false);
            }

            if let Some(output) = formatted_output {
                emit(output.trim());
                emit("\n");
                return Ok(true);
            }

            return Ok(false);
        }

        thread::sleep(Duration::from_millis(60));
    }
}

fn spawn_stream_reader<R>(mut reader: R, source: StreamSource, tx: mpsc::Sender<StreamChunk>)
where
    R: Read + Send + 'static,
{
    thread::spawn(move || {
        let mut buffer = [0_u8; 2048];
        loop {
            match reader.read(&mut buffer) {
                Ok(0) => break,
                Ok(bytes_read) => {
                    let text = String::from_utf8_lossy(&buffer[..bytes_read]).to_string();
                    if tx.send(StreamChunk { source, text }).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });
}

fn build_provider_attempts(kind: ProviderKind, prompt: &str, diff: &str) -> Vec<ProviderAttempt> {
    let stdin_payload = build_stdin_payload(prompt, diff);
    match kind {
        ProviderKind::Codex => vec![
            ProviderAttempt {
                name: "codex exec --json -",
                args: vec!["exec".to_string(), "--json".to_string(), "-".to_string()],
                stdin_payload: Some(stdin_payload.clone()),
                output_mode: ProviderOutputMode::CodexJsonl,
            },
            ProviderAttempt {
                name: "codex exec -",
                args: vec!["exec".to_string(), "-".to_string()],
                stdin_payload: Some(stdin_payload),
                output_mode: ProviderOutputMode::PlainText,
            },
        ],
        ProviderKind::Claude => vec![
            ProviderAttempt {
                name: "claude -p --output-format json",
                args: vec![
                    "-p".to_string(),
                    "--output-format".to_string(),
                    "json".to_string(),
                ],
                stdin_payload: Some(stdin_payload.clone()),
                output_mode: ProviderOutputMode::ClaudeJson,
            },
            ProviderAttempt {
                name: "claude -p",
                args: vec!["-p".to_string()],
                stdin_payload: Some(stdin_payload),
                output_mode: ProviderOutputMode::PlainText,
            },
        ],
        ProviderKind::Gemini => vec![
            ProviderAttempt {
                name: "npx --yes @google/gemini-cli -o json",
                args: vec![
                    "--yes".to_string(),
                    "@google/gemini-cli".to_string(),
                    "-p".to_string(),
                    "".to_string(),
                    "-o".to_string(),
                    "json".to_string(),
                    "-m".to_string(),
                    "auto-gemini-3".to_string(),
                ],
                stdin_payload: Some(stdin_payload.clone()),
                output_mode: ProviderOutputMode::GeminiJson,
            },
            ProviderAttempt {
                name: "npx --yes @google/gemini-cli",
                args: vec![
                    "--yes".to_string(),
                    "@google/gemini-cli".to_string(),
                    "-p".to_string(),
                    "".to_string(),
                    "-m".to_string(),
                    "auto-gemini-3".to_string(),
                ],
                stdin_payload: Some(stdin_payload),
                output_mode: ProviderOutputMode::PlainText,
            },
        ],
        ProviderKind::OpenCode => vec![
            ProviderAttempt {
                name: "opencode run --format json",
                args: vec![
                    "run".to_string(),
                    "--format".to_string(),
                    "json".to_string(),
                    "-m".to_string(),
                    "opencode/big-pickle".to_string(),
                ],
                stdin_payload: Some(stdin_payload.clone()),
                output_mode: ProviderOutputMode::OpenCodeJsonl,
            },
            ProviderAttempt {
                name: "opencode run",
                args: vec![
                    "run".to_string(),
                    "-m".to_string(),
                    "opencode/big-pickle".to_string(),
                ],
                stdin_payload: Some(stdin_payload),
                output_mode: ProviderOutputMode::PlainText,
            },
        ],
    }
}

fn set_provider_environment(kind: ProviderKind, command: &mut Command) {
    match kind {
        ProviderKind::Claude => {
            command.env("CLAUDE_CODE_ENTRYPOINT", "cli");
        }
        ProviderKind::Gemini => {
            command.env("CI", "1");
        }
        ProviderKind::Codex | ProviderKind::OpenCode => {}
    }
}

fn format_provider_output(
    mode: ProviderOutputMode,
    stdout: &str,
    stderr: &str,
) -> Option<String> {
    match mode {
        ProviderOutputMode::PlainText => {
            let stdout = strip_ansi(stdout.trim());
            if !stdout.is_empty() {
                return Some(stdout);
            }
            let stderr = strip_ansi(stderr.trim());
            if !stderr.is_empty() {
                return Some(stderr);
            }
            None
        }
        ProviderOutputMode::CodexJsonl => parse_codex_jsonl(stdout).or_else(|| {
            let stderr = strip_ansi(stderr.trim());
            if stderr.is_empty() {
                None
            } else {
                Some(stderr)
            }
        }),
        ProviderOutputMode::ClaudeJson => parse_claude_json(stdout).or_else(|| {
            let fallback = strip_ansi(stdout.trim());
            if !fallback.is_empty() {
                return Some(fallback);
            }
            let stderr = strip_ansi(stderr.trim());
            if stderr.is_empty() {
                None
            } else {
                Some(stderr)
            }
        }),
        ProviderOutputMode::GeminiJson => parse_gemini_json(stdout).or_else(|| {
            let fallback = strip_ansi(stdout.trim());
            if !fallback.is_empty() {
                return Some(fallback);
            }
            let stderr = strip_ansi(stderr.trim());
            if stderr.is_empty() {
                None
            } else {
                Some(stderr)
            }
        }),
        ProviderOutputMode::OpenCodeJsonl => parse_opencode_jsonl(stdout).or_else(|| {
            let fallback = strip_ansi(stdout.trim());
            if !fallback.is_empty() {
                return Some(fallback);
            }
            let stderr = strip_ansi(stderr.trim());
            if stderr.is_empty() {
                None
            } else {
                Some(stderr)
            }
        }),
    }
}

fn parse_codex_jsonl(stdout: &str) -> Option<String> {
    let mut response = String::new();
    let mut error_message = String::new();

    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        let Some(kind) = value.get("type").and_then(Value::as_str) else {
            continue;
        };

        match kind {
            "item.completed" => {
                if let Some(text) = value
                    .get("item")
                    .and_then(|item| item.get("text"))
                    .and_then(Value::as_str)
                {
                    response = text.to_string();
                }
            }
            "error" | "turn.failed" => {
                if let Some(message) = value.get("message").and_then(Value::as_str) {
                    error_message = message.to_string();
                } else if let Some(message) = value
                    .get("error")
                    .and_then(|error| error.get("message"))
                    .and_then(Value::as_str)
                {
                    error_message = message.to_string();
                }
            }
            _ => {}
        }
    }

    if !response.trim().is_empty() {
        return Some(response);
    }
    if !error_message.trim().is_empty() {
        return Some(format!("Codex error: {}", strip_ansi(error_message.trim())));
    }

    let fallback = strip_ansi(stdout.trim());
    if fallback.is_empty() {
        None
    } else {
        Some(fallback)
    }
}

fn parse_claude_json(stdout: &str) -> Option<String> {
    let value = serde_json::from_str::<Value>(stdout).ok()?;

    if value
        .get("is_error")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        if let Some(message) = value.get("result").and_then(Value::as_str) {
            return Some(format!("Claude error: {}", strip_ansi(message)));
        }
    }

    if let Some(result) = value.get("result").and_then(Value::as_str) {
        let trimmed = result.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
    }

    None
}

fn parse_gemini_json(stdout: &str) -> Option<String> {
    let value = serde_json::from_str::<Value>(stdout).ok()?;
    if let Some(message) = value
        .get("error")
        .and_then(|error| error.get("message"))
        .and_then(Value::as_str)
    {
        return Some(format!("Gemini error: {}", strip_ansi(message)));
    }

    if let Some(response) = value.get("response").and_then(Value::as_str) {
        let trimmed = response.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
    }

    None
}

fn parse_opencode_jsonl(stdout: &str) -> Option<String> {
    let mut response = String::new();

    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        let Some(kind) = value.get("type").and_then(Value::as_str) else {
            continue;
        };

        if kind == "text" {
            if let Some(text) = value
                .get("part")
                .and_then(|part| part.get("text"))
                .and_then(Value::as_str)
            {
                response.push_str(text);
            }
        }
    }

    let trimmed = response.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn strip_ansi(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut chars = value.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch == '\u{1b}' {
            if matches!(chars.peek(), Some('[')) {
                let _ = chars.next();
                while let Some(next) = chars.next() {
                    if ('@'..='~').contains(&next) {
                        break;
                    }
                }
                continue;
            }
        }

        result.push(ch);
    }

    result
}

#[cfg(test)]
fn build_inline_prompt(prompt: &str, diff: &str) -> String {
    let diff_excerpt = truncate_chars(diff, MAX_INLINE_DIFF_CHARS);
    format!(
        "{}\n\nReview this git diff excerpt and provide actionable findings:\n\n{}",
        prompt.trim(),
        diff_excerpt
    )
}

fn build_stdin_payload(prompt: &str, diff: &str) -> String {
    let bounded_diff = truncate_chars(diff, MAX_STDIN_DIFF_CHARS);
    format!(
        "Task: {}\n\nRepository diff follows. Provide a concise review with risks, regressions, and suggestions.\n\n{}",
        prompt.trim(),
        bounded_diff
    )
}

fn truncate_chars(value: &str, max_chars: usize) -> String {
    let mut iter = value.chars();
    let truncated: String = iter.by_ref().take(max_chars).collect();
    if iter.next().is_some() {
        return format!(
            "{truncated}\n\n[...diff truncated to {max_chars} characters for adapter input...]"
        );
    }
    truncated
}

fn run_fallback_review<F>(
    provider_id: &str,
    binary: &str,
    prompt: &str,
    diff: &str,
    cancel_flag: &AtomicBool,
    mut emit: F,
) -> Result<(), AppError>
where
    F: FnMut(&str),
{
    let mut changed_files = 0_u32;
    let mut additions = 0_u32;
    let mut deletions = 0_u32;
    let mut todo_hits = 0_u32;
    let mut fixme_hits = 0_u32;
    let mut unwrap_hits = 0_u32;
    let mut panic_hits = 0_u32;

    for line in diff.lines() {
        if line.starts_with("diff --git ") {
            changed_files += 1;
            continue;
        }
        if line.starts_with('+') && !line.starts_with("+++") {
            additions += 1;
        }
        if line.starts_with('-') && !line.starts_with("---") {
            deletions += 1;
        }

        let lowercase = line.to_ascii_lowercase();
        if lowercase.contains("todo") {
            todo_hits += 1;
        }
        if lowercase.contains("fixme") {
            fixme_hits += 1;
        }
        if lowercase.contains("unwrap(") {
            unwrap_hits += 1;
        }
        if lowercase.contains("panic!(") {
            panic_hits += 1;
        }
    }

    let mut chunks = Vec::new();
    chunks.push(format!(
        "AI review started with provider '{provider_id}'.\n"
    ));
    chunks.push(format!(
        "Fallback mode active for provider binary '{binary}'.\n"
    ));
    chunks.push(format!("Prompt summary: {}\n", prompt.trim()));

    if diff.trim().is_empty() {
        chunks.push("No local diff detected. Nothing to review.\n".to_string());
    } else {
        chunks.push(format!(
            "Diff summary: files={changed_files}, additions={additions}, deletions={deletions}.\n"
        ));
        if unwrap_hits > 0 || panic_hits > 0 {
            chunks.push(format!(
                "Risk signals: unwrap={unwrap_hits}, panic={panic_hits}. Review error handling paths.\n"
            ));
        }
        if todo_hits > 0 || fixme_hits > 0 {
            chunks.push(format!(
                "Maintenance signals: TODO={todo_hits}, FIXME={fixme_hits}. Consider follow-up tasks.\n"
            ));
        }
        chunks.push(
            "Fallback review complete. Integrate provider-specific adapters for semantic model output.\n"
                .to_string(),
        );
    }

    for chunk in chunks {
        if cancel_flag.load(Ordering::Relaxed) {
            return Err(cancel_error());
        }
        emit(&chunk);
        thread::sleep(Duration::from_millis(150));
    }

    Ok(())
}

fn cancel_error() -> AppError {
    AppError::CommandExecution("review canceled".to_string())
}

fn is_cancel_error(error: &AppError) -> bool {
    matches!(error, AppError::CommandExecution(message) if message == "review canceled")
}

fn trimmed_non_empty(value: &str) -> Option<&str> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }

    Some(trimmed)
}

#[cfg(test)]
fn provider_binary_name(provider_id: &str) -> Option<&'static str> {
    provider_adapter(provider_id).map(|adapter| adapter.binary_name())
}

fn inspect_provider(adapter: &dyn AiProviderAdapter) -> ProviderAvailability {
    let resolution = resolve_provider_command(adapter.binary_name());
    let auth = adapter.auth_status();
    let ready = resolution.is_some() && auth.ok;

    ProviderAvailability {
        ready,
        resolution,
        auth,
    }
}

fn format_provider_health(availability: &ProviderAvailability) -> String {
    let binary = availability
        .resolution
        .as_ref()
        .map(|value| value.health_check.clone())
        .unwrap_or_else(|| "binary unavailable".to_string());

    format!("{binary}; auth={}", availability.auth.detail)
}

fn provider_auth_status(kind: ProviderKind) -> ProviderAuthStatus {
    match kind {
        ProviderKind::Codex => codex_auth_status(),
        ProviderKind::Claude => claude_auth_status(),
        ProviderKind::Gemini => gemini_auth_status(),
        ProviderKind::OpenCode => opencode_auth_status(),
    }
}

fn codex_auth_status() -> ProviderAuthStatus {
    let auth_file = codex_auth_path();
    let Some(value) = read_json_file(auth_file.as_path()) else {
        return ProviderAuthStatus {
            ok: false,
            detail: "missing ~/.codex/auth.json".to_string(),
            plan_name: None,
        };
    };

    let plan_name = value
        .get("tokens")
        .and_then(|tokens| tokens.get("id_token"))
        .and_then(Value::as_str)
        .and_then(extract_codex_plan_from_id_token)
        .map(|plan| humanize_label(plan.as_str()));

    let has_token = value
        .get("tokens")
        .and_then(|tokens| tokens.get("id_token").or_else(|| tokens.get("access_token")))
        .and_then(Value::as_str)
        .map(|token| !token.trim().is_empty())
        .unwrap_or(false);

    ProviderAuthStatus {
        ok: has_token,
        detail: if has_token {
            match plan_name.as_deref() {
                Some(plan) => format!("codex auth token found ({plan})"),
                None => "codex auth token found".to_string(),
            }
        } else {
            "codex token missing".to_string()
        },
        plan_name,
    }
}

fn claude_auth_status() -> ProviderAuthStatus {
    let Some(home_dir) = user_home_dir() else {
        return ProviderAuthStatus {
            ok: false,
            detail: "home directory unavailable".to_string(),
            plan_name: None,
        };
    };

    let credentials_path = home_dir.join(".claude").join(".credentials.json");
    let Some(value) = read_json_file(credentials_path.as_path()) else {
        return ProviderAuthStatus {
            ok: false,
            detail: "missing ~/.claude/.credentials.json".to_string(),
            plan_name: None,
        };
    };

    let oauth = value.get("claudeAiOauth").cloned().unwrap_or(Value::Null);
    let token_ok = oauth
        .get("accessToken")
        .and_then(Value::as_str)
        .map(|token| !token.trim().is_empty())
        .unwrap_or(false);
    let inference_scope = oauth
        .get("scopes")
        .and_then(Value::as_array)
        .map(|scopes| scopes.iter().any(|scope| scope.as_str() == Some("user:inference")))
        .unwrap_or(false);
    let subscription = oauth
        .get("subscriptionType")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let ok = token_ok && inference_scope;
    let plan_name = if ok {
        Some(humanize_label(subscription))
    } else {
        None
    };

    ProviderAuthStatus {
        ok,
        detail: if ok {
            format!("claude oauth ready ({subscription})")
        } else {
            "claude oauth missing token or user:inference scope".to_string()
        },
        plan_name,
    }
}

fn gemini_auth_status() -> ProviderAuthStatus {
    let Some(home_dir) = user_home_dir() else {
        return ProviderAuthStatus {
            ok: false,
            detail: "home directory unavailable".to_string(),
            plan_name: None,
        };
    };

    let credentials_path = home_dir.join(".gemini").join("oauth_creds.json");
    let Some(value) = read_json_file(credentials_path.as_path()) else {
        return ProviderAuthStatus {
            ok: false,
            detail: "missing ~/.gemini/oauth_creds.json".to_string(),
            plan_name: None,
        };
    };

    let has_token = value
        .get("access_token")
        .and_then(Value::as_str)
        .map(|token| !token.trim().is_empty())
        .unwrap_or(false);
    let plan_name = if has_token {
        gemini_account_label(home_dir.as_path()).or_else(|| Some("Google AI".to_string()))
    } else {
        None
    };

    ProviderAuthStatus {
        ok: has_token,
        detail: if has_token {
            "gemini oauth token found".to_string()
        } else {
            "gemini oauth token missing".to_string()
        },
        plan_name,
    }
}

fn opencode_auth_status() -> ProviderAuthStatus {
    let auth_candidates = opencode_auth_paths();
    for path in auth_candidates {
        let Some(value) = read_json_file(path.as_path()) else {
            continue;
        };

        let provider_count = value
            .as_object()
            .map(|providers| providers.len())
            .unwrap_or(0);

        if provider_count > 0 {
            return ProviderAuthStatus {
                ok: true,
                detail: format!("opencode connected providers={provider_count}"),
                plan_name: Some(format!(
                    "{provider_count} provider{}",
                    if provider_count == 1 { "" } else { "s" }
                )),
            };
        }

        return ProviderAuthStatus {
            ok: true,
            detail: "opencode auth file present".to_string(),
            plan_name: Some("Connected".to_string()),
        };
    }

    ProviderAuthStatus {
        ok: true,
        detail: "opencode auth managed by CLI".to_string(),
        plan_name: Some("Connected".to_string()),
    }
}

fn extract_codex_plan_from_id_token(id_token: &str) -> Option<String> {
    let payload_segment = id_token.split('.').nth(1)?;
    let payload_bytes = decode_base64url(payload_segment)?;
    let payload_text = String::from_utf8(payload_bytes).ok()?;
    let payload = serde_json::from_str::<Value>(&payload_text).ok()?;

    payload
        .get("https://api.openai.com/auth")
        .and_then(|auth| auth.get("chatgpt_plan_type"))
        .and_then(Value::as_str)
        .map(|value| value.to_string())
}

fn gemini_account_label(home_dir: &Path) -> Option<String> {
    let settings_path = home_dir.join(".gemini").join("settings.json");
    let settings = read_json_file(settings_path.as_path())?;
    let selected = settings
        .get("security")
        .and_then(|security| security.get("auth"))
        .and_then(|auth| auth.get("selectedType"))
        .and_then(Value::as_str)?;

    Some(
        match selected {
            "oauth-personal" => "Google AI",
            "oauth-adc" => "Cloud ADC",
            "service-account" => "Service Account",
            "api-key" => "API Key",
            _ => "Connected",
        }
        .to_string(),
    )
}

fn humanize_label(value: &str) -> String {
    value
        .split(['-', '_', ' '])
        .filter(|segment| !segment.is_empty())
        .map(|segment| {
            let mut chars = segment.chars();
            match chars.next() {
                Some(first) => {
                    let mut part = String::new();
                    part.push(first.to_ascii_uppercase());
                    part.push_str(chars.as_str().to_ascii_lowercase().as_str());
                    part
                }
                None => String::new(),
            }
        })
        .collect::<Vec<String>>()
        .join(" ")
}

fn decode_base64url(value: &str) -> Option<Vec<u8>> {
    let mut normalized = String::with_capacity(value.len() + 4);
    for ch in value.chars() {
        match ch {
            '-' => normalized.push('+'),
            '_' => normalized.push('/'),
            _ => normalized.push(ch),
        }
    }

    let remainder = normalized.len() % 4;
    if remainder != 0 {
        normalized.push_str("=".repeat(4 - remainder).as_str());
    }

    decode_base64_standard(normalized.as_bytes())
}

fn decode_base64_standard(input: &[u8]) -> Option<Vec<u8>> {
    let mut output = Vec::with_capacity((input.len() * 3) / 4);
    let mut accumulator: u32 = 0;
    let mut bits: u8 = 0;

    for byte in input {
        if *byte == b'=' {
            break;
        }

        let value = match byte {
            b'A'..=b'Z' => *byte - b'A',
            b'a'..=b'z' => *byte - b'a' + 26,
            b'0'..=b'9' => *byte - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'\r' | b'\n' | b'\t' | b' ' => continue,
            _ => return None,
        } as u32;

        accumulator = (accumulator << 6) | value;
        bits += 6;

        while bits >= 8 {
            bits -= 8;
            output.push(((accumulator >> bits) & 0xFF) as u8);
        }
    }

    Some(output)
}

fn codex_auth_path() -> PathBuf {
    if let Ok(codex_home) = std::env::var("CODEX_HOME") {
        return PathBuf::from(codex_home).join("auth.json");
    }

    user_home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".codex")
        .join("auth.json")
}

fn opencode_auth_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    if let Some(home_dir) = user_home_dir() {
        paths.push(home_dir.join(".local").join("share").join("opencode").join("auth.json"));
    }

    if let Ok(app_data) = std::env::var("APPDATA") {
        paths.push(PathBuf::from(app_data).join("opencode").join("auth.json"));
    }

    if let Ok(local_app_data) = std::env::var("LOCALAPPDATA") {
        paths.push(PathBuf::from(local_app_data).join("opencode").join("auth.json"));
    }

    paths
}

fn user_home_dir() -> Option<PathBuf> {
    if let Ok(home) = std::env::var("HOME") {
        if !home.trim().is_empty() {
            return Some(PathBuf::from(home));
        }
    }

    if let Ok(profile) = std::env::var("USERPROFILE") {
        if !profile.trim().is_empty() {
            return Some(PathBuf::from(profile));
        }
    }

    None
}

fn read_json_file(path: &Path) -> Option<Value> {
    let payload = fs::read_to_string(path).ok()?;
    serde_json::from_str::<Value>(&payload).ok()
}

fn resolve_provider_command(binary: &str) -> Option<ProviderResolution> {
    let cache_key = binary.trim().to_ascii_lowercase();
    if let Ok(cache) = provider_resolution_cache().lock() {
        if let Some(entry) = cache.get(cache_key.as_str()) {
            if entry.checked_at.elapsed() < PROVIDER_RESOLUTION_CACHE_TTL {
                return entry.resolution.clone();
            }
        }
    }

    let candidates = known_binary_candidates(binary);
    let mut resolved = None;
    for (command, source) in candidates {
        if let Some(health_check) = probe_binary_health(command.as_str()) {
            resolved = Some(ProviderResolution {
                command,
                source,
                health_check,
            });
            break;
        }
    }

    if let Ok(mut cache) = provider_resolution_cache().lock() {
        cache.insert(
            cache_key,
            ProviderResolutionCacheEntry {
                checked_at: Instant::now(),
                resolution: resolved.clone(),
            },
        );
    }

    resolved
}

fn provider_resolution_cache() -> &'static Mutex<std::collections::HashMap<String, ProviderResolutionCacheEntry>> {
    static CACHE: OnceLock<Mutex<std::collections::HashMap<String, ProviderResolutionCacheEntry>>> =
        OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(std::collections::HashMap::new()))
}

fn known_binary_candidates(binary: &str) -> Vec<(String, String)> {
    let mut candidates = Vec::<(String, String)>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    if cfg!(target_os = "windows") {
        for suffix in ["", ".cmd", ".exe", ".bat"] {
            push_candidate(
                &mut candidates,
                &mut seen,
                format!("{binary}{suffix}"),
                "PATH".to_string(),
            );
        }
    } else {
        push_candidate(
            &mut candidates,
            &mut seen,
            binary.to_string(),
            "PATH".to_string(),
        );
    }

    if cfg!(target_os = "windows") {
        if let Ok(appdata) = std::env::var("APPDATA") {
            let npm_dir = std::path::Path::new(&appdata).join("npm");
            for suffix in ["", ".cmd", ".exe"] {
                let command = npm_dir
                    .join(format!("{binary}{suffix}"))
                    .to_string_lossy()
                    .to_string();
                push_candidate(
                    &mut candidates,
                    &mut seen,
                    command,
                    "APPDATA/npm".to_string(),
                );
            }
        }

        if let Ok(local_appdata) = std::env::var("LOCALAPPDATA") {
            let command = std::path::Path::new(&local_appdata)
                .join("Programs")
                .join(binary)
                .join(format!("{binary}.exe"))
                .to_string_lossy()
                .to_string();
            push_candidate(
                &mut candidates,
                &mut seen,
                command,
                "LOCALAPPDATA/Programs".to_string(),
            );
        }

        if let Ok(user_profile) = std::env::var("USERPROFILE") {
            let local_bin = std::path::Path::new(&user_profile)
                .join(".local")
                .join("bin");
            for suffix in ["", ".exe"] {
                let command = local_bin
                    .join(format!("{binary}{suffix}"))
                    .to_string_lossy()
                    .to_string();
                push_candidate(
                    &mut candidates,
                    &mut seen,
                    command,
                    "USERPROFILE/.local/bin".to_string(),
                );
            }
        }
    } else {
        for base in [
            "/usr/local/bin",
            "/usr/bin",
            "/opt/homebrew/bin",
            "/opt/bin",
        ] {
            let command = std::path::Path::new(base)
                .join(binary)
                .to_string_lossy()
                .to_string();
            push_candidate(
                &mut candidates,
                &mut seen,
                command,
                format!("known-path:{base}"),
            );
        }
    }

    candidates
}

fn push_candidate(
    candidates: &mut Vec<(String, String)>,
    seen: &mut std::collections::HashSet<String>,
    command: String,
    source: String,
) {
    if command.trim().is_empty() {
        return;
    }

    let key = command.to_ascii_lowercase();
    if seen.insert(key) {
        candidates.push((command, source));
    }
}

fn probe_binary_health(command: &str) -> Option<String> {
    const HEALTH_CHECKS: [&[&str]; 4] = [&["--version"], &["version"], &["-v"], &["--help"]];

    for args in HEALTH_CHECKS {
        let result = Command::new(command).args(args).output();
        if let Ok(output) = result {
            if output.status.success() {
                return Some(format!("ok({})", args.join(" ")));
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;
    use std::fs;

    use uuid::Uuid;

    use crate::errors::AppError;

    use super::{
        build_inline_prompt, build_provider_attempts, build_stdin_payload,
        enforce_guardrail_for_review, known_binary_candidates, prompt_requests_write_action,
        provider_adapters, provider_binary_name, push_candidate, AiProviderAdapter, ProviderKind,
        validate_review_input, MAX_INLINE_DIFF_CHARS, MAX_STDIN_DIFF_CHARS, PROVIDER_BINARIES,
    };

    #[test]
    fn provider_binary_name_maps_all_supported_provider_ids() {
        for (provider_id, expected_binary, _) in PROVIDER_BINARIES {
            assert_eq!(provider_binary_name(provider_id), Some(expected_binary));
        }

        assert_eq!(provider_binary_name("unknown-provider"), None);
    }

    #[test]
    fn provider_adapter_contracts_are_well_formed() {
        let mut ids = HashSet::new();
        for adapter in provider_adapters() {
            assert!(ids.insert(adapter.id()));
            assert!(!adapter.binary_name().trim().is_empty());
            assert!(!adapter.build_attempts("review prompt", "diff body").is_empty());
        }
    }

    #[test]
    fn known_binary_candidates_includes_path_candidate_first() {
        let candidates = known_binary_candidates("codex");
        assert!(!candidates.is_empty());
        assert_eq!(candidates[0].0, "codex");
        assert_eq!(candidates[0].1, "PATH");
    }

    #[test]
    fn push_candidate_deduplicates_case_insensitive_commands() {
        let mut candidates = Vec::<(String, String)>::new();
        let mut seen = HashSet::<String>::new();

        push_candidate(
            &mut candidates,
            &mut seen,
            "CodeX".to_string(),
            "PATH".to_string(),
        );
        push_candidate(
            &mut candidates,
            &mut seen,
            "codex".to_string(),
            "APPDATA/npm".to_string(),
        );

        assert_eq!(candidates.len(), 1);
    }

    #[test]
    fn validate_review_input_returns_provider_unavailable_for_unknown_provider() {
        let temp = std::env::temp_dir().join(format!("gdpu-ai-validate-{}", Uuid::new_v4()));
        fs::create_dir_all(&temp).expect("temp directory should be creatable");

        let result = validate_review_input(
            "unknown-provider",
            temp.to_str().expect("temp path should be valid utf-8"),
        );

        match result {
            Err(AppError::AiProviderUnavailable(provider_id)) => {
                assert_eq!(provider_id, "unknown-provider")
            }
            other => panic!("expected AiProviderUnavailable error, got {other:?}"),
        }

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn build_provider_attempts_exposes_expected_contract_strategies() {
        for kind in [
            ProviderKind::Codex,
            ProviderKind::Claude,
            ProviderKind::Gemini,
            ProviderKind::OpenCode,
        ] {
            let attempts = build_provider_attempts(kind, "review prompt", "diff body");
            assert!(!attempts.is_empty());
            assert!(attempts.iter().any(|attempt| attempt.stdin_payload.is_some()));
        }
    }

    #[test]
    fn prompt_builders_clip_large_diff_payloads() {
        let large_inline_diff = "x".repeat(MAX_INLINE_DIFF_CHARS + 32);
        let inline_prompt = build_inline_prompt("prompt", &large_inline_diff);
        assert!(inline_prompt.contains("truncated to"));

        let large_stdin_diff = "y".repeat(MAX_STDIN_DIFF_CHARS + 64);
        let stdin_payload = build_stdin_payload("prompt", &large_stdin_diff);
        assert!(stdin_payload.contains("truncated to"));
    }

    #[test]
    fn guardrail_write_intent_detection_matches_expected_markers() {
        assert!(prompt_requests_write_action(
            "Please apply patch to write file and then git commit"
        ));
        assert!(!prompt_requests_write_action(
            "Review this diff and highlight regressions"
        ));
    }

    #[test]
    fn enforce_guardrail_blocks_write_intent_prompts() {
        let result = enforce_guardrail_for_review("execute command and write file changes");
        assert!(result.is_err());
    }
}
