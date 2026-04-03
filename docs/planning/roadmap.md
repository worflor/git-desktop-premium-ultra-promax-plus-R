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
- Large-diff detection and Pretext-driven canvas rendering path
- Renderer benchmark harness and telemetry dashboards for Pretext layout hot paths
- Pretext accuracy and upgrade gate automation in CI
- Profiling instrumentation and perf dashboards/logging
- Robust error handling and retries around system Git operations
- Regression test suite with large synthetic repos

Exit criteria:
- Meets initial perf budgets on target hardware
- Handles 10k+ changed lines without unusable UI jank
- Renderer mode selection is deterministic and validated on fixtures
- Pretext layout correctness passes unicode/bidi/long-line fixture corpus

## Phase 3 - AI Assist Layer (Week 8-10)
Deliverables:
- Provider detection for Codex/Claude/Gemini/OpenCode
- Streaming AI review panel for selected files/hunks
- Prompt templates (review, summarize, risky changes)
- Audit trail for AI interactions
- Guardrail slider (0.0 to 1.0) mapped to Loose/Balanced/Strict/Paranoid profiles

Exit criteria:
- AI results stream reliably from at least one provider
- AI failure states are understandable and recoverable

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

Exit criteria:
- Stable alpha builds for external users
- Prioritized post-alpha backlog
