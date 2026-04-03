# Pretext Evaluation for Large Diff Rendering

## Purpose
Validate implementation considerations for a committed Pretext-first diff renderer.

## Research Date
2026-04-03

## Sources Reviewed
- https://github.com/chenglou/pretext
- https://raw.githubusercontent.com/chenglou/pretext/main/README.md
- https://raw.githubusercontent.com/chenglou/pretext/main/STATUS.md
- https://www.npmjs.com/package/@chenglou/pretext
- https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/measureText
- https://codemirror.net/examples/million/
- https://codemirror.net/
- https://microsoft.github.io/monaco-editor/

## Decision
Use Pretext as the core line-layout engine for diff rendering in V1.

Renderer surfaces:
- Virtualized DOM for small and medium diffs
- Canvas for large diffs

Both surfaces consume the same Pretext-derived line mapping.

## What Pretext Provides That Matches Our Needs
- DOM-free measurement and layout pipeline suited to text-heavy UIs.
- Prepare-once, layout-many model that maps to diff open, resize, and scroll flows.
- APIs for line-level output and cursor mapping that can unify navigation and hunk alignment.

## Maturity Reality and Handling Strategy
Observed facts:
- Active repository and package publication exist.
- Current package version is early.
- Upstream already documents caveats and benchmark/accuracy snapshots.

Execution stance:
- We are adopting Pretext now.
- We will control risk through version pinning, fixture testing, telemetry, and upgrade gates.

## Technical Caveats We Must Engineer Around
From upstream behavior notes:
- Not a full browser text engine replacement.
- Wrapping behavior assumptions matter.
- Font configuration consistency is required for predictable results.

Implementation implications:
- Use explicit named monospaced fonts in diff surfaces.
- Normalize line-height and font profile at renderer boundaries.
- Validate unicode and bidi behavior with dedicated fixtures.

## Comparison Context
CodeMirror and Monaco remain useful reference baselines for huge-document ergonomics.
This project still uses a custom renderer strategy because product goals prioritize:
- tight Rust command integration,
- renderer mode control,
- and AI-augmented diff workflows tuned to this app.

## Required Engineering Controls
1. Pin Pretext version and lock upgrade policy.
2. Add fixture suites for unicode, bidi, long-line, and mixed script diffs.
3. Track Pretext prepare and layout timings independently.
4. Keep emergency fallback renderer path for runtime resilience.
5. Add canary benchmark checks to CI before Pretext version changes.

## Success Criteria
- Pretext layout correctness passes fixture corpus on target OS browsers/webviews.
- p95 diff first paint and scrolling budgets are met in both renderer modes.
- Renderer mode switching does not change logical line mapping.
- Fallback activation remains rare and diagnosable.

## Immediate Follow-Up Tasks
- Implement Pretext layout adapter interface in UI layer.
- Add renderer integration tests using same diff corpus for DOM and canvas modes.
- Build a diagnostics panel section that reports Pretext version and layout health.
