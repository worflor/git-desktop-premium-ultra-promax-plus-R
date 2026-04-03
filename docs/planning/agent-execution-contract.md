# Agent Execution Contract (Pre-Build)

## Purpose
Define how AI coding agents should work in this project so implementation quality stays high over long runs.

## Core Rules
1. Respect architecture boundaries from docs before adding files.
2. Prefer small vertical slices with tests and diagnostics.
3. Never bypass provider abstractions for convenience.
4. Preserve platform-agnostic behavior in all core Git flows.

## Delivery Sequence
1. Foundation scaffolding and shared contracts.
2. System Git capability and auth diagnostics.
3. Repository and status vertical slice.
4. Stage/commit vertical slice.
5. Pretext DOM diff path.
6. Canvas diff path and fallback.
7. AI provider integration and guardrail control.

## Guardrail Profiles
The app supports four user profiles mapped from a 0 to 1 slider.

- Loose: minimal checks, high velocity.
- Balanced: default checks for safety and speed.
- Strict: stronger checks before execution.
- Paranoid: maximum verification and explicit confirmations.

## Quality Gates Per Change
1. Build passes.
2. Relevant tests pass.
3. New command paths emit telemetry spans.
4. User-facing error states include actionable remediation.

## Logging Requirements
1. Every command gets request id and duration.
2. Critical workflows log start, success, failure, and retry events.
3. Sensitive data is redacted by default.
4. Log retention stays local and rolling.

## Prohibited Shortcuts
1. Hardcoding forge-specific behavior in core Git services.
2. Writing plaintext credentials into settings or logs.
3. Large unreviewed refactors during feature delivery.
4. Unbounded list rendering in UI paths.

## Completion Criteria for First Build Wave
1. App opens repository and shows status correctly.
2. Stage/unstage and commit are reliable.
3. Diff opens with Pretext DOM path and telemetry.
4. Auth diagnostics surface useful guidance.
5. Foundation is ready for canvas mode and AI extensions.
