# Bootstrap Checklist

## Goal
Stand up the implementation foundation while preserving the architecture choices in this docs set.

## Checklist
1. Initialize Tauri + Solid + TypeScript project skeleton.
2. Configure Rust workspace with core service modules.
3. Define shared command DTOs and error envelope types.
4. Implement system Git capability detection and auth diagnostics baseline.
5. Create first vertical slice: open repo -> read status -> render list.
6. Add baseline instrumentation for command timing.
7. Add CI pipeline for build/test/lint on Windows first.
8. Add fixture repos for smoke and performance tests.
9. Document keyboard shortcuts and UX principles in app docs.

## Immediate Next Actions
- Pick the app codename and package IDs.
- Lock toolchain versions (Node, pnpm/npm, Rust, Tauri CLI).
- Define minimum supported Git version and capability checks.
- Create the initial scaffold and commit it as "chore: bootstrap workspace".
- Implement status path end-to-end before touching advanced Git features.

## First Demo Definition
A successful first demo can:
- Open a local repository
- Show changed files and branch name
- Stage/unstage a file
- Commit with message validation
- Open a file diff and scroll smoothly
