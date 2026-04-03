# Fixtures

This directory stores reproducible test fixtures used by CI and local validation.

## Layout
- `repos/`: repository scenario fixtures and notes.
- `diffs/`: diff-specific fixture corpora (unicode, bidi, long-line, and mixed script cases).
- `auth/`: authentication and remote-URL diagnostic fixture notes.

## Current Coverage
- Git operation compatibility fixtures are implemented in Rust tests under:
  - `apps/desktop/src-tauri/src/services/git_provider/mod.rs`
- These tests build repositories on the fly and compare provider results to direct Git CLI output.

## CI Integration
- Git fixture tests run in `.github/workflows/desktop-ci.yml` via:
  - `cargo test fixture_ -- --nocapture`

## Next Fixture Additions
- Add static repository snapshots under `repos/` for cross-version reproducibility.
- Add diff corpora under `diffs/` for renderer correctness and performance baselines.
- Add remote/auth protocol matrix under `auth/` to validate diagnostics guidance.
