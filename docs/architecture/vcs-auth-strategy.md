# VCS and Auth Strategy

## Goal
Keep core Git workflows platform agnostic across GitHub, GitLab, Bitbucket, and self-hosted remotes while minimizing auth friction.

## Primary Decision
1. Core Git engine uses system Git CLI as the default provider.
2. Forge-specific capabilities are implemented through optional adapters.
3. Optional git2 acceleration is allowed only for targeted read-heavy paths after profiling.
4. Minimum supported Git version is 2.39+.
5. gh CLI is optional and used only for GitHub-specific enhancements.

## Why System Git First
- Maximum compatibility with real repositories and edge-case behavior.
- Reuses mature credential helpers and SSH agent flows users already trust.
- Avoids coupling core workflows to a single forge or API.

## Provider Model
### GitProvider (required)
Responsibilities:
- status, add/reset, commit, branch, checkout, merge/rebase helpers
- fetch, pull, push
- stash and log operations

Implementation:
- command execution wrapper around system Git
- structured parsing + normalized error mapping

### ForgeProvider (optional)
Responsibilities:
- PR links, checks metadata, issue/review deep links
- host-specific convenience actions

Implementations:
- github adapter (uses gh CLI only for optional GitHub-specific enhancements)
- gitlab adapter (API/token path later)
- bitbucket adapter (API/token path later)
- generic fallback (remote URL parsing only)

### AuthProvider (required)
Responsibilities:
- detect auth readiness for fetch/pull/push
- expose actionable diagnostics

Behavior:
- prefers system Git credential helper + SSH agent
- reads host adapter auth state when available
- never stores plaintext credentials in app state

## Capability Detection
At startup and in diagnostics:
1. Detect system Git availability and version.
2. Resolve Git executable path when possible (`where`/`which`) for diagnostics transparency.
3. Detect credential helper/SSH readiness.
4. Detect optional forge CLIs and auth status.
5. Publish capability matrix to UI.

## Failure and Fallback
- If forge adapter is unavailable, core Git remains fully functional.
- If host auth metadata cannot be fetched, show fallback actions using remote URLs.
- If Git command fails, return structured error codes and remediation hints.

## Security Posture
- Prefer delegated auth to OS tools and host CLIs.
- Store only non-secret metadata in app settings.
- Keep sensitive command output redaction in logs by default.

## Optional git2 Usage Policy
Allowed only when all are true:
- profiler shows meaningful gain on targeted operation
- behavior parity tests pass against system Git fixtures
- fallback to system Git exists for that operation

Non-goal:
- replacing the default GitProvider with git2 in V1.
