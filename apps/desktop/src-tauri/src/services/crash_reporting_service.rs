use std::any::Any;
use std::fs;
use std::panic::PanicHookInfo;
use std::path::PathBuf;

use chrono::{SecondsFormat, Utc};

use crate::services::{settings_service, storage_paths};

pub fn install_panic_hook() {
    let default_hook = std::panic::take_hook();

    std::panic::set_hook(Box::new(move |panic_info| {
        if should_persist_crash_report() {
            let _ = persist_crash_report(panic_info);
        }

        default_hook(panic_info);
    }));
}

fn should_persist_crash_report() -> bool {
    settings_service::get_settings()
        .map(|settings| settings.crash_reporting_enabled)
        .unwrap_or(false)
}

fn persist_crash_report(panic_info: &PanicHookInfo<'_>) -> std::io::Result<()> {
    let reports_dir = crash_report_directory()?;
    fs::create_dir_all(&reports_dir)?;

    let timestamp = Utc::now();
    let file_name = format!("panic-{}.log", timestamp.format("%Y%m%dT%H%M%S%.3fZ"));
    let file_path = reports_dir.join(file_name);

    let thread = std::thread::current();
    let thread_name = thread.name().unwrap_or("unknown");
    let payload = panic_payload_to_string(panic_info.payload());
    let location = panic_info
        .location()
        .map(|value| format!("{}:{}:{}", value.file(), value.line(), value.column()))
        .unwrap_or_else(|| "unknown".to_string());

    let report = format!(
        "timestamp={}\nthread={}\nlocation={}\npayload={}\nbacktrace=\n{}\n",
        timestamp.to_rfc3339_opts(SecondsFormat::Secs, true),
        thread_name,
        location,
        payload,
        std::backtrace::Backtrace::force_capture(),
    );

    fs::write(file_path, report)
}

fn crash_report_directory() -> std::io::Result<PathBuf> {
    storage_paths::gdpu_data_dir()
        .map(|path| path.join("crash-reports"))
        .map_err(|error| std::io::Error::other(error.to_string()))
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_string();
    }

    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }

    "<non-string panic payload>".to_string()
}

#[cfg(test)]
mod tests {
    use super::panic_payload_to_string;

    #[test]
    fn panic_payload_to_string_supports_common_payloads() {
        let owned = "owned panic".to_string();
        assert_eq!(panic_payload_to_string(&owned), "owned panic");

        let borrowed: &str = "borrowed panic";
        assert_eq!(panic_payload_to_string(&borrowed), "borrowed panic");
    }
}
