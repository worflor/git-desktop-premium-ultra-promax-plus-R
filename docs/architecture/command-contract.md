# Command Contract

## Purpose
Define a stable, versioned contract between Solid UI and Tauri Rust commands.

## Envelope Types
All commands should return one of:

```ts
export type CommandResult<T> =
  | { ok: true; data: T; meta?: ResponseMeta }
  | { ok: false; error: CommandError; meta?: ResponseMeta };

export interface ResponseMeta {
  requestId: string;
  durationMs: number;
  version: string;
}

export interface CommandError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
  retryable?: boolean;
}
```

## Error Code Convention
Format:
- domain.reason

Examples:
- repo.not_found
- repo.open_failed
- git.not_installed
- git.auth_required
- git.conflict_detected
- auth.helper_unavailable
- forge.adapter_unavailable
- diff.too_large
- ai.provider_unavailable
- ai.process_failed

## Versioning Rule
- Include contract version in response meta.
- Breaking response shape changes require version bump.
- UI should fail soft for unknown fields and known error envelope.

## Initial Commands (V0)
1. open_repository
2. list_recent_repositories
3. get_git_capabilities
4. get_auth_status
5. get_repository_auth_status
6. list_forge_adapters
7. get_repository_integration_matrix
8. get_repository_status
9. stage_paths
10. unstage_paths
11. create_commit
12. get_file_diff
13. fetch_remote
14. pull_remote
15. push_remote
16. list_ai_providers
17. run_ai_diff_review
18. start_ai_diff_review_job
19. get_ai_diff_review_job
20. cancel_ai_diff_review_job
21. get_conflict_state
22. continue_conflict_resolution
23. abort_conflict_resolution
24. get_app_settings
25. update_ai_guardrail
26. update_telemetry_retention
27. update_layout_preferences
28. update_ui_preferences

Settings payload note:
- update_layout_preferences uses `{ sidebarWidthPx, sidebarPosition, utilityDrawerDefaultExpanded, utilityDrawerHeightPx }`.
- sidebarPosition accepts `left` or `right`.
- update_ui_preferences uses `{ themeId, keybindingProfile }`.
- themeId accepts `aether`, `helix`, `quanta`, `petrichor`, `redshift`, or `halo`; keybindingProfile accepts `classic` or `compact`.

## DTO Guidelines
- Use explicit, named fields; avoid tuple-like arrays.
- Keep dates in ISO-8601 string format.
- Keep path fields normalized to absolute internal form in backend, convert to display-safe paths in UI.
- Do not include secrets in DTOs.

## Long-Running Commands
For long-running operations (for example AI review jobs):
- start command returns immediate ack with requestId and jobId
- UI polls a get_*_job command by jobId until done=true
- output is incremental and append-only in job.output
- cancellation is command-based via cancel_*_job(jobId)

Standard job status values:
- queued
- running
- completed
- failed
- canceled

Note:
- Tauri event-channel streaming is not part of V0 command behavior.

## Observability Requirements
Every command must:
- Generate requestId
- Log start/end with duration and status
- Attach domain-specific counters for performance dashboards
