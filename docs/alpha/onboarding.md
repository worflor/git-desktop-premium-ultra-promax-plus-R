# Alpha Onboarding Guide

## Goal
This guide gets a first-time alpha tester from install to a validated working setup in under 15 minutes.

## Prerequisites
- Operating system: Windows, macOS, or Linux.
- Git 2.39 or newer is installed and available on PATH.
- At least one repository is available locally.
- Optional AI CLIs for review workflows: Codex, Claude, Gemini, or OpenCode.

## First-Run Checklist
1. Launch the desktop app and open a known local repository.
2. Confirm startup diagnostics:
- Open Settings and verify startup readiness checks are green.
- If a check is degraded, capture the error code and continue with core Git workflows.
3. Validate core Git loop:
- Refresh repository status.
- Stage and unstage at least one file.
- Create a test commit on a throwaway branch.
4. Validate optional integrations:
- Run AI provider listing and verify at least one provider is detected (if installed).
- Run issue and pull request provider listing for your active remote.
5. Configure release channel and update path:
- Open Settings -> Release Channel.
- Select Stable or Beta.
- Run Check for Updates once to confirm updater configuration is valid.

## Update Configuration
Runtime update configuration can be provided with environment variables.

Channel-aware endpoint variables (first non-empty value is used):
- Stable: GDPU_UPDATER_ENDPOINTS_STABLE, GDPU_UPDATER_ENDPOINT_STABLE
- Beta: GDPU_UPDATER_ENDPOINTS_BETA, GDPU_UPDATER_ENDPOINT_BETA
- Shared fallback: GDPU_UPDATER_ENDPOINTS, GDPU_UPDATER_ENDPOINT

Endpoint value format:
- Single URL or multiple URLs separated by comma, semicolon, or newline.
- Example: https://updates.example.com/stable/{{target}}/{{arch}}/{{current_version}}

Optional runtime public key override:
- GDPU_UPDATER_PUBKEY

## Diagnostic Capture for Bug Reports
When reporting issues, include:
- App version and selected update channel.
- Operating system and architecture.
- Exact action sequence.
- Command error code and message.
- Whether the issue reproduces after app restart.

## Exit Criteria for a Successful Onboarding
- Repository opens successfully.
- Core stage/commit/status operations complete without data-loss behavior.
- Update check command returns a valid result (update available or no update).
- Tester can identify where to report feedback and known limitations.
