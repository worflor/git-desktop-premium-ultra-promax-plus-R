use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

use serde::{Deserialize, Serialize};

const PRETEXT_LAYOUT_VERSION: &str = "pretext-runtime-adapter-v2";
const PRETEXT_RUNTIME_SCRIPT_PATH: &str = "../scripts/pretext-layout-runtime.mjs";
const DEFAULT_LAYOUT_WIDTH_PX: u32 = 1080;
const DEFAULT_LINE_HEIGHT_PX: u32 = 18;
#[cfg(target_os = "windows")]
const DEFAULT_FONT_PROFILE: &str = "13px Consolas";
#[cfg(target_os = "macos")]
const DEFAULT_FONT_PROFILE: &str = "13px Menlo";
#[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
const DEFAULT_FONT_PROFILE: &str = "13px DejaVu Sans Mono";
const MIN_LAYOUT_WIDTH_PX: u32 = 320;
const MAX_LAYOUT_WIDTH_PX: u32 = 4096;
const MIN_LINE_HEIGHT_PX: u32 = 12;
const MAX_LINE_HEIGHT_PX: u32 = 64;
const DEFAULT_MAX_LAYOUT_BYTES: usize = 24 * 1024 * 1024;
const AVERAGE_GLYPH_WIDTH_PX: u32 = 8;
const MAX_RUNTIME_LAYOUT_CACHE_ENTRIES: usize = 128;

#[derive(Debug, Clone)]
pub struct LayoutOptions {
    pub width_px: u32,
    pub font_profile: String,
    pub line_height_px: u32,
}

impl LayoutOptions {
    pub fn from_command_inputs(
        layout_width_px: Option<u32>,
        font_profile: Option<&str>,
        line_height_px: Option<u32>,
    ) -> Self {
        let width_px = layout_width_px
            .unwrap_or(DEFAULT_LAYOUT_WIDTH_PX)
            .clamp(MIN_LAYOUT_WIDTH_PX, MAX_LAYOUT_WIDTH_PX);
        let line_height_px = line_height_px
            .unwrap_or(DEFAULT_LINE_HEIGHT_PX)
            .clamp(MIN_LINE_HEIGHT_PX, MAX_LINE_HEIGHT_PX);
        let font_profile = font_profile
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(resolve_font_profile)
            .unwrap_or_else(|| DEFAULT_FONT_PROFILE.to_string());

        Self {
            width_px,
            font_profile,
            line_height_px,
        }
    }
}

#[derive(Debug, Clone)]
pub struct LayoutSnapshot {
    pub pretext_version: String,
    pub prepare_ms: u64,
    pub layout_ms: u64,
    pub fallback_activated: bool,
    pub fallback_reason: Option<String>,
    pub visual_row_count: u32,
    pub layout_cache_key: String,
}

#[derive(Debug, Clone)]
struct RuntimeLayoutSnapshot {
    pretext_version: String,
    prepare_ms: u64,
    layout_ms: u64,
    visual_row_count: u32,
}

struct PretextRuntimeWorker {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeLayoutRequest<'a> {
    text: &'a str,
    width_px: u32,
    line_height_px: u32,
    font_profile: &'a str,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeLayoutResponse {
    ok: bool,
    pretext_version: Option<String>,
    prepare_ms: Option<f64>,
    layout_ms: Option<f64>,
    line_count: Option<u32>,
    error: Option<String>,
}

pub fn prepare_layout(diff_id: &str, payload: &str, options: &LayoutOptions) -> LayoutSnapshot {
    let layout_cache_key = build_layout_cache_key(
        diff_id,
        options.width_px,
        options.font_profile.as_str(),
        options.line_height_px,
    );

    let max_layout_bytes = max_layout_bytes();
    if payload.len() > max_layout_bytes {
        return fallback_layout(
            payload,
            options,
            layout_cache_key,
            format!(
                "payload exceeds pretext layout budget: {} > {}",
                payload.len(),
                max_layout_bytes
            ),
        );
    }

    if payload.contains('\0') {
        return fallback_layout(
            payload,
            options,
            layout_cache_key,
            "payload contains binary null bytes".to_string(),
        );
    }

    if force_fallback_enabled() {
        return fallback_layout(
            payload,
            options,
            layout_cache_key,
            "forced by GDPU_FORCE_DIFF_FALLBACK=1".to_string(),
        );
    }

    let runtime_cache_key = build_runtime_cache_key(payload, options);
    if let Some(cached_layout) = runtime_layout_cache_get(runtime_cache_key.as_str()) {
        return LayoutSnapshot {
            pretext_version: cached_layout.pretext_version,
            prepare_ms: cached_layout.prepare_ms,
            layout_ms: cached_layout.layout_ms,
            fallback_activated: false,
            fallback_reason: None,
            visual_row_count: cached_layout.visual_row_count,
            layout_cache_key,
        };
    }

    match run_pretext_runtime(payload, options) {
        Ok(runtime_layout) => {
            runtime_layout_cache_insert(runtime_cache_key, runtime_layout.clone());
            LayoutSnapshot {
                pretext_version: runtime_layout.pretext_version,
                prepare_ms: runtime_layout.prepare_ms,
                layout_ms: runtime_layout.layout_ms,
                fallback_activated: false,
                fallback_reason: None,
                visual_row_count: runtime_layout.visual_row_count,
                layout_cache_key,
            }
        }
        Err(error) => fallback_layout(
            payload,
            options,
            layout_cache_key,
            format!("pretext runtime unavailable: {error}"),
        ),
    }
}

fn fallback_layout(
    payload: &str,
    options: &LayoutOptions,
    layout_cache_key: String,
    reason: String,
) -> LayoutSnapshot {
    let prepare_started_at = Instant::now();
    let lines = payload.lines().collect::<Vec<_>>();
    let prepare_ms = prepare_started_at.elapsed().as_millis() as u64;

    let layout_started_at = Instant::now();
    let visual_row_count = lines.len().max(1) as u32;
    let estimated_layout_rows = estimate_visual_rows(&lines, options.width_px);
    let layout_ms = layout_started_at.elapsed().as_millis() as u64;

    LayoutSnapshot {
        pretext_version: PRETEXT_LAYOUT_VERSION.to_string(),
        prepare_ms,
        layout_ms,
        fallback_activated: true,
        fallback_reason: Some(truncate_reason(reason.as_str())),
        visual_row_count: visual_row_count.max(estimated_layout_rows),
        layout_cache_key,
    }
}

fn run_pretext_runtime(
    payload: &str,
    options: &LayoutOptions,
) -> Result<RuntimeLayoutSnapshot, String> {
    if let Some(cached_error) = runtime_unavailable_reason_get() {
        return Err(cached_error);
    }

    let script_path = pretext_runtime_script_path();
    if !script_path.exists() {
        let reason = format!(
            "pretext runtime script missing at {}",
            script_path.to_string_lossy()
        );
        runtime_unavailable_reason_set(reason.clone());
        return Err(reason);
    }

    let request = RuntimeLayoutRequest {
        text: payload,
        width_px: options.width_px,
        line_height_px: options.line_height_px,
        font_profile: options.font_profile.as_str(),
    };

    let request_payload = serde_json::to_string(&request)
        .map_err(|error| format!("failed to serialize pretext runtime request: {error}"))?;

    let response = invoke_pretext_runtime_worker(script_path.as_path(), request_payload.as_str())
        .map_err(|error| {
            runtime_unavailable_reason_set(error.clone());
            error
        })?;

    if !response.ok {
        let reason = response
            .error
            .unwrap_or_else(|| "pretext runtime response marked as not ok".to_string());
        runtime_unavailable_reason_set(reason.clone());
        return Err(reason);
    }

    let pretext_version = response.pretext_version.ok_or_else(|| {
        let reason = "pretext runtime response missing pretextVersion".to_string();
        runtime_unavailable_reason_set(reason.clone());
        reason
    })?;

    Ok(RuntimeLayoutSnapshot {
        pretext_version: format!("pretext@{pretext_version}"),
        prepare_ms: f64_to_u64_ms(response.prepare_ms.unwrap_or(0.0)),
        layout_ms: f64_to_u64_ms(response.layout_ms.unwrap_or(0.0)),
        visual_row_count: response.line_count.unwrap_or(1).max(1),
    })
}

fn invoke_pretext_runtime_worker(
    script_path: &std::path::Path,
    request_payload: &str,
) -> Result<RuntimeLayoutResponse, String> {
    let mut worker_slot = pretext_runtime_worker_store()
        .lock()
        .map_err(|_| "failed to lock pretext runtime worker".to_string())?;

    if worker_slot.is_none() {
        *worker_slot = Some(spawn_pretext_runtime_worker(script_path)?);
    }

    let response_line_result = {
        let worker = worker_slot
            .as_mut()
            .ok_or_else(|| "pretext runtime worker unavailable".to_string())?;

        worker
            .stdin
            .write_all(request_payload.as_bytes())
            .map_err(|error| format!("failed to write pretext runtime request: {error}"))
            .and_then(|_| {
                worker
                    .stdin
                    .write_all(b"\n")
                    .map_err(|error| format!("failed to finalize pretext runtime request: {error}"))
            })
            .and_then(|_| {
                worker
                    .stdin
                    .flush()
                    .map_err(|error| format!("failed to flush pretext runtime request: {error}"))
            })
            .and_then(|_| {
                let mut line = String::new();
                let byte_count = worker
                    .stdout
                    .read_line(&mut line)
                    .map_err(|error| format!("failed to read pretext runtime response: {error}"))?;

                if byte_count == 0 {
                    return Err("pretext runtime worker closed stdout".to_string());
                }

                Ok(line)
            })
    };

    let response_line = match response_line_result {
        Ok(line) => line,
        Err(error) => {
            discard_pretext_runtime_worker(&mut worker_slot);
            return Err(error);
        }
    };

    let response_text = response_line.trim();
    if response_text.is_empty() {
        discard_pretext_runtime_worker(&mut worker_slot);
        return Err("pretext runtime worker returned empty response".to_string());
    }

    serde_json::from_str::<RuntimeLayoutResponse>(response_text).map_err(|error| {
        discard_pretext_runtime_worker(&mut worker_slot);
        format!("failed to parse pretext runtime response: {error}")
    })
}

fn spawn_pretext_runtime_worker(script_path: &std::path::Path) -> Result<PretextRuntimeWorker, String> {
    let mut child = Command::new("node")
        .arg(script_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("failed to spawn pretext runtime process: {error}"))?;

    let stdin = child
        .stdin
        .take()
        .ok_or_else(|| "failed to capture pretext runtime stdin".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "failed to capture pretext runtime stdout".to_string())?;

    Ok(PretextRuntimeWorker {
        child,
        stdin,
        stdout: BufReader::new(stdout),
    })
}

fn discard_pretext_runtime_worker(slot: &mut Option<PretextRuntimeWorker>) {
    if let Some(mut worker) = slot.take() {
        let _ = worker.child.kill();
        let _ = worker.child.wait();
    }
}

fn f64_to_u64_ms(value: f64) -> u64 {
    if !value.is_finite() || value <= 0.0 {
        return 0;
    }

    value.round() as u64
}

fn truncate_reason(value: &str) -> String {
    const MAX_REASON_LENGTH: usize = 240;
    let trimmed = value.trim();
    if trimmed.len() <= MAX_REASON_LENGTH {
        return trimmed.to_string();
    }

    let mut output = String::new();
    for ch in trimmed.chars().take(MAX_REASON_LENGTH) {
        output.push(ch);
    }
    output.push_str("...");
    output
}

fn pretext_runtime_script_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(PRETEXT_RUNTIME_SCRIPT_PATH)
}

fn build_runtime_cache_key(payload: &str, options: &LayoutOptions) -> String {
    let mut hasher = DefaultHasher::new();
    payload.hash(&mut hasher);
    options.width_px.hash(&mut hasher);
    options.line_height_px.hash(&mut hasher);
    normalize_font_profile(options.font_profile.as_str()).hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn runtime_layout_cache_get(cache_key: &str) -> Option<RuntimeLayoutSnapshot> {
    runtime_layout_cache()
        .lock()
        .ok()
        .and_then(|cache| cache.get(cache_key).cloned())
}

fn runtime_layout_cache_insert(cache_key: String, snapshot: RuntimeLayoutSnapshot) {
    if let Ok(mut cache) = runtime_layout_cache().lock() {
        cache.insert(cache_key, snapshot);

        while cache.len() > MAX_RUNTIME_LAYOUT_CACHE_ENTRIES {
            if let Some(first_key) = cache.keys().next().cloned() {
                cache.remove(first_key.as_str());
            } else {
                break;
            }
        }
    }
}

fn runtime_layout_cache() -> &'static Mutex<HashMap<String, RuntimeLayoutSnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, RuntimeLayoutSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn pretext_runtime_worker_store() -> &'static Mutex<Option<PretextRuntimeWorker>> {
    static WORKER: OnceLock<Mutex<Option<PretextRuntimeWorker>>> = OnceLock::new();
    WORKER.get_or_init(|| Mutex::new(None))
}

fn runtime_unavailable_reason_get() -> Option<String> {
    runtime_unavailable_reason_store()
        .lock()
        .ok()
        .and_then(|value| value.clone())
}

fn runtime_unavailable_reason_set(reason: String) {
    if let Ok(mut value) = runtime_unavailable_reason_store().lock() {
        *value = Some(reason);
    }
}

fn runtime_unavailable_reason_store() -> &'static Mutex<Option<String>> {
    static STORE: OnceLock<Mutex<Option<String>>> = OnceLock::new();
    STORE.get_or_init(|| Mutex::new(None))
}

fn build_layout_cache_key(
    diff_id: &str,
    width_px: u32,
    font_profile: &str,
    line_height_px: u32,
) -> String {
    format!(
        "{diff_id}:{width_px}:{}:{line_height_px}",
        normalize_font_profile(font_profile)
    )
}

fn normalize_font_profile(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string()
}

fn resolve_font_profile(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return DEFAULT_FONT_PROFILE.to_string();
    }

    if trimmed.contains("px") {
        return trimmed.to_string();
    }

    if let Some(size) = trimmed
        .strip_prefix("ui-mono-")
        .and_then(|item| item.parse::<u32>().ok())
    {
        return format!("{size}px {}", default_monospace_family());
    }

    DEFAULT_FONT_PROFILE.to_string()
}

fn default_monospace_family() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        "Consolas"
    }
    #[cfg(target_os = "macos")]
    {
        "Menlo"
    }
    #[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
    {
        "DejaVu Sans Mono"
    }
}

fn estimate_visual_rows(lines: &[&str], width_px: u32) -> u32 {
    let max_columns = (width_px / AVERAGE_GLYPH_WIDTH_PX).max(16) as usize;
    let mut rows = 0_u32;

    for line in lines {
        let expanded = line.replace('\t', "    ");
        let char_count = expanded.chars().count();
        let wrapped_rows = if char_count == 0 {
            1
        } else {
            char_count.div_ceil(max_columns)
        };
        rows = rows.saturating_add(wrapped_rows as u32);
    }

    rows.max(1)
}

fn force_fallback_enabled() -> bool {
    matches!(
        std::env::var("GDPU_FORCE_DIFF_FALLBACK")
            .ok()
            .map(|value| value.trim().to_ascii_lowercase())
            .as_deref(),
        Some("1") | Some("true") | Some("yes")
    )
}

fn max_layout_bytes() -> usize {
    std::env::var("GDPU_PRETEXT_MAX_LAYOUT_BYTES")
        .ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
        .filter(|value| *value >= 1024)
        .unwrap_or(DEFAULT_MAX_LAYOUT_BYTES)
}
