mod commands;
mod errors;
mod models;
mod runtime;
mod services;

use runtime::state::AppState;
use services::crash_reporting_service;

fn main() {
    crash_reporting_service::install_panic_hook();

    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            commands::open_repository,
            commands::pick_repository_directory,
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
            commands::get_rebase_plan,
            commands::start_interactive_rebase,
            commands::search_commits_by_message,
            commands::search_commits_by_code,
            commands::search_commits_by_file,
            commands::list_reflog,
            commands::get_file_blame,
            commands::clone_repository,
            commands::init_repository,
            commands::list_tags,
            commands::create_tag,
            commands::delete_tag,
            commands::list_worktrees,
            commands::create_worktree,
            commands::remove_worktree,
            commands::list_commit_history,
            commands::get_commit_detail,
            commands::prime_commit_details,
            commands::stage_paths,
            commands::unstage_paths,
            commands::create_commit,
            commands::get_file_diff,
            commands::prepare_file_diff_chunks,
            commands::get_file_diff_chunk,
            commands::fetch_remote,
            commands::pull_remote,
            commands::push_remote,
            commands::sync_remote,
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
            commands::list_ai_model_options,
            commands::get_ai_audit_entries,
            commands::clear_ai_audit_entries,
            commands::run_ai_diff_review,
            commands::start_ai_diff_review_job,
            commands::get_ai_diff_review_job,
            commands::cancel_ai_diff_review_job,
            commands::get_startup_readiness_snapshot,
            commands::get_app_settings,
            commands::update_ai_guardrail,
            commands::update_telemetry_retention,
            commands::update_update_channel,
            commands::check_for_app_update,
            commands::install_app_update,
            commands::update_crash_reporting,
            commands::update_layout_preferences,
            commands::update_ui_preferences,
            commands::get_command_telemetry_snapshot,
            commands::clear_command_telemetry
        ])
        .run(tauri::generate_context!())
        .expect("failed to run tauri application");
}
