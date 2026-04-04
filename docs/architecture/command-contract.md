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

## Current Commands (V0)
1. open_repository
2. list_recent_repositories
3. get_git_capabilities
4. get_auth_status
5. get_repository_auth_status
6. list_forge_adapters
7. get_repository_integration_matrix
8. get_repository_status
9. list_branches
10. create_branch
11. checkout_branch
12. delete_branch
13. rename_branch
14. set_branch_upstream
15. list_stashes
16. create_stash
17. pop_stash
18. drop_stash
19. list_worktrees
20. create_worktree
21. remove_worktree
22. list_commit_history
23. get_commit_detail
24. stage_paths
25. unstage_paths
26. create_commit
27. get_file_diff
28. prepare_file_diff_chunks
29. get_file_diff_chunk
30. fetch_remote
31. pull_remote
32. push_remote
33. start_rebase
34. continue_rebase
35. abort_rebase
36. start_cherry_pick
37. continue_cherry_pick
38. abort_cherry_pick
39. get_conflict_state
40. continue_conflict_resolution
41. abort_conflict_resolution
42. list_issue_providers
43. list_local_issues
44. list_pull_request_providers
45. list_pull_requests
46. create_pull_request
47. close_pull_request
48. reopen_pull_request
49. mark_pull_request_ready
50. merge_pull_request
51. create_local_issue
52. close_local_issue
53. reopen_local_issue
54. list_ai_providers
55. get_ai_audit_entries
56. run_ai_diff_review
57. start_ai_diff_review_job
58. get_ai_diff_review_job
59. cancel_ai_diff_review_job
60. get_startup_readiness_snapshot
61. get_app_settings
62. update_ai_guardrail
63. update_telemetry_retention
64. update_update_channel
65. update_crash_reporting
66. update_layout_preferences
67. update_ui_preferences
68. get_command_telemetry_snapshot
69. clear_command_telemetry

Settings payload note:
- update_update_channel uses `{ updateChannel }`; accepted values are `stable` and `beta`.
- update_crash_reporting uses `{ crashReportingEnabled }` and toggles local crash-report artifact persistence.
- update_layout_preferences uses `{ sidebarWidthPx, sidebarPosition, utilityDrawerDefaultExpanded, utilityDrawerHeightPx }`.
- sidebarPosition accepts `left` or `right`.
- update_ui_preferences uses `{ themeId, keybindingProfile }`.
- themeId accepts `aether`, `helix`, `quanta`, `petrichor`, `redshift`, `halo`, `nightwalker`, `blackboard`, or `crafty`; keybindingProfile accepts `classic` or `compact`.

Telemetry payload note:
- get_command_telemetry_snapshot accepts optional `{ recentLimit }` and returns aggregated p50/p95 summaries plus recent samples.
- clear_command_telemetry deletes persisted telemetry samples and returns operation metadata.
- Backend telemetry samples are local-only and retention-bound by app telemetry settings.

Capability payload note:
- get_git_capabilities now includes `gitExecutablePath` when the binary path can be resolved from host environment lookup (`where`/`which`).

Forge payload note:
- list_forge_adapters now includes contract-level GitLab and Bitbucket adapter entries (`gitlab-contract`, `bitbucket-contract`) in degraded mode alongside optional GitHub auth diagnostics.
- get_repository_integration_matrix classifies GitHub/GitLab/Bitbucket remotes and emits host-specific local-mirror capability flags.

Bootstrap payload note:
- get_startup_readiness_snapshot accepts optional `{ refresh }` and returns the latest probe snapshot with per-check status, timings, and degraded-count metadata.
- If no cached probe exists, backend runs a probe on demand before returning snapshot data.

Diff payload note:
- prepare_file_diff_chunks accepts `{ repositoryPath, path, staged?, contextLines?, chunkSizeBytes?, layoutWidthPx?, fontProfile?, lineHeightPx? }` and returns diff manifest metadata including hunk summaries.
- get_file_diff_chunk accepts `{ diffId, chunkIndex }` and returns chunk text plus pagination metadata.
- Diff chunk payloads are cached ephemerally in backend memory and can expire.
- Diff manifest payload now includes renderer mode selection metadata, mode thresholds, and Pretext layout telemetry fields (`pretextVersion`, `pretextPrepareMs`, `pretextLayoutMs`, `fallbackActivated`, `fallbackReason`, `visualRowCount`, `layoutCacheKey`).

Branch/Stash payload note:
- set_branch_upstream returns explicit tracking metadata `{ repositoryPath, branchName, upstream, operation }`.
- stash commands return structured stash operation/list DTOs rather than raw command output.

Advanced git workflow payload note:
- start_rebase accepts `{ repositoryPath, ontoRef }` and returns conflict-resolution operation payload with `operation=rebase` and `action=start`.
- start_cherry_pick accepts `{ repositoryPath, commitRef, mainline? }` and returns conflict-resolution operation payload with `operation=cherry-pick` and `action=start`.
- continue/abort variants for rebase and cherry-pick are exposed as explicit commands in addition to generic conflict operation commands.

AI payload note:
- list_ai_providers includes provider discovery diagnostics: `{ resolvedBinary?, detectionSource?, healthCheck }`.
- get_ai_audit_entries returns locally persisted redacted prompt/output previews for backend AI actions.
- run_ai_diff_review and start_ai_diff_review_job enforce read-only guardrails; write-intent prompts return `ai.guardrail_blocked`.

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

Implementation update (2026-04-03):
- All tauri command handlers now use telemetry-aware success/error wrappers that emit command-level duration and outcome samples.
- Backend now persists structured operation lifecycle events (`start`, `success`, `failure`, `retry`) with correlation IDs in local rolling storage.
- System Git command execution now includes transient retry events for network-class operations (`fetch`, `pull`, `push`, `ls-remote`, `remote`) when failures match retryable network signatures.
- Command handlers now initialize per-request correlation context at command entry, so nested service/git spans share the same requestId lineage.
- Diff chunk manifest/chunk retrieval now emits backend diff telemetry spans with payload and chunk metadata (`renderer_mode=backend-chunking`).
