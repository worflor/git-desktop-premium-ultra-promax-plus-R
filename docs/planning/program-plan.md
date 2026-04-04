# Program Plan (Execution Expansion)

## Planning Horizon
12 to 16 weeks to reach internal replacement readiness.

## Workstreams
1. Git Core Engine
2. Diff and Performance (Pretext-first)
3. AI Provider Layer
4. UX and Workflow Polish
5. Quality, Release, and Ops

## Milestones and Gates
### M0: Bootstrap Complete
Gate:
- App starts on Windows dev machine
- One repository can open and return status
- System Git and auth diagnostics report usable readiness

### M1: Core Loop Usable
Gate:
- stage/unstage/commit/sync works for normal repos
- no known P0 data-loss scenarios

### M2: Large Diff Reliable
Gate:
- meets first paint + scroll budgets on large fixtures
- renderer fallback behavior is deterministic and tested
- Pretext layout correctness passes fixture corpus across target platforms

### M3: AI Assist Practical
Gate:
- provider detection and stream review work with at least one CLI
- AI failures have clear, actionable UX

### M4: Personal Workflow Replacement
Gate:
- full daily workflow done inside app for 2 weeks
- logged blockers are triaged or resolved

### M5: Public Alpha Candidate
Gate:
- install/update path validated
- crash and error diagnostics adequate for external feedback loop

## Weekly Operating Rhythm
- Monday: pick 3 to 5 highest-value tasks with explicit acceptance criteria
- Wednesday: risk review and scope trim if needed
- Friday: performance and reliability review, then retro notes

## Capacity Guardrails (Solo)
- Target 70% feature work, 20% hardening, 10% docs/ops
- Keep active WIP to max 2 in-progress items
- Timebox spikes to 2 days unless promoted by data

## KPI Dashboard (Track Weekly)
- Core loop completion success rate
- p95 status refresh latency
- p95 diff first paint
- crash-free session ratio
- AI request success ratio

## Exit to Alpha Checklist
- Installer works and can rollback
- Diagnostics page includes environment and provider health
- Known issues list is explicit and user-facing
- Minimal onboarding doc exists for first-time setup

Implementation update (2026-04-03):
- Runtime update check/install command path is implemented and surfaced in Settings release controls.
- Alpha hardening pack now includes onboarding, known issues, security/privacy review, and feedback triage cadence docs under `docs/alpha/`.
