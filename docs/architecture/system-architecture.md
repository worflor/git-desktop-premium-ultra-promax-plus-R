# System Architecture

## Top-Level Components
1. Desktop shell (Tauri)
2. Core services (Rust)
3. UI application (Solid.js + TypeScript)
4. AI provider adapters (Rust child-process layer)
5. Persistence/config (local app data + secure credential store)

## Backend Service Modules (Rust)
- repository_service: open/switch/list repositories
- git_provider_service: system Git command orchestration and normalized result mapping
- forge_provider_service: optional host-specific capabilities (GitHub/GitLab/Bitbucket adapters)
- auth_service: auth readiness checks and diagnostics for helpers/SSH/providers
- status_service: file status, staging/unstaging, index operations
- commit_service: commit creation, amend, signing hooks
- history_service: log, graph, branch pointers
- branch_service: create/switch/delete/rename/track
- sync_service: fetch/pull/push/auth workflows
- merge_rebase_service: conflict state, continue/abort flows
- diff_service: diff computation, hunk metadata, pagination/chunking
- ai_service: provider discovery, prompt assembly, streaming output
- settings_service: per-user/per-repo settings

## Frontend Domains (Solid)
- shell: app layout, navigation, command palette
- repositories: list, open, recents
- changes: status list, staging controls, commit panel
- diff-view: file tree, hunk navigator, renderer surface
- history: commit graph and detail view
- sync: remote status, fetch/pull/push controls
- ai-panel: review controls, prompt templates, stream output
- settings: providers, keybindings, UI density/theme

## Command Contract
Tauri command boundary should use versioned DTOs.

Example pattern:
- command: get_repository_status
- request: { repoId, includeUntracked, includeSubmodules }
- response: { head, aheadBehind, changedFiles[], summary }

Rules:
- Keep command payloads explicit and typed
- Return structured errors (code, message, details)
- Never leak raw internal exceptions to UI

## VCS and Forge Integration
Core model:
- GitProvider is required and backed by system Git CLI.
- ForgeProvider is optional and host-specific.
- Core repo operations must not depend on forge-specific adapters.

Behavior expectations:
- If a forge adapter is unavailable, core Git workflows still function.
- Host-specific actions should fail soft with clear diagnostics.

Detailed strategy is defined in [docs/architecture/vcs-auth-strategy.md](docs/architecture/vcs-auth-strategy.md).

## Diff Rendering Strategy
Pretext-first strategy:
- Pretext computes line layout and measurement as the shared source of truth.
- Small/medium diffs render through virtualized DOM.
- Large diffs render through canvas using the same Pretext-derived line map.
- Emergency fallback path exists only for runtime resilience.

Renderer requirements:
- Stable line number mapping
- Incremental chunk loading
- Jump-to-hunk and minimap hooks
- Search-in-diff support without full DOM materialization
- Pretext line metadata reused across renderer modes to avoid mapping drift

Detailed mode selection, interaction model, and telemetry are specified in [docs/architecture/diff-rendering-architecture.md](docs/architecture/diff-rendering-architecture.md).

## AI Integration Architecture
### Provider detection
At startup and on demand, discover installed CLIs by:
- PATH scanning
- Known install paths (OS-specific)
- Health-check commands

### Adapter interface
Each provider implements:
- name()
- is_available()
- build_command(prompt, context)
- stream_response(callback)
- parse_error(stderr)

### Safety and trust
- Default to read-only AI operations
- Require explicit user confirmation for any action that executes commands
- Log all AI-triggered operations in an audit pane

## Data and State
- UI state: in-memory store with optimistic updates where safe
- Persistent settings: local JSON/TOML with schema versioning
- Credentials/tokens: OS-native secure store

## Auth and Credentials
- Primary auth path: system Git credential helper and SSH agent.
- Optional host adapter auth status (for example gh auth state) augments diagnostics.
- Avoid handling plaintext credentials in app-managed storage.

## Error and Observability
- Structured logs (info/warn/error) with correlation IDs
- Perf spans around key operations (status, diff, sync, AI request)
- User-visible diagnostics page for provider and repo health

## Performance Budgets
- Command round-trip p95: <= 50ms for status metadata
- Diff first paint p95: <= 200ms on large changes
- Memory ceiling target: < 400MB under heavy diff session
- No UI main-thread stalls > 100ms in normal workflows
