# Implementation Decisions (Locked)

Date: 2026-04-03

This file captures explicit product and architecture decisions to reduce ambiguity for AI coding agents.

## Platform and Packaging
1. V1 target platforms: Windows + macOS + Linux.
2. Linux packaging priority: Flatpak first.
3. Update channels: Stable + Beta.

## Core Git and Auth
1. Core Git engine: system Git provider (platform agnostic).
2. Minimum supported Git version: 2.39+.
3. Protocol behavior default: auto-detect existing remote setup.
4. Auth UX: reuse system credentials and show diagnostics.
5. gh usage: optional, only for GitHub-specific enhancements.

## Forge Strategy
1. Forge adapters are optional and capability-driven.
2. V1 priority: GitHub adapter first.
3. Core Git workflows must remain fully functional without forge adapters.

## AI Provider Strategy
1. V1 provider detection scope: Codex, Claude, Gemini, OpenCode.
2. Base policy: read-only by default for AI actions.
3. Architecture must support future write/autonomous features.

## AI Guardrail Model
1. UX control: continuous slider in [0, 1].
2. Profile mapping: Loose, Balanced, Strict, Paranoid.
3. Default profile: Balanced.

## Telemetry and Logging
1. Telemetry is local-only by default.
2. Logging is first-class for debugging and agent-assisted diagnosis.
3. Retention policy uses rolling logs with configurable time and/or size cap.

## UI Interaction Policy
1. Density: single compact mode only.
2. Allowed customization: theme switching, panel resizing, panel rearranging.
3. No separate comfortable mode for v1.

## Design Borrowing Policy
1. T3 Code serves as baseline template for structure and interaction patterns.
2. We may borrow selected visual conventions, but maintain distinct product identity.

## Workflow Notes (Project Development)
1. User handles repository workflow strategy manually.
2. AI agents are expected to focus on implementation tasks and code quality.
