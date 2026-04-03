# Sprint 0 Plan (2 Weeks)

## Sprint Goal
Stand up the app skeleton and complete one end-to-end status and commit workflow slice with instrumentation.

## Scope
- Scaffold Tauri + Solid + TypeScript app
- Define Rust command envelope and first DTOs
- Implement system Git capability detection and version checks
- Implement auth diagnostics baseline (SSH and credential helper readiness)
- Implement repository open + recents
- Implement status read path
- Implement stage/unstage + commit panel
- Implement Pretext layout adapter skeleton in diff domain
- Add command timing instrumentation

## Day-by-Day Plan
1. Project scaffold and toolchain lock
2. Command contract and error envelope implementation
3. System Git capability and auth diagnostics wiring
4. Repository open flow and recent storage
5. Status service minimal command
6. Pretext adapter scaffolding and layout cache model
7. Stage/unstage actions
8. Commit validation and execution
9. Diff open wiring with Pretext layout plumbing (baseline)
10. Instrumentation, smoke testing, and bug fixes

## Deliverables
- Runnable desktop app skeleton
- First working user flow:
  - open repo
  - inspect changed files
  - stage/unstage
  - commit
- Pretext adapter integrated in baseline diff path
- Basic timings emitted for major commands

## Risks This Sprint
- Rust/Tauri command glue friction
- Git edge cases in staging behavior
- UI state race conditions after write operations

## Mitigation
- Keep DTOs small and explicit
- Add refresh-after-write consistency checks
- Keep manual smoke test script and run daily

## Demo Script (End of Sprint)
1. Open real repository
2. Show branch and changed files
3. Stage one file and unstage another
4. Commit with valid message
5. Open file diff and scroll through content
