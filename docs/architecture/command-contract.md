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
5. list_forge_adapters
6. get_repository_status
7. stage_paths
8. unstage_paths
9. create_commit
10. get_file_diff
11. fetch_remote
12. pull_remote
13. push_remote
14. list_ai_providers
15. run_ai_diff_review

## DTO Guidelines
- Use explicit, named fields; avoid tuple-like arrays.
- Keep dates in ISO-8601 string format.
- Keep path fields normalized to absolute internal form in backend, convert to display-safe paths in UI.
- Do not include secrets in DTOs.

## Streaming Commands
For long-running operations (AI, large diff prep):
- return immediate ack with requestId
- stream progress events via Tauri event channel
- support cancellation by requestId

Event naming convention:
- op.progress
- op.chunk
- op.completed
- op.failed

## Observability Requirements
Every command must:
- Generate requestId
- Log start/end with duration and status
- Attach domain-specific counters for performance dashboards
