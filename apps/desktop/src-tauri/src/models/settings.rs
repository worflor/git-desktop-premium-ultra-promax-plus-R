use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AppSettingsData {
    pub guardrail_value: f32,
    pub guardrail_profile: String,
    pub ai_read_only_default: bool,
    pub telemetry_retention_days: u32,
    pub telemetry_retention_mb: u32,
    pub theme_id: String,
    pub keybinding_profile: String,
    pub sidebar_width_px: u32,
    pub sidebar_position: String,
    pub utility_drawer_default_expanded: bool,
    pub utility_drawer_height_px: u32,
}
