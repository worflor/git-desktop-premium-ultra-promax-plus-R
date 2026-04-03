use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::errors::AppError;
use crate::models::settings::AppSettingsData;

const SETTINGS_FILE_NAME: &str = "settings.json";
const SIDEBAR_WIDTH_MIN_PX: u32 = 220;
const SIDEBAR_WIDTH_MAX_PX: u32 = 520;
const UTILITY_DRAWER_HEIGHT_MIN_PX: u32 = 120;
const UTILITY_DRAWER_HEIGHT_MAX_PX: u32 = 420;
const SUPPORTED_THEME_IDS: [&str; 6] =
    ["aether", "helix", "quanta", "petrichor", "redshift", "halo"];
const DEFAULT_THEME_ID: &str = "aether";
const DEFAULT_KEYBINDING_PROFILE: &str = "classic";

#[derive(Debug, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct StoredSettings {
    guardrail_value: f32,
    ai_read_only_default: bool,
    telemetry_retention_days: u32,
    telemetry_retention_mb: u32,
    theme_id: String,
    keybinding_profile: String,
    sidebar_width_px: u32,
    sidebar_position: String,
    utility_drawer_default_expanded: bool,
    utility_drawer_height_px: u32,
}

impl Default for StoredSettings {
    fn default() -> Self {
        Self {
            guardrail_value: 0.5,
            ai_read_only_default: true,
            telemetry_retention_days: 30,
            telemetry_retention_mb: 128,
            theme_id: DEFAULT_THEME_ID.to_string(),
            keybinding_profile: DEFAULT_KEYBINDING_PROFILE.to_string(),
            sidebar_width_px: 280,
            sidebar_position: "left".to_string(),
            utility_drawer_default_expanded: false,
            utility_drawer_height_px: 180,
        }
    }
}

pub fn get_settings() -> Result<AppSettingsData, AppError> {
    let stored = load_settings()?;
    Ok(to_data(&stored))
}

pub fn update_guardrail(value: f32) -> Result<AppSettingsData, AppError> {
    if !value.is_finite() {
        return Err(AppError::InvalidInput(
            "guardrail value must be a finite number".to_string(),
        ));
    }

    let mut stored = load_settings()?;
    stored.guardrail_value = value.clamp(0.0, 1.0);
    persist_settings(&stored)?;
    Ok(to_data(&stored))
}

pub fn update_telemetry_retention(days: u32, max_mb: u32) -> Result<AppSettingsData, AppError> {
    let days = days.clamp(1, 365);
    let max_mb = max_mb.clamp(16, 4096);

    let mut stored = load_settings()?;
    stored.telemetry_retention_days = days;
    stored.telemetry_retention_mb = max_mb;
    persist_settings(&stored)?;
    Ok(to_data(&stored))
}

pub fn update_layout_preferences(
    sidebar_width_px: u32,
    sidebar_position: &str,
    utility_drawer_default_expanded: bool,
    utility_drawer_height_px: u32,
) -> Result<AppSettingsData, AppError> {
    let normalized_sidebar_position = parse_sidebar_position(sidebar_position)?;

    let mut stored = load_settings()?;
    stored.sidebar_width_px = clamp_sidebar_width_px(sidebar_width_px);
    stored.sidebar_position = normalized_sidebar_position.to_string();
    stored.utility_drawer_default_expanded = utility_drawer_default_expanded;
    stored.utility_drawer_height_px = clamp_utility_drawer_height_px(utility_drawer_height_px);

    persist_settings(&stored)?;
    Ok(to_data(&stored))
}

pub fn update_ui_preferences(
    theme_id: &str,
    keybinding_profile: &str,
) -> Result<AppSettingsData, AppError> {
    let normalized_theme_id = normalize_theme_id(theme_id);
    let normalized_keybinding_profile = normalize_keybinding_profile(keybinding_profile);

    let mut stored = load_settings()?;
    stored.theme_id = normalized_theme_id.to_string();
    stored.keybinding_profile = normalized_keybinding_profile.to_string();

    persist_settings(&stored)?;
    Ok(to_data(&stored))
}

fn to_data(stored: &StoredSettings) -> AppSettingsData {
    AppSettingsData {
        guardrail_value: stored.guardrail_value,
        guardrail_profile: guardrail_profile(stored.guardrail_value).to_string(),
        ai_read_only_default: stored.ai_read_only_default,
        telemetry_retention_days: stored.telemetry_retention_days,
        telemetry_retention_mb: stored.telemetry_retention_mb,
        theme_id: normalize_theme_id(&stored.theme_id).to_string(),
        keybinding_profile: normalize_keybinding_profile(&stored.keybinding_profile).to_string(),
        sidebar_width_px: clamp_sidebar_width_px(stored.sidebar_width_px),
        sidebar_position: normalize_sidebar_position(&stored.sidebar_position).to_string(),
        utility_drawer_default_expanded: stored.utility_drawer_default_expanded,
        utility_drawer_height_px: clamp_utility_drawer_height_px(stored.utility_drawer_height_px),
    }
}

fn guardrail_profile(value: f32) -> &'static str {
    if value < 0.25 {
        return "Loose";
    }
    if value <= 0.5 {
        return "Balanced";
    }
    if value < 0.75 {
        return "Strict";
    }
    "Paranoid"
}

fn clamp_sidebar_width_px(value: u32) -> u32 {
    value.clamp(SIDEBAR_WIDTH_MIN_PX, SIDEBAR_WIDTH_MAX_PX)
}

fn clamp_utility_drawer_height_px(value: u32) -> u32 {
    value.clamp(UTILITY_DRAWER_HEIGHT_MIN_PX, UTILITY_DRAWER_HEIGHT_MAX_PX)
}

fn normalize_sidebar_position(value: &str) -> &'static str {
    if value.trim().eq_ignore_ascii_case("right") {
        return "right";
    }

    "left"
}

fn parse_sidebar_position(value: &str) -> Result<&'static str, AppError> {
    let normalized = value.trim();
    if normalized.eq_ignore_ascii_case("left") {
        return Ok("left");
    }
    if normalized.eq_ignore_ascii_case("right") {
        return Ok("right");
    }

    Err(AppError::InvalidInput(
        "sidebar position must be 'left' or 'right'".to_string(),
    ))
}

fn normalize_theme_id(value: &str) -> &'static str {
    match find_supported_theme_id(value) {
        Some(theme_id) => theme_id,
        None => DEFAULT_THEME_ID,
    }
}

fn find_supported_theme_id(value: &str) -> Option<&'static str> {
    let normalized = value.trim();
    for theme_id in SUPPORTED_THEME_IDS {
        if normalized.eq_ignore_ascii_case(theme_id) {
            return Some(theme_id);
        }
    }

    None
}

fn normalize_keybinding_profile(value: &str) -> &'static str {
    let normalized = value.trim();
    if normalized.eq_ignore_ascii_case("compact") {
        return "compact";
    }

    DEFAULT_KEYBINDING_PROFILE
}

fn load_settings() -> Result<StoredSettings, AppError> {
    let path = settings_file_path()?;
    if !path.exists() {
        return Ok(StoredSettings::default());
    }

    let payload = fs::read_to_string(path)
        .map_err(|error| AppError::Internal(format!("failed to read settings file: {error}")))?;

    serde_json::from_str::<StoredSettings>(&payload)
        .map_err(|error| AppError::Internal(format!("failed to parse settings file: {error}")))
}

fn persist_settings(settings: &StoredSettings) -> Result<(), AppError> {
    let path = settings_file_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| AppError::Internal("settings storage path is invalid".to_string()))?;

    fs::create_dir_all(parent).map_err(|error| {
        AppError::Internal(format!("failed to create settings directory: {error}"))
    })?;

    let payload = serde_json::to_string_pretty(settings)
        .map_err(|error| AppError::Internal(format!("failed to serialize settings: {error}")))?;

    fs::write(path, payload)
        .map_err(|error| AppError::Internal(format!("failed to write settings file: {error}")))
}

fn settings_file_path() -> Result<PathBuf, AppError> {
    let appdata = std::env::var("APPDATA").map_err(|_| {
        AppError::Internal("APPDATA environment variable is unavailable".to_string())
    })?;
    Ok(PathBuf::from(appdata).join("gdpu").join(SETTINGS_FILE_NAME))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;
    use std::sync::{Mutex, OnceLock};

    use uuid::Uuid;

    fn appdata_mutex() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    struct AppDataTestScope {
        _lock: std::sync::MutexGuard<'static, ()>,
        previous: Option<OsString>,
        temp_root: PathBuf,
    }

    impl AppDataTestScope {
        fn enter() -> Self {
            let lock = appdata_mutex()
                .lock()
                .expect("APPDATA test lock should not be poisoned");

            let temp_root = std::env::temp_dir().join(format!("gdpu-settings-{}", Uuid::new_v4()));
            fs::create_dir_all(&temp_root).expect("temporary APPDATA directory should be created");

            let previous = std::env::var_os("APPDATA");
            std::env::set_var("APPDATA", &temp_root);

            Self {
                _lock: lock,
                previous,
                temp_root,
            }
        }
    }

    impl Drop for AppDataTestScope {
        fn drop(&mut self) {
            if let Some(previous) = &self.previous {
                std::env::set_var("APPDATA", previous);
            } else {
                std::env::remove_var("APPDATA");
            }

            let _ = fs::remove_dir_all(&self.temp_root);
        }
    }

    #[test]
    fn update_ui_preferences_persists_theme_and_profile() {
        let _scope = AppDataTestScope::enter();

        let updated = update_ui_preferences("helix", "compact")
            .expect("updating UI preferences should succeed");
        assert_eq!(updated.theme_id, "helix");
        assert_eq!(updated.keybinding_profile, "compact");

        let loaded = get_settings().expect("loading settings should succeed");
        assert_eq!(loaded.theme_id, "helix");
        assert_eq!(loaded.keybinding_profile, "compact");
    }

    #[test]
    fn get_settings_normalizes_unknown_ui_preferences() {
        let _scope = AppDataTestScope::enter();

        let payload = r#"{
  "themeId": "unknown-theme",
  "keybindingProfile": "unknown-profile"
}"#;

        let path = settings_file_path().expect("settings path should resolve");
        let parent = path
            .parent()
            .expect("settings path should include a parent directory");
        fs::create_dir_all(parent).expect("settings directory should be created");
        fs::write(path, payload).expect("settings fixture should be written");

        let loaded = get_settings().expect("loading settings should succeed");
        assert_eq!(loaded.theme_id, DEFAULT_THEME_ID);
        assert_eq!(loaded.keybinding_profile, DEFAULT_KEYBINDING_PROFILE);
    }

    #[test]
    fn update_ui_preferences_normalizes_unknown_theme() {
        let _scope = AppDataTestScope::enter();

        let updated = update_ui_preferences("unknown-theme", "classic")
            .expect("unknown theme should normalize to default");
        assert_eq!(updated.theme_id, DEFAULT_THEME_ID);
        assert_eq!(updated.keybinding_profile, "classic");
    }

    #[test]
    fn update_ui_preferences_normalizes_unknown_keybinding_profile() {
        let _scope = AppDataTestScope::enter();

        let updated = update_ui_preferences("aether", "vim")
            .expect("unknown keybinding profile should normalize to default");
        assert_eq!(updated.theme_id, "aether");
        assert_eq!(updated.keybinding_profile, DEFAULT_KEYBINDING_PROFILE);
    }

    #[test]
    fn default_guardrail_profile_is_balanced() {
        let _scope = AppDataTestScope::enter();

        let loaded = get_settings().expect("loading default settings should succeed");
        assert_eq!(loaded.guardrail_profile, "Balanced");
    }
}
