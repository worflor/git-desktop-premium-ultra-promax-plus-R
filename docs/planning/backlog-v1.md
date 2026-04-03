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

### C-2 Pretext + virtualized DOM baseline (P1)
Acceptance criteria:
- Large diff does not freeze UI thread
- Scroll remains responsive at 10k+ lines
- Render timing is instrumented
- Pretext prepare/layout timings are tracked separately

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

## EPIC D - Sync Workflow
### D-1 Fetch/pull/push operations (P1)
Acceptance criteria:
- User can fetch, pull, push for current branch
- Auth failures return clear guidance
- Operation states (running/success/fail) are visible

### D-2 Auth diagnostics baseline (P1)
Acceptance criteria:
- Detects SSH and credential helper readiness
- Shows per-remote auth diagnostics with suggested fixes
- Does not require app-managed plaintext credential storage

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

## EPIC E - AI Assist
### E-1 Provider detection (P1)
Acceptance criteria:
- Detects installed Codex/Claude/Gemini/OpenCode CLIs
- Shows availability state and basic diagnostics
- Degraded mode does not break app if no provider exists

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

### E-4 AI guardrail slider model (P1)
Acceptance criteria:
- Slider maps continuous value to Loose/Balanced/Strict/Paranoid profiles
- Default profile is Balanced for new installs
- Read-only AI actions remain default in base workflows

## EPIC F - Reliability and Performance
### F-1 Command latency instrumentation (P0)
Acceptance criteria:
- p50/p95 duration captured per command
- Diagnostics view can display recent operation timings

### F-4 Local telemetry retention policy (P1)
Acceptance criteria:
- Telemetry remains local-only by default
- Rolling log retention supports configurable time and size caps
- Default retention policy is safe against disk bloat

## EPIC H - UX Interaction Model
### H-1 Single compact density policy (P1)
Acceptance criteria:
- App ships with one compact density mode only
- Theme switching is supported without density mode switching
- Panel resizing and rearranging are supported in compact mode

### F-2 Compatibility fixture suite (P1)
Acceptance criteria:
- Key operations compared against git CLI fixture expectations
- CI runs fixtures and reports diffs clearly

### F-3 Crash-safe and recoverable UX states (P1)
Acceptance criteria:
- No workflow dead ends after command failure
- Retry paths available for major operations

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
