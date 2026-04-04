# Alpha Feedback Triage Cadence

## Purpose
Define a repeatable intake and prioritization loop for alpha feedback so regressions are addressed quickly and roadmap decisions are data-driven.

## Intake Channels
Primary:
- GitHub issues in the project repository

Required issue fields:
- environment (OS, architecture, app version)
- update channel (stable or beta)
- reproduction steps
- expected vs actual behavior
- command error code/message when available

## Severity Model
- P0: data loss, destructive workflow corruption, app unusable on launch
- P1: core workflow blocked, no practical workaround
- P2: degraded workflow with workaround available
- P3: polish, quality-of-life, non-blocking defects

## SLA Targets
- P0: acknowledge within 4 hours, mitigation plan same day
- P1: acknowledge within 1 business day, prioritize for next patch
- P2: acknowledge within 2 business days, triage into active backlog
- P3: acknowledge within 5 business days, batch for quality sprint

## Weekly Rhythm
- Monday: review new issues, classify severity, assign owner
- Wednesday: risk review, promote urgent regressions, de-scope low-value work
- Friday: publish status update and close resolved confirmations

## Triage States
- needs-repro
- confirmed
- in-progress
- blocked
- fixed-awaiting-verification
- closed

## Labels
Functional labels:
- area:git-core
- area:diff
- area:ai
- area:forge
- area:updater
- area:settings
- area:docs

Risk labels:
- risk:data-loss
- risk:security
- risk:privacy
- risk:performance

## Exit Criteria for Alpha Loop Readiness
- All P0/P1 issues have owners and explicit target milestones.
- Known issues doc is updated weekly.
- At least one patch cycle closes feedback from each major functional area.
