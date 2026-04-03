mod commands;
mod errors;
mod models;
mod runtime;
mod services;

use runtime::state::AppState;

fn main() {
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
            commands::list_worktrees,
            commands::create_worktree,
            commands::remove_worktree,
            commands::list_commit_history,
            commands::get_commit_detail,
            commands::stage_paths,
            commands::unstage_paths,
            commands::create_commit,
            commands::get_file_diff,
            commands::fetch_remote,
            commands::pull_remote,
            commands::push_remote,
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
            commands::run_ai_diff_review,
            commands::start_ai_diff_review_job,
            commands::get_ai_diff_review_job,
            commands::cancel_ai_diff_review_job,
            commands::get_app_settings,
            commands::update_ai_guardrail,
            commands::update_telemetry_retention,
            commands::update_layout_preferences,
            commands::update_ui_preferences
        ])
        .run(tauri::generate_context!())
        .expect("failed to run tauri application");
}
