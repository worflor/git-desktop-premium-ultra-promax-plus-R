# Pretext Version Bump Checklist

## Goal
Upgrade Pretext-related layout behavior safely with deterministic correctness and performance gates.

## Required Inputs
- Proposed version or adapter revision ID
- Changelog summary and known breaking behaviors
- Rollback target (previous pinned revision)

## Pre-Change Checklist
1. Document the proposal in the active sprint notes and link this checklist.
2. Confirm current baseline passes:
- `npm run pretext:fixtures --workspace apps/desktop`
- `npm run pretext:canary --workspace apps/desktop`
- `cargo test perf_budget_ -- --nocapture`
3. Capture baseline metrics from canary and backend perf tests.

## Change Checklist
1. Apply version/revision update.
2. Re-run fixture and canary gates locally.
3. Re-run backend performance budget gate.
4. Validate fallback telemetry fields remain populated in diff manifest payloads.

## Acceptance Criteria
1. Fixture gate passes for unicode, bidi, long-line, massive payload, mixed line endings.
2. Canary benchmark passes configured p95 budgets.
3. Backend perf budget tests pass configured thresholds.
4. No increase in fallback activation for non-forced normal fixtures.
5. Command contract docs remain accurate after the upgrade.

## Rollback Procedure
1. Revert to previous version/revision.
2. Re-run full gate suite.
3. File a regression issue with fixture/canary evidence and stack traces.

## Required Artifacts
- Before/after metric summary
- Gate command outputs
- Linked follow-up issues (if any)
