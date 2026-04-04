# Roadmap

## Phase 0 - Foundation (Week 0-1)
Deliverables:
- Repo bootstrap (Tauri + Solid + TypeScript + Rust workspace)
- Command contract scaffolding and error model
- System Git capability detection and auth diagnostics baseline
- Minimum supported Git version gate (2.39+)
- Basic app shell and repository selector
- CI checks (format, lint, tests, build)

Exit criteria:
- App launches cross-platform in dev mode
- One repo can be opened and inspected
Implementation update (2026-04-03):
- Backend now performs asynchronous startup readiness probing (git capabilities, auth baseline, forge adapters, AI providers) and records bootstrap lifecycle spans for diagnostics.

## Phase 1 - Core Loop MVP (Week 2-4)
Deliverables:
- Status view with stage/unstage controls
- Commit creation panel
- Branch switch/create basics
- Pull/push/fetch basic flow
- Forge adapter skeleton with optional GitHub enhancement path
- Basic diff view with Pretext-driven line layout and virtualized DOM surface

Exit criteria:
- Daily workflow can run entirely in app for simple repos
- No critical data-loss bugs in manual tests

## Phase 2 - Performance and Stability (Week 5-7)
Deliverables:

Exit criteria:
Implementation update (2026-04-03):
- Backend diff chunking/hunk metadata APIs are implemented and covered by parsing/chunking unit tests.
- Backend diff chunk APIs now emit diff-scoped telemetry samples and span metadata to support renderer-path diagnostics.

## Phase 3 - AI Assist Layer (Week 8-10)
Deliverables:

Exit criteria:
Implementation update (2026-04-03):
- Backend now exposes first-class rebase/cherry-pick command workflows (start/continue/abort variants).
- Backend git execution now emits lifecycle events and transient retry diagnostics for network-class sync operations.

## Phase 4 - Advanced Git and UX Polish (Week 11-14)
Deliverables:
- Rebase/cherry-pick workflows
- Conflict resolution UX improvements
- Command palette and keyboard-first navigation
- Theme customization with single compact-density design
- Panel resize and panel rearrange controls

Exit criteria:
- Power-user workflow parity with current personal GitHub Desktop usage
- Strong subjective UX acceptance in dogfooding

## Phase 5 - Hardening and Public Alpha (Week 15+)
Deliverables:
- Installers with Linux Flatpak-first packaging
- Stable and beta update channels
- Crash reporting options
- Documentation and onboarding flow
- Security and privacy review
- Alpha feedback loop and issue triage cadence

Implementation update (2026-04-03):
- Backend settings now expose stable/beta update channel selection and crash-reporting toggle commands (`update_update_channel`, `update_crash_reporting`).
- Crash-report option now installs a backend panic hook that persists local crash artifacts when enabled.
- Linux packaging baseline now includes a Flatpak manifest scaffold (`apps/desktop/flatpak/com.gdpu.desktop.json`) plus CI manifest validation on Ubuntu.

Implementation update (2026-04-03):
- Backend now exposes updater runtime commands for channel-aware check/install workflows (`check_for_app_update`, `install_app_update`) using Tauri updater integration.
- Settings UI now includes release update actions to check and install available updates without leaving the app.
- Alpha hardening document pack added under `docs/alpha/` for onboarding, known issues, security/privacy posture, and feedback triage cadence.

Exit criteria:
- Stable alpha builds for external users
- Prioritized post-alpha backlog
