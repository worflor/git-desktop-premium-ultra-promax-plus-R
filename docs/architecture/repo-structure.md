# Repository Structure (Pre-Build Spec)

## Purpose
Define the implementation structure before coding so AI agents can add files predictably without architectural drift.

## Monorepo Layout

```text
/
  apps/
    desktop/
      src/
        app/
          layout/
          routing/
          providers/
        features/
          repositories/
          changes/
          diff/
          history/
          sync/
          ai/
          settings/
        components/
          primitives/
          composite/
          icons/
        styles/
          tokens.css
          globals.css
          motion.css
        lib/
          telemetry/
          formatting/
          validation/
          capability/
        state/
        workers/
      src-tauri/
        src/
          main.rs
          commands/
          services/
            git_provider/
            forge_provider/
            auth/
            diff/
            ai/
            settings/
          models/
          errors/
          telemetry/
          runtime/
        Cargo.toml
      package.json
      tsconfig.json
      vite.config.ts
  crates/
    shared-models/
    shared-telemetry/
  fixtures/
    repos/
    diffs/
    auth/
  scripts/
    dev/
    ci/
    benchmark/
  docs/
```

## Principles
1. Keep UI feature code under feature boundaries, not by file type alone.
2. Keep Tauri command handlers thin; move behavior into Rust services.
3. Keep shared DTO and error models centralized in Rust models/errors.
4. Keep provider abstractions isolated so optional adapters do not leak into core flows.
5. Keep fixture data under top-level fixtures for CI and reproducibility.

## Rust Service Layer Boundaries
- git_provider: system Git command execution, parsing, normalization.
- forge_provider: optional host adapters and capability matrix.
- auth: helper and SSH diagnostics, readiness reporting.
- diff: patch metadata/chunking and renderer payload shaping.
- ai: provider discovery, job process control, incremental output capture, audit events.
- telemetry: structured events, performance spans, local retention manager.

## Frontend Feature Boundaries
- repositories: open/switch/recents.
- changes: status list, stage/unstage, commit composer.
- diff: pretext adapter, render mode orchestration, search and navigation.
- history: commit list and details.
- sync: fetch/pull/push state and diagnostics.
- ai: provider health, read-only actions, job output polling.
- settings: themes, panels, keybindings, guardrail slider.

## File Naming Conventions
- UI component files: PascalCase.
- Hooks and utilities: camelCase.
- Rust modules: snake_case.
- Command handlers: keep verb_noun function naming (for example `get_repository_status`), and group handlers either in `commands/mod.rs` or domain-specific modules depending on slice size.

## Dependency Direction Rules
1. primitives -> composite -> features -> app.
2. features cannot import from other features' internal folders.
3. command handlers cannot call shell commands directly; they must go through service layer.
4. forge adapters cannot be required by core Git workflows.

## Placeholders to Create Early
- icon registry and animated icon slots.
- telemetry event catalog and log schemas.
- capability matrix model (git, auth, forge, ai providers).
- render mode switch abstraction (dom/canvas/fallback).
