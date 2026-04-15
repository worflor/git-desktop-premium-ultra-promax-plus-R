# Git Desktop Premium Ultra Promax Plus-R

Git Desktop is an ambitious desktop Git client project focused on fast local workflows, richer repository context, and stronger visual tooling than a plain status/history UI.

This repository now has a clear split:

- `apps/desktop-flutter/README.md` is the canonical detailed README for the Flutter desktop app
- this root `README.md` is the repo-level overview for the broader project and docs set

## Start here

If you want the runnable Dart app:

- [apps/desktop-flutter/README.md](apps/desktop-flutter/README.md)

If you want the broader planning and architecture material:

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

## Repo layout

- `apps/desktop-flutter`
  - current Flutter desktop app
- `docs/`
  - product, architecture, UX, and planning docs

## What the Flutter app already covers

The Flutter app already includes:

- day-to-day Git operations through the system Git binary
- staged/unstaged workflow, diffing, history, stash, worktrees, and interactive rebase support
- Logos related-file ranking and repository-context tooling
- Engram semantic indexing over local code tokens
- X-Ray analytics views for hotspots, cadence, keystones, and repo activity summaries
- optional AI-backed commit/review workflows through configured providers
- a substantial theme, animation, and diagnostics layer

For the full walkthrough, storage model, math notes, and feature semantics, use:

- [apps/desktop-flutter/README.md](apps/desktop-flutter/README.md)

## Mission

Build a fast, native-feeling Git desktop client that:

- handles real local Git workflows without ceremony
- surfaces repository context instead of only file lists
- keeps AI features optional and explicit
- treats visual design and diagnostics as product features, not garnish

## Product principles

- Speed over ceremony
- Native feel over web-app feel
- Explainability over opaque AI
- Local-first defaults
- Extensibility without plugin chaos

## Scope strategy

We are not starting with parity on every GitHub Desktop feature.

Phase strategy:

1. Build a thin but elite core loop: status -> stage -> commit -> diff -> push/pull.
2. Make context and performance on larger repos a first-class concern.
3. Add advanced Git, review, and AI workflows without turning the app into a generic chat wrapper.

## Quick start for the Flutter app

```bash
cd apps/desktop-flutter
flutter pub get
flutter run -d windows
```

## License

See the project root for license information.
