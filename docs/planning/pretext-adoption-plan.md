# Pretext Adoption Plan (Committed)

## Goal
Ship a Pretext-first diff renderer that is fast, correct, and operationally maintainable.

## Scope
In scope:
- Pretext integration into diff layout pipeline
- Shared layout model for virtualized DOM and canvas modes
- Telemetry, fixtures, and upgrade governance

Out of scope:
- Building a full editor component replacement
- Rich inline markup engine beyond current diff needs

## Milestones
### P-1 Layout Adapter Foundation
Deliverables:
- Pretext adapter module with prepare and layout APIs
- Cache keys based on diff id, width, font profile, line-height
- Error envelope for layout failures

Exit criteria:
- Adapter returns deterministic line maps for test corpus

### P-2 DOM Surface Integration
Deliverables:
- Virtualized DOM reads Pretext line map
- Search and hunk navigation consume same mapping
- Selection behavior validated

Exit criteria:
- DOM mode correctness tests pass with fixtures

### P-3 Canvas Surface Integration
Deliverables:
- Canvas renderer uses same Pretext line/cursor mapping
- Copy serialization and line-number alignment validated
- Threshold switch from DOM to canvas enabled

Exit criteria:
- Canvas mode passes correctness and interaction tests

### P-4 Reliability and Governance
Deliverables:
- CI fixture suite for unicode, bidi, long lines
- Pretext prepare/layout telemetry in diagnostics
- Version bump checklist and canary benchmark pipeline

Exit criteria:
- Pretext upgrades are gated and repeatable

## Test Corpus Requirements
- Tiny diff, medium diff, massive diff
- Long unbroken lines
- Mixed scripts and bidi samples
- Mixed LF and CRLF line endings
- Real repository fixture from daily workflow

## Telemetry Requirements
Per diff session capture:
- pretext_version
- prepare_ms
- layout_ms
- renderer_mode
- changed_lines
- payload_bytes
- first_paint_ms
- scroll_fps
- fallback_activated

## Failure Handling
If Pretext prepare or layout fails:
1. Emit structured error with context.
2. Activate emergency fallback renderer.
3. Show non-blocking warning with diagnostics link.
4. Log issue payload fingerprint for triage.

## Ownership
- UI architecture: renderer + adapter integration
- Rust side: diff payload chunking and metadata integrity
- QA/perf: fixture maintenance and benchmark health checks
