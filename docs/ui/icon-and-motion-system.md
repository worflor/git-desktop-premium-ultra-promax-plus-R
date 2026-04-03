# Icon and Motion System (Handmade SVG Plan)

## Goal
Use custom handmade SVG icons with an animation-ready architecture that scales without visual inconsistency.

## Icon Strategy
1. Build first-party icon set for app identity and key Git concepts.
2. Use SVG source files as canonical assets.
3. Generate component wrappers from SVG with a shared API.

## Directory Plan

```text
apps/desktop/src/components/icons/
  raw/
    app/
    git/
    ai/
    status/
  animated/
    app/
    git/
    ai/
    status/
  registry/
    iconRegistry.ts
    animatedIconRegistry.ts
  Icon.tsx
  AnimatedIcon.tsx
```

## Core Icon Categories
- app: logo mark, navigation, settings, diagnostics.
- git: branch, commit, merge, rebase, stash, tag, remote.
- status: added, modified, deleted, conflicted, staged, pending.
- ai: provider-neutral action icons and stream states.

## Standard SVG Rules
1. Use 16 and 20 pixel grids as primary targets.
2. Keep stroke weight consistent per size bucket.
3. Prefer rounded joins for compact legibility.
4. Use currentColor where possible.
5. Avoid embedded text in icons.

## Animation Rules
1. Keep animations meaningful, not decorative noise.
2. Animate only state transitions and active processes.
3. Provide reduced-motion fallback.
4. Keep default animation duration in 120 to 240ms range for micro transitions.

## Initial Animated States
- sync-running: subtle rotational or sweep motion.
- ai-streaming: pulse waveform or flowing indicator.
- conflict-alert: controlled pulse/outline emphasis.
- success-complete: short check reveal.

## Placeholder API Contract

Static icon props:
- name
- size
- tone
- title

Animated icon props:
- name
- state
- intensity
- loop
- reducedMotion

## Implementation Readiness Checklist
1. Icon registry supports lazy loading.
2. Animated and static variants share naming conventions.
3. Theme tokens control icon color semantics.
4. Status icons map to Git state classes consistently.
5. Snapshot tests guard icon rendering regressions.

## Custom Identity Guardrail
- Do not copy external brand icons directly.
- Keep structural inspiration from T3 patterns, but maintain unique visual language.
