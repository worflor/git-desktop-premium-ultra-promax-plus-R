# Execution Model

## Planning Framework
Use a lightweight dual-track loop:
- Discovery track: define UX, risks, acceptance criteria
- Delivery track: implement smallest vertical slice that proves value

Work in weekly cycles with explicit outcomes.

## Standard Work Item Template
Each feature task should include:
- Problem: what user pain this solves
- Scope: what is in/out
- Acceptance criteria: observable behaviors
- Telemetry/perf impact: what must be measured
- Risk notes: likely failure modes

For technical spikes, also include:
- Explicit decision to make at spike end
- Timebox (default 2 days)
- Go/no-go criteria and required evidence artifacts

## Definition of Ready (DoR)
A task is ready when:
- API/command contract is clear
- UX states are defined (loading/empty/error/success)
- Test strategy is listed
- Dependencies are identified

## Definition of Done (DoD)
A task is done when:
- Behavior matches acceptance criteria
- Unit/integration tests are present and passing
- Logging/error handling is sufficient
- No obvious performance regressions introduced
- Docs updated if public behavior changed

Spike-specific done criteria:
- Decision captured in architecture docs
- Benchmark results attached or linked
- Follow-up backlog actions created

## Weekly Cadence (Solo-Friendly)
- Monday: commit to weekly goals and risks
- Midweek: deliver first vertical slice and validate assumptions
- Friday: stabilize, measure, and write short retrospective

## Issue Taxonomy
Use labels:
- type:feature
- type:bug
- type:tech-debt
- type:perf
- type:docs
- priority:p0/p1/p2
- area:backend/ui/ai/diff/git

## Quality Gates
Before merging mainline changes:
- Build passes on target OS
- Test suite passes
- Lint/format checks pass
- Manual sanity check for critical flows (open repo, status, commit)

## First 10 Engineering Tasks
1. Scaffold Tauri + Solid + TypeScript workspace.
2. Define Rust command error envelope and DTO conventions.
3. Implement system Git capability detection and version checks.
4. Implement auth diagnostics for credential helpers and SSH readiness.
5. Implement repository open/list recent repositories.
6. Implement status_service minimal file status output.
7. Build changes panel with stage/unstage interactions.
8. Implement commit_service with validation and commit execution.
9. Implement Pretext layout adapter and cache strategy for diff domain.
10. Add instrumentation and regression fixtures for command latency, Pretext timing, and unicode/bidi edge cases.
