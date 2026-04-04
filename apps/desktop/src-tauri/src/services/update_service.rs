use std::time::Duration;

use chrono::Utc;
use reqwest::Url;
use tauri::AppHandle;
use tauri_plugin_updater::UpdaterExt;

use crate::errors::AppError;
use crate::models::operations::{AppUpdateCheckData, AppUpdateInstallData};
use crate::services::settings_service;

const CHANNEL_STABLE: &str = "stable";
const CHANNEL_BETA: &str = "beta";
const UPDATE_REQUEST_TIMEOUT: Duration = Duration::from_secs(45);

struct UpdateRuntimeConfig {
    channel: String,
    endpoint: Option<String>,
    endpoints: Vec<Url>,
    pubkey: Option<String>,
}

pub async fn check_for_updates(app: &AppHandle) -> Result<AppUpdateCheckData, AppError> {
    let runtime = resolve_runtime_config()?;
    let checked_at = Utc::now().to_rfc3339();
    let current_version = app.package_info().version.to_string();

    let updater = build_updater(app, &runtime)?;
    let update = updater.check().await.map_err(map_updater_error)?;

    if let Some(update) = update {
        return Ok(AppUpdateCheckData {
            channel: runtime.channel,
            endpoint: runtime.endpoint,
            checked_at,
            update_available: true,
            current_version: update.current_version,
            latest_version: Some(update.version),
            notes: update.body,
            published_at: update.date.map(|value| value.to_string()),
            target: Some(update.target),
            download_url: Some(update.download_url.to_string()),
        });
    }

    Ok(AppUpdateCheckData {
        channel: runtime.channel,
        endpoint: runtime.endpoint,
        checked_at,
        update_available: false,
        current_version,
        latest_version: None,
        notes: None,
        published_at: None,
        target: None,
        download_url: None,
    })
}

pub async fn install_update(app: &AppHandle) -> Result<AppUpdateInstallData, AppError> {
    let runtime = resolve_runtime_config()?;
    let checked_at = Utc::now().to_rfc3339();
    let current_version = app.package_info().version.to_string();

    let updater = build_updater(app, &runtime)?;
    let update = updater.check().await.map_err(map_updater_error)?;

    let Some(update) = update else {
        return Ok(AppUpdateInstallData {
            channel: runtime.channel,
            endpoint: runtime.endpoint,
            checked_at,
            attempted: false,
            installed: false,
            current_version,
            target_version: None,
            message: "No update available for the selected channel.".to_string(),
        });
    };

    let target_version = update.version.clone();
    update
        .download_and_install(|_, _| {}, || {})
        .await
        .map_err(map_updater_error)?;

    Ok(AppUpdateInstallData {
        channel: runtime.channel,
        endpoint: runtime.endpoint,
        checked_at,
        attempted: true,
        installed: true,
        current_version: update.current_version,
        target_version: Some(target_version.clone()),
        message: format!(
            "Installed update {target_version}. Restart the app to finish activation."
        ),
    })
}

fn resolve_runtime_config() -> Result<UpdateRuntimeConfig, AppError> {
    let settings = settings_service::get_settings()?;
    let channel = normalize_channel(&settings.update_channel).to_string();
    let endpoints = resolve_endpoint_env(&channel)?;

    Ok(UpdateRuntimeConfig {
        channel,
        endpoint: endpoints.first().map(|value| value.to_string()),
        endpoints,
        pubkey: read_non_empty_env_var("GDPU_UPDATER_PUBKEY"),
    })
}

fn build_updater(
    app: &AppHandle,
    runtime: &UpdateRuntimeConfig,
) -> Result<tauri_plugin_updater::Updater, AppError> {
    let mut builder = app.updater_builder().timeout(UPDATE_REQUEST_TIMEOUT);

    if !runtime.endpoints.is_empty() {
        builder = builder
            .endpoints(runtime.endpoints.clone())
            .map_err(map_updater_error)?;
    }

    if let Some(pubkey) = &runtime.pubkey {
        builder = builder.pubkey(pubkey.clone());
    }

    builder.build().map_err(map_updater_error)
}

fn normalize_channel(value: &str) -> &'static str {
    if value.trim().eq_ignore_ascii_case(CHANNEL_BETA) {
        return CHANNEL_BETA;
    }

    CHANNEL_STABLE
}

fn resolve_endpoint_env(channel: &str) -> Result<Vec<Url>, AppError> {
    let env_names: &[&str] = if channel == CHANNEL_BETA {
        &[
            "GDPU_UPDATER_ENDPOINTS_BETA",
            "GDPU_UPDATER_ENDPOINT_BETA",
            "GDPU_UPDATER_ENDPOINTS",
            "GDPU_UPDATER_ENDPOINT",
        ]
    } else {
        &[
            "GDPU_UPDATER_ENDPOINTS_STABLE",
            "GDPU_UPDATER_ENDPOINT_STABLE",
            "GDPU_UPDATER_ENDPOINTS",
            "GDPU_UPDATER_ENDPOINT",
        ]
    };

    for env_name in env_names {
        if let Ok(raw_value) = std::env::var(env_name) {
            let endpoints = parse_endpoint_list(*env_name, &raw_value)?;
            if !endpoints.is_empty() {
                return Ok(endpoints);
            }
        }
    }

    Ok(Vec::new())
}

fn parse_endpoint_list(env_name: &str, raw_value: &str) -> Result<Vec<Url>, AppError> {
    let mut endpoints = Vec::new();
    for token in raw_value
        .split(|value| value == ',' || value == ';' || value == '\n')
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let parsed = Url::parse(token).map_err(|error| {
            AppError::InvalidInput(format!(
                "invalid updater endpoint in {env_name}: {error}"
            ))
        })?;

        if parsed.scheme() != "https" && !cfg!(debug_assertions) {
            return Err(AppError::InvalidInput(format!(
                "updater endpoint in {env_name} must use https in release builds"
            )));
        }

        endpoints.push(parsed);
    }

    Ok(endpoints)
}

fn read_non_empty_env_var(name: &str) -> Option<String> {
    let value = std::env::var(name).ok()?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }

    Some(trimmed.to_string())
}

fn map_updater_error<E>(error: E) -> AppError
where
    E: std::fmt::Display,
{
    let message = error.to_string();
    let normalized = message.to_ascii_lowercase();

    if normalized.contains("pubkey") || normalized.contains("endpoint") {
        return AppError::InvalidInput(format!("updater configuration error: {message}"));
    }

    AppError::CommandExecution(format!("updater request failed: {message}"))
}

#[cfg(test)]
mod tests {
    use super::{normalize_channel, parse_endpoint_list, CHANNEL_BETA, CHANNEL_STABLE};

    #[test]
    fn normalize_channel_maps_unknown_values_to_stable() {
        assert_eq!(normalize_channel("stable"), CHANNEL_STABLE);
        assert_eq!(normalize_channel("beta"), CHANNEL_BETA);
        assert_eq!(normalize_channel("nightly"), CHANNEL_STABLE);
    }

    #[test]
    fn parse_endpoint_list_accepts_multiple_delimiters() {
        let parsed = parse_endpoint_list(
            "GDPU_UPDATER_ENDPOINTS",
            "https://a.example, https://b.example;https://c.example\nhttps://d.example",
        )
        .expect("endpoint list should parse");

        assert_eq!(parsed.len(), 4);
        assert_eq!(parsed[0].as_str(), "https://a.example/");
        assert_eq!(parsed[3].as_str(), "https://d.example/");
    }

    #[test]
    fn parse_endpoint_list_rejects_invalid_urls() {
        let error = parse_endpoint_list("GDPU_UPDATER_ENDPOINTS", "not-a-url")
            .expect_err("invalid URL should fail");

        assert!(error.to_string().contains("invalid updater endpoint"));
    }
}
