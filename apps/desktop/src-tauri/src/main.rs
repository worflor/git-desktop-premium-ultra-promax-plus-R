mod commands;
mod errors;
mod models;
mod runtime;
mod services;

use runtime::state::AppState;
use services::{bootstrap_service, crash_reporting_service};

fn main() {
    crash_reporting_service::install_panic_hook();
    std::thread::spawn(bootstrap_service::run_startup_readiness_probe);

    tauri::Builder::default()
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            commands::open_repository,
            commands::list_recent_repositories,
            commands::get_git_capabilities,
            commands::get_auth_status,
            commands::get_repository_auth_status,
            commands::list_forge_adapters,
            commands::get_repository_integration_matrix,
            commands::get_repository_status,
            commands::list_branches,
            commands::create_branch,
            commands::checkout_branch,
            commands::delete_branch,
            commands::rename_branch,
            commands::set_branch_upstream,
            commands::list_stashes,
            commands::create_stash,
            commands::pop_stash,
            commands::drop_stash,
            commands::list_worktrees,
            commands::create_worktree,
            commands::remove_worktree,
            commands::list_commit_history,
            commands::get_commit_detail,
            commands::stage_paths,
            commands::unstage_paths,
            commands::create_commit,
            commands::get_file_diff,
            commands::prepare_file_diff_chunks,
            commands::get_file_diff_chunk,
            commands::fetch_remote,
            commands::pull_remote,
            commands::push_remote,
            commands::start_rebase,
            commands::continue_rebase,
            commands::abort_rebase,
            commands::start_cherry_pick,
            commands::continue_cherry_pick,
            commands::abort_cherry_pick,
            commands::get_conflict_state,
            commands::continue_conflict_resolution,
            commands::abort_conflict_resolution,
            commands::list_issue_providers,
            commands::list_local_issues,
            commands::list_pull_request_providers,
            commands::list_pull_requests,
            commands::create_pull_request,
            commands::close_pull_request,
            commands::reopen_pull_request,
            commands::mark_pull_request_ready,
            commands::merge_pull_request,
            commands::create_local_issue,
            commands::close_local_issue,
            commands::reopen_local_issue,
            commands::list_ai_providers,
            commands::get_ai_audit_entries,
            commands::run_ai_diff_review,
            commands::start_ai_diff_review_job,
            commands::get_ai_diff_review_job,
            commands::cancel_ai_diff_review_job,
            commands::get_startup_readiness_snapshot,
            commands::get_app_settings,
            commands::update_ai_guardrail,
            commands::update_telemetry_retention,
            commands::update_update_channel,
            commands::update_crash_reporting,
            commands::update_layout_preferences,
            commands::update_ui_preferences,
            commands::get_command_telemetry_snapshot,
            commands::clear_command_telemetry
        ])
        .run(tauri::generate_context!())
        .expect("failed to run tauri application");
}
