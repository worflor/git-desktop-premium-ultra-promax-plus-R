# Diff Rendering Architecture

## Objective
Render very large diffs smoothly while preserving correctness and usability.

## Design Principles
- Correctness first: line mapping, hunk boundaries, and copy semantics must be reliable.
- Scale by default: avoid DOM explosion and long main-thread blocks.
- Progressive complexity: start with robust baseline, then add specialized high-scale paths.
- Observability-driven: each renderer path must emit measurable performance data.
- One layout truth: Pretext-derived line layout must drive both DOM and canvas modes.

## Renderer Modes
### Mode A: Virtualized DOM + Pretext Layout (default)
Use for small and medium diffs.

Strengths:
- Fast to ship
- Native text selection and accessibility behaviors
- Easier search highlight and annotation rendering

### Mode B: Canvas Renderer + Pretext Layout (large diff path)
Use for very large diffs where DOM virtualization starts degrading.

Strengths:
- Predictable frame time
- Stable memory profile at high line counts
- Tight control over paint pipeline

Responsibilities:
- Draw line numbers, sign columns, and text runs
- Maintain viewport-to-line index map
- Provide copy-from-selection overlay strategy
- Use Pretext line ranges and cursor metadata for consistent mapping

### Mode C: Emergency Fallback Layout Path (non-default)
Only used if Pretext fails to initialize or returns invalid layout state.

Use cases:
- Runtime resilience and graceful degradation
- Diagnostics and bug isolation

## Mode Selection Heuristic
Initial heuristic (tunable):
- Mode A if changed lines < 15,000 and diff payload < 3 MB
- Mode B otherwise
- Mode C only on runtime failure or explicit diagnostics flag

## Data Pipeline
1. Rust `diff_service` computes file + hunk metadata.
2. Rust chunks large diff payloads for incremental transfer.
3. UI worker precomputes layout indices (line offsets, visual rows, folding state).
4. Renderer paints visible window plus overscan buffer.

Pretext integration notes:
- Pretext prepare phase runs once per diff payload slice and font profile.
- Pretext layout results are cached by diff id, width, and line-height profile.
- Width changes trigger layout recompute, not full diff parse.

## Interaction Model
Required interactions across all modes:
- Keyboard navigation by file/hunk/line
- Text selection and copy
- Search in visible file diff
- Jump-to-hunk and minimap synchronization

Mode-specific notes:
- Mode A uses native DOM semantics while respecting Pretext-derived row mapping.
- Mode B uses logical selection model with clipboard serialization and Pretext cursor mapping.
- Mode C preserves essential navigation and copy behavior with reduced fidelity.

## Performance Budgets
- First paint p95 for opened diff: <= 200ms
- Scroll frame budget: <= 16ms at 60 FPS (target <= 8ms on capable hardware)
- Main-thread long tasks > 100ms: zero in normal interaction

## Instrumentation
Track per open/scroll session:
- renderer_mode
- total_changed_lines
- payload_bytes
- first_paint_ms
- sustained_scroll_fps
- memory_estimate_mb

## Rollout Strategy
1. Ship Mode A with Pretext-driven layout and correctness tests.
2. Introduce Mode B at large-size thresholds using the same layout pipeline.
3. Keep Mode C as non-default safety net and monitor activation rates.

## Test Matrix
- Tiny: < 200 changed lines
- Medium: 200 to 5,000 lines
- Large: 5,000 to 50,000 lines
- Edge: long single lines, unicode/bidi, mixed line endings, binary-like patches
