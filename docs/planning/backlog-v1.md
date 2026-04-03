# Backlog V1 (Execution-Ready)

## Prioritization Method
- P0: blocks core loop
- P1: critical for replacing current workflow
- P2: quality/polish or future growth

## EPIC A - Repo and Status Foundation
### A-1 Initialize app scaffold (P0)
Acceptance criteria:
- Tauri + Solid + TypeScript app runs locally
- Rust and UI build pass
- Basic app shell renders on startup

### A-0 System Git provider bootstrap (P0)
Acceptance criteria:
- App detects system Git path and version at startup
- Enforces minimum supported Git version (2.39+)
- Missing Git state returns actionable setup guidance
- Command wrapper returns structured stdout/stderr/error envelopes
Implementation update (2026-04-03):
- Backend startup now runs an asynchronous readiness probe for git capabilities, auth baseline, forge adapters, and AI providers with structured bootstrap spans.
- Git capability payload now includes resolved executable path diagnostics when host lookup succeeds.

### A-2 Repository open and recents (P0)
Acceptance criteria:
- User can open local repo path
- Recent repositories list persists across restarts
- Invalid path errors are actionable

### A-3 Status service MVP (P0)
Acceptance criteria:
- Shows branch name and ahead/behind counts
- Shows changed files with status type
- Refresh action updates status without app restart

## EPIC B - Commit Workflow
### B-1 Stage/unstage file actions (P0)
Acceptance criteria:
- Stage and unstage operations work per file
- UI reflects operation results within one refresh cycle
- Failures show domain error code and message

### B-2 Commit panel and validation (P0)
Acceptance criteria:
- Commit requires non-empty message
- Successful commit clears message and refreshes status
- Error path preserves unsent message for retry

## EPIC C - Diff Experience
### C-0 Renderer architecture baseline (P0)
Acceptance criteria:
- Renderer mode selection rules are documented and implemented
- Thresholds are configurable and telemetry-tagged by mode
- Fallback behavior between modes is deterministic
- Pretext is wired as the shared line layout engine for renderer modes A/B

### C-1 File diff API and UI wiring (P1)
Acceptance criteria:
- User can open selected file diff
- Line additions/deletions render accurately
- Basic search-in-file diff works
- Pretext-derived line mapping is used for row, hunk, and cursor navigation
Implementation update (2026-04-03):
- Backend now exposes chunked diff APIs via `prepare_file_diff_chunks` and `get_file_diff_chunk` with hunk metadata and size/line counters.
- Diff payload caching and expiry are now implemented in backend runtime state for incremental transfer to UI.
- Oversized diff payloads now return a typed `diff.too_large` contract error.

### C-2 Pretext + virtualized DOM baseline (P1)
Acceptance criteria:
- Large diff does not freeze UI thread
- Scroll remains responsive at 10k+ lines
- Render timing is instrumented
- Pretext prepare/layout timings are tracked separately
Implementation update (2026-04-03):
- Backend diff manifest now includes renderer mode metadata and Pretext telemetry fields (`pretextVersion`, `pretextPrepareMs`, `pretextLayoutMs`, fallback activation metadata, visual row counts, and layout cache keying inputs).
- Diff prepare telemetry now records dedicated samples for pretext prepare/layout durations and fallback activations.

### C-3 Pretext + canvas threshold path (P1)
Acceptance criteria:
- Threshold trigger for large diffs is configurable
- Canvas path supports line numbers and hunk boundaries
- Users can still copy visible text lines
- Canvas path reuses Pretext cursor and line-range metadata

### C-4 Pretext hardening and upgrade gates (P1)
Acceptance criteria:
- CI runs Pretext correctness fixtures (unicode, bidi, long-line)
- Upgrade checklist exists for Pretext version bumps
- Emergency fallback activation rate is observable and < 0.1% in internal dogfooding
Implementation update (2026-04-03):
- CI now runs both fixture correctness gate (`pretext:fixtures`) and canary benchmark gate (`pretext:canary`).
- Version bump checklist is codified in `docs/planning/pretext-version-bump-checklist.md`.

## EPIC D - Sync Workflow
### D-1 Fetch/pull/push operations (P1)
Acceptance criteria:
- User can fetch, pull, push for current branch
- Auth failures return clear guidance
- Operation states (running/success/fail) are visible
Implementation update (2026-04-03):
- Backend git command execution now applies transient retry handling for network-class operations (`fetch`, `pull`, `push`, `ls-remote`, `remote`) when failures match retryable network signatures.
- Retry attempts emit structured backend lifecycle retry events for diagnostics.

### D-2 Auth diagnostics baseline (P1)
Acceptance criteria:
- Detects SSH and credential helper readiness
- Shows per-remote auth diagnostics with suggested fixes
- Does not require app-managed plaintext credential storage
Implementation update (2026-04-03):
- Backend auth status now includes GitHub CLI availability/authentication diagnostics.
- Per-remote guidance now includes GitHub-specific remediation when `gh` is installed but unauthenticated.

## EPIC G - Forge Adapters (Optional Enhancements)
### G-1 Forge adapter capability model (P1)
Acceptance criteria:
- Capability matrix indicates available host features per remote
- Core Git workflows remain usable when no adapter is present

### G-2 GitHub adapter via optional gh integration (P2)
Acceptance criteria:
- Detects gh availability and login status
- Exposes GitHub-specific enhancements without blocking core workflows
- Degraded path uses remote URL handoff when adapter unavailable
Implementation update (2026-04-03):
- Forge adapter diagnostics now probe `gh auth status` and expose adapter auth state metadata.
- Repository integration matrix now emits GitHub capability signals for authenticated vs unauthenticated optional adapter paths.

## EPIC E - AI Assist
### E-1 Provider detection (P1)
Acceptance criteria:
- Detects installed Codex/Claude/Gemini/OpenCode CLIs
- Shows availability state and basic diagnostics
- Degraded mode does not break app if no provider exists
Implementation update (2026-04-03):
- AI provider discovery now returns resolved binary command, detection source, and health-check status.
- Detection now includes PATH plus known install path probes to improve Windows and non-PATH discovery.
- Provider adapter contract tests now validate attempt strategy generation and truncation guarantees for bounded prompt/diff payload construction.

### E-2 Diff review stream panel (P1)
Acceptance criteria:
- User can run review on selected file/hunk
- Response streams incrementally in UI
- User can cancel in-flight request

### E-3 Prompt templates and audit trail (P2)
Acceptance criteria:
- User can pick from baseline templates
- Prompt and output metadata is logged locally
- Sensitive content redaction strategy is documented
Implementation update (2026-04-03):
- Backend now persists a local AI audit trail under the app data root (`gdpu/ai_review_audit.jsonl`) with retention limits.
- Prompt/output previews are redacted and truncated before persistence.
- New command `get_ai_audit_entries` exposes audit metadata for diagnostics and future UI surfacing.

### E-4 AI guardrail slider model (P1)
Acceptance criteria:
- Slider maps continuous value to Loose/Balanced/Strict/Paranoid profiles
- Default profile is Balanced for new installs
- Read-only AI actions remain default in base workflows
Implementation update (2026-04-03):
- Backend guardrail mapping now defaults a value of `0.5` to the Balanced profile.
- Regression test added to enforce Balanced default behavior for new installs.
- AI review execution now enforces read-only guardrails and blocks write-intent prompts with contract error code `ai.guardrail_blocked`.
- Guardrail-blocked attempts are recorded in the backend AI audit trail for diagnostics visibility.

## EPIC F - Reliability and Performance
### F-1 Command latency instrumentation (P0)
Acceptance criteria:
- p50/p95 duration captured per command
- Diagnostics view can display recent operation timings
Implementation update (2026-04-03):
- Backend now records system Git command telemetry samples with command label, duration, success/failure status, and mapped error code.
- All tauri command endpoints now emit backend telemetry samples with command-level success/failure classification.
- Rolling retention policy is enforced in backend storage using configured telemetry days/MB caps from app settings.
- Backend telemetry snapshot command now returns aggregated p50/p95 summaries and recent samples for diagnostics tooling.
- Backend settings updates for telemetry retention now trigger immediate retention enforcement in backend storage.
- Backend now persists structured operation lifecycle events (`start`, `success`, `failure`, `retry`) with request correlation IDs for command and git scopes.
- Command handlers now set request context before service execution so nested spans and git command spans preserve command-level correlation IDs.
- Diff chunk preparation and chunk retrieval now emit diff-scoped telemetry samples and span messages with payload/chunk metrics.

### F-4 Local telemetry retention policy (P1)
Acceptance criteria:
- Telemetry remains local-only by default
- Rolling log retention supports configurable time and size caps
- Default retention policy is safe against disk bloat
Implementation update (2026-04-03):
- Backend telemetry storage is local-only and persisted under APPDATA/gdpu.
- Retention policy is applied by both age and size, keeping newest samples within configured bounds.
- Malformed telemetry lines are safely ignored to preserve crash-resistant diagnostics reads.
- Backend exposes a telemetry-clear maintenance command for deterministic diagnostics reset.
- Backend persistence paths now resolve cross-platform data roots (Windows/macOS/Linux/XDG) with a shared storage-path resolver and optional `GDPU_DATA_DIR` override.

## EPIC H - UX Interaction Model
### H-1 Single compact density policy (P1)
Acceptance criteria:
- App ships with one compact density mode only
- Theme switching is supported without density mode switching
- Panel resizing and rearranging are supported in compact mode
Implementation update (2026-04-03):
- Sidebar rail now supports drag and keyboard resizing with persisted width bounds.
- Sidebar can be rearranged to either left or right position through layout preferences.
- Utility drawer default expansion and height are now persisted and support drag/keyboard resize in shell.
- Theme switching now supports Aether, Helix, Quanta, Petrichor, Redshift, and Halo themes without changing compact density policy.
- Keybinding profiles now support Classic chord navigation and Compact single-stroke navigation with global route hotkeys.

### F-2 Compatibility fixture suite (P1)
Acceptance criteria:
- Key operations compared against git CLI fixture expectations
- CI runs fixtures and reports diffs clearly
Implementation update (2026-04-03):
- Backend fixture parity tests now cover status stage/unstage, branch listing, commit history/detail, and merge-conflict detection/abort against direct git CLI outputs.
- CI now includes a dedicated fixture test step via `cargo test fixture_ -- --nocapture`.
- Additional backend unit coverage now validates diff chunk parsing/chunking behavior, AI audit redaction/retention behavior, forge/AI adapter contract invariants, and transient git retry classification.
- Fixture parity coverage now also validates stash lifecycle parity and worktree create/remove behavior against direct git CLI outputs.
- Performance budget tests now gate command status p95 and diff prepare p95 latency (`cargo test perf_budget_ -- --nocapture`).

### Advanced Git Workflow Expansion (P1)
Acceptance criteria:
- Rebase and cherry-pick flows are available as explicit command APIs.
- Continue/abort operations exist as operation-specific command variants.
- Conflict-oriented workflows remain compatible with existing generic conflict commands.
Implementation update (2026-04-03):
- Backend now exposes `start_rebase`, `continue_rebase`, `abort_rebase`, `start_cherry_pick`, `continue_cherry_pick`, and `abort_cherry_pick` commands.
- Existing generic conflict commands remain available for merge/rebase/cherry-pick/revert fallback behavior.

### F-3 Crash-safe and recoverable UX states (P1)
Acceptance criteria:
- No workflow dead ends after command failure
- Retry paths available for major operations
Implementation update (2026-04-03):
- Frontend command client now tracks recoverable command failures and exposes global retry APIs for the last failed command.
- Shell now renders a recovery banner with retry and dismiss controls, preventing dead-end error states after command failures.
- Utility drawer now shows rolling command lifecycle events (start/success/failure/retry) for major workflows.

## Suggested Sprint 1 Scope (2 Weeks)
- A-0
- A-1, A-2, A-3
- B-1, B-2
- C-0
- C-1 (partial)
- F-1

## Sprint 1 Exit Definition
- You can run the full minimal loop:
  open repo -> inspect changes -> stage/unstage -> commit -> inspect diff
- Command failures are visible and understandable
- No known P0 bugs in manual smoke tests
