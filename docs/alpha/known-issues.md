# Alpha Known Issues

This list is intentionally explicit for external alpha users and internal triage.

## Update Path Configuration Required
Impact: Medium

Symptoms:
- Check for Updates fails with updater configuration errors.

Cause:
- No update endpoint or public key is configured for the updater runtime.

Workaround:
- Configure one of the endpoint environment variables:
  - GDPU_UPDATER_ENDPOINTS_STABLE or GDPU_UPDATER_ENDPOINT_STABLE
  - GDPU_UPDATER_ENDPOINTS_BETA or GDPU_UPDATER_ENDPOINT_BETA
  - GDPU_UPDATER_ENDPOINTS or GDPU_UPDATER_ENDPOINT
- Configure GDPU_UPDATER_PUBKEY when not embedded in app updater config.

## Windows Installer Exit Behavior
Impact: Low

Symptoms:
- App appears to close during update install.

Cause:
- Windows updater flow exits the app before installer execution.

Workaround:
- Relaunch the app after installation completes.

## AI Provider CLI Variability
Impact: Medium

Symptoms:
- AI review responses differ by provider and CLI version.
- Some provider attempts produce no output and fallback summary is used.

Cause:
- Local AI CLIs expose heterogeneous argument contracts.

Workaround:
- Verify provider binary is detected in Settings diagnostics.
- Keep provider CLI updated.
- Use fallback review output as a deterministic baseline.

## Forge API Credentials Not Found
Impact: Medium

Symptoms:
- GitLab or Bitbucket issue/PR operations report unavailable adapter or auth guidance.

Cause:
- Required token or credential environment variables are not set.

Workaround:
- GitLab: set GDPU_GITLAB_TOKEN or GITLAB_TOKEN.
- Bitbucket: set GDPU_BITBUCKET_TOKEN or BITBUCKET_TOKEN.
- Bitbucket alternative auth: set GDPU_BITBUCKET_USERNAME and GDPU_BITBUCKET_APP_PASSWORD.

## Large Diff Review Degradation
Impact: Low

Symptoms:
- AI review output references truncated diff input.

Cause:
- Review adapters enforce bounded payload sizes to protect runtime stability.

Workaround:
- Review a narrower scope path when possible.
- Split large changes into smaller commits for review quality.

## Reporting Instructions
When opening an issue, include:
- app version
- OS + architecture
- selected update channel
- command error code and message
- reproduction steps and expected result
