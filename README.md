# Git Desktop Premium Ultra Promax Plus-R

A high-performance, AI-augmented Git desktop app intended to replace GitHub Desktop for daily use.

## Mission
Build a fast, native-feeling, cross-platform Git client with:
- Full local Git workflows (clone, branch, commit, stash, rebase, cherry-pick, conflict resolution)
- First-class diff performance at large scale
- Pluggable local AI review/assist via installed CLIs (no mandatory cloud key flow)
- A UI that is intentional, customizable, and not "enterprise bland"

## Product Principles
- Speed over ceremony
- Native feel over web-app feel
- Explainability over magic AI
- Local-first and privacy-respecting defaults
- Extensibility without plugin chaos

## Proposed Stack
- Shell/runtime: Tauri (Rust backend + native webview)
- Git engine: Rust + system Git CLI provider (platform-agnostic baseline)
- UI: Solid.js (primary) with Vite + TypeScript
- High-scale text rendering: Pretext-first layout engine with virtualized DOM + canvas rendering surfaces
- AI integration: Rust child-process adapters for local CLIs (Codex, Claude, Gemini, OpenCode)

Detailed rationale is in [docs/architecture/stack-decision.md](docs/architecture/stack-decision.md).

## Documentation Index
- [docs/product/vision.md](docs/product/vision.md)
- [docs/architecture/system-architecture.md](docs/architecture/system-architecture.md)
- [docs/architecture/stack-decision.md](docs/architecture/stack-decision.md)
- [docs/architecture/command-contract.md](docs/architecture/command-contract.md)
- [docs/architecture/diff-rendering-architecture.md](docs/architecture/diff-rendering-architecture.md)
- [docs/architecture/vcs-auth-strategy.md](docs/architecture/vcs-auth-strategy.md)
- [docs/architecture/repo-structure.md](docs/architecture/repo-structure.md)
- [docs/architecture/open-questions.md](docs/architecture/open-questions.md)
- [docs/research/pretext-evaluation.md](docs/research/pretext-evaluation.md)
- [docs/research/t3code-ux-inspiration.md](docs/research/t3code-ux-inspiration.md)
- [docs/ui/layout-and-component-spec.md](docs/ui/layout-and-component-spec.md)
- [docs/ui/icon-and-motion-system.md](docs/ui/icon-and-motion-system.md)
- [docs/planning/roadmap.md](docs/planning/roadmap.md)
- [docs/planning/execution-model.md](docs/planning/execution-model.md)
- [docs/planning/risk-register.md](docs/planning/risk-register.md)
- [docs/planning/backlog-v1.md](docs/planning/backlog-v1.md)
- [docs/planning/bootstrap-checklist.md](docs/planning/bootstrap-checklist.md)
- [docs/planning/program-plan.md](docs/planning/program-plan.md)
- [docs/planning/sprint-0-plan.md](docs/planning/sprint-0-plan.md)
- [docs/planning/pretext-adoption-plan.md](docs/planning/pretext-adoption-plan.md)
- [docs/planning/implementation-decisions.md](docs/planning/implementation-decisions.md)
- [docs/planning/agent-execution-contract.md](docs/planning/agent-execution-contract.md)

## Scope Strategy
We are not starting with parity on every GitHub Desktop feature.

Phase strategy:
1. Build a thin but elite core loop (status -> stage -> commit -> diff -> push/pull).
2. Achieve "faster than GitHub Desktop" on large repos.
3. Add advanced Git + AI workflows incrementally.

## Success Metrics (Initial)
- Cold start (app launched to interactive): <= 1.5s on mid-range hardware
- Repo status refresh: <= 200ms on a 100k-file monorepo (warm cache target)
- Diff open (10k+ changed lines): <= 150ms to first paint
- Scroll performance in large diffs: sustained 60 FPS, target 120 FPS on capable hardware
- AI diff review response stream starts: <= 2.0s when local CLI is available

## Current Status
Project initialized with planning and architecture docs. Pretext is committed as core diff-layout engine and implementation scaffold is next.

## Implementation Status
- Monorepo scaffold created under `apps/desktop`.
- Solid + TypeScript UI shell with route skeleton (`/changes`, `/history`, `/branches`, `/sync`, `/settings`) is implemented.
- Typed command contract client is wired from UI to Tauri command names.
- Rust backend command layer is implemented for repository open/recents, status and commit flow, branch/worktree flow, sync operations, conflict state/continue/abort, local issue and pull-request models, and AI review job lifecycle.
- Sync and Settings UX now include conflict controls, auth/integration diagnostics, and local command latency diagnostics with retention controls.
- Crash-safe recovery UX now includes global retry for recoverable command failures and a utility drawer with command lifecycle logs (start/success/failure/retry).
- Reliability hardening now includes Git CLI fixture-parity tests for key operations and CI execution coverage in `.github/workflows/desktop-ci.yml`.
- Compact density layout controls now persist sidebar width/position and utility drawer default expansion/height, including shell drag-resize interactions.
- Theme and keybinding customization now persist in settings with app-wide live theme application (Aether, Helix, Quanta, Petrichor, Redshift, Halo) and global profile-driven route hotkeys.
- Custom icon registry and animation-ready icon wrappers are in place.

## Bootstrap
```bash
npm install
npm run typecheck --workspace apps/desktop
npm run build --workspace apps/desktop
```

## Run Desktop Dev Mode
```bash
npm run tauri:dev --workspace apps/desktop
```

## Windows Rust Tooling Note
For Tauri Rust builds on Windows, install one of the following:
- Visual Studio Build Tools with C++ workload (for MSVC linker `link.exe`), or
- GNU binutils with `dlltool.exe` available in `PATH`.
