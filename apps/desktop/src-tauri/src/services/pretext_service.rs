use std::time::Instant;

const PRETEXT_LAYOUT_VERSION: &str = "pretext-adapter-v1";
const DEFAULT_LAYOUT_WIDTH_PX: u32 = 1080;
const DEFAULT_LINE_HEIGHT_PX: u32 = 18;
const DEFAULT_FONT_PROFILE: &str = "ui-mono-13";
const MIN_LAYOUT_WIDTH_PX: u32 = 320;
const MAX_LAYOUT_WIDTH_PX: u32 = 4096;
const MIN_LINE_HEIGHT_PX: u32 = 12;
const MAX_LINE_HEIGHT_PX: u32 = 64;
const DEFAULT_MAX_LAYOUT_BYTES: usize = 24 * 1024 * 1024;
const AVERAGE_GLYPH_WIDTH_PX: u32 = 8;

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
            .unwrap_or(DEFAULT_FONT_PROFILE)
            .to_string();

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

pub fn prepare_layout(diff_id: &str, payload: &str, options: &LayoutOptions) -> LayoutSnapshot {
    let prepare_started_at = Instant::now();
    let max_layout_bytes = max_layout_bytes();
    let mut fallback_reason = None::<String>;

    if payload.len() > max_layout_bytes {
        fallback_reason = Some(format!(
            "payload exceeds pretext layout budget: {} > {}",
            payload.len(),
            max_layout_bytes
        ));
    }

    if payload.contains('\0') {
        fallback_reason = Some("payload contains binary null bytes".to_string());
    }

    if force_fallback_enabled() {
        fallback_reason = Some("forced by GDPU_FORCE_DIFF_FALLBACK=1".to_string());
    }

    let lines = payload.lines().collect::<Vec<_>>();
    let prepare_ms = prepare_started_at.elapsed().as_millis() as u64;

    let layout_started_at = Instant::now();
    let visual_row_count = if fallback_reason.is_some() {
        // Fallback uses 1:1 row mapping to preserve deterministic line navigation.
        lines.len().max(1) as u32
    } else {
        estimate_visual_rows(&lines, options.width_px)
    };
    let layout_ms = layout_started_at.elapsed().as_millis() as u64;

    LayoutSnapshot {
        pretext_version: PRETEXT_LAYOUT_VERSION.to_string(),
        prepare_ms,
        layout_ms,
        fallback_activated: fallback_reason.is_some(),
        fallback_reason,
        visual_row_count,
        layout_cache_key: build_layout_cache_key(
            diff_id,
            options.width_px,
            options.font_profile.as_str(),
            options.line_height_px,
        ),
    }
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
