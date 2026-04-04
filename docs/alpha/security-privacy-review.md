# Alpha Security and Privacy Review

## Scope
This document captures the current alpha security posture and privacy behavior for desktop workflows.

## Data Residency and Storage
Default storage root:
- Windows: %APPDATA%/gdpu
- macOS: $HOME/Library/Application Support/gdpu
- Linux: $XDG_DATA_HOME/gdpu or $HOME/.local/share/gdpu
- Override: GDPU_DATA_DIR

Local app files:
- settings.json
- command_telemetry.jsonl
- operation_events.jsonl
- ai_review_audit.jsonl
- crash-reports/* (only when crash reporting is enabled)

Repository-local artifacts:
- .git/gdpu/local_issues.json
- .git/gdpu/local_pull_requests.json

## Network Boundaries
Expected outbound requests are limited to:
- Git remotes for fetch/pull/push workflows.
- Optional forge API calls for GitLab/Bitbucket issue and pull request workflows.
- Optional updater endpoint checks and update artifact downloads.

No automatic telemetry export is implemented in alpha.
Command and operation telemetry are local-only diagnostic artifacts.

## Credentials and Secret Handling
Credentials are not persisted by the app when avoidable.
Primary auth model:
- Core Git auth uses system credential helpers and existing remote setup.
- Forge API adapters read tokens/credentials from environment variables.
- Updater runtime can read public key and endpoint overrides from environment variables.

Required handling rules:
- Never commit secrets or endpoint credentials into repository files.
- Prefer process/session scoped environment variables for testing.
- Rotate tokens immediately after accidental disclosure.

## AI Privacy Posture
AI provider execution is local CLI based.
- Prompts and diff excerpts are passed to user-installed local provider CLIs.
- Provider output metadata is audited locally in ai_review_audit.jsonl.
- Audit persistence uses redaction/truncation safeguards.
- Read-only guardrail mode is enabled by default.

## Crash Reporting Posture
Crash artifacts are local files only.
- Disabled by default.
- No remote crash upload in alpha.
- Enable only when local diagnostics are needed.

## Threat Model Notes (Alpha)
Primary risks:
- Misconfigured environment variables exposing tokens in shared shells.
- Over-broad prompt content sent to external AI providers through local CLIs.
- Update endpoint misconfiguration leading to failed update checks.

Current mitigations:
- Explicit adapter availability diagnostics with guidance messages.
- Read-only AI guardrail default and write-intent prompt blocking.
- Updater endpoint and pubkey validation errors surfaced in command output.

## Residual Risks and Follow-ups
- Formal secret-scanning for local logs is not yet integrated.
- Installer rollback verification is still operationally validated, not automatically tested.
- Security review should be repeated before beta launch with dependency and permission audit.
