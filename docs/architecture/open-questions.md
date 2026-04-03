# Open Questions

## Product and Scope
1. What level of GitHub-specific integration is required for replacement workflow beyond optional adapter enhancements?

## Technical
1. Which diff-size threshold should trigger canvas rendering path?
2. Should we introduce optional git2 acceleration in V2, or only after profiler evidence from V1 dogfooding?
3. Should we add AppImage in parallel with Flatpak for Linux distribution redundancy?

## AI Layer
1. Should AI prompt context include entire file, selected hunk, or configurable context window by default?
2. What is the default policy for retaining prompt/output history locally?

## UX
1. Do we target keyboard-first command palette in MVP, or Phase 2?

## Delivery
1. What weekly hour budget is realistic for sustained solo development?
2. What objective criteria defines "ready to replace current workflow" for dogfooding switch?

## Decision Logging Rule
When any question is resolved:
- Add answer + date + rationale
- Link to implementation PR/commit
- Update affected docs (roadmap, architecture, backlog)

## Provisional Decisions (Pending Validation)
- 2026-04-03: Adopt Pretext as the core diff text-layout engine for V1.
	Rationale: aligns with product performance goals and desired architecture direction; shared layout pipeline across DOM/canvas reduces mode drift.
	Evidence: [docs/research/pretext-evaluation.md](docs/research/pretext-evaluation.md).
- 2026-04-03: Adopt system Git provider as default core Git engine, with optional forge adapters.
	Rationale: platform-agnostic behavior, auth compatibility, and reduced host coupling.
	Evidence: [docs/architecture/vcs-auth-strategy.md](docs/architecture/vcs-auth-strategy.md).
- 2026-04-03: Lock implementation defaults for providers, guardrails, logging, and compact UI policy.
	Rationale: reduce ambiguity for AI coding agent execution.
	Evidence: [docs/planning/implementation-decisions.md](docs/planning/implementation-decisions.md).
