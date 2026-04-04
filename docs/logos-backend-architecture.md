# Logos-Inspired Backend Architecture

This document translates the best ideas from the Whisper codecs into a backend architecture for the desktop app. It does not change visuals or product behavior. It changes how the backend thinks, caches, schedules, and invalidates read work so the app feels static and immediate.

## Goal

The app should behave like a good desktop program:

- visible state does not flap because a fetch started
- immutable data returns from memory whenever possible
- semi-stable data reuses recent snapshots instead of re-probing
- expensive work runs only when there is strong evidence it will help
- multiple services do not independently rediscover the same repository facts

## What To Borrow From The Codecs

### Logos

`logos.wat` is useful because it is not just "compression math". It is a systems design:

- multiple weak predictors instead of one absolute source of truth
- confidence-weighted blending instead of naive equal treatment
- exact-match short-circuit paths
- cheap root priors when specialized contexts are cold
- regime-aware behavior: gas, volatile, crystal
- lazy lookup tables and bounded evidence
- bypass of expensive paths on near-random input

Backend translation:

- predict likely next reads from several signals
- weight speculative work by confidence and cost
- keep exact immutable payloads on a direct memory path
- maintain a cheap root snapshot for each repository
- classify backend state into stable and volatile regimes
- lazily materialize expensive derived views
- skip speculative work when user behavior is noisy

### Glyph

`live-wasm-glyph.ts` adds two ideas that matter a lot for app architecture:

- trial-gated sidecars: auxiliary prediction paths only run if they reduce total cost
- headers-first wire format: cheap structural metadata comes first, heavy payload comes later

Backend translation:

- prefetch should be trial-gated, not unconditional
- every expensive read should have a cheap "header" path before the deep payload
- commands should return enough metadata for the frontend to remain static before heavy detail is needed

### Lumen

`lumen.wat` is valuable for fused passes:

- multiple logical stages fused into one memory pass
- fewer temporary buffers
- fewer cache-miss traversals

Backend translation:

- combine git probes that currently run separately when they target the same repository state
- compute several read-model outputs from one backend snapshot
- avoid parsing the same git output in multiple services

## Current Backend Shape

The current backend already has good local optimizations:

- immutable commit-detail cache in [commands/mod.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/commands/mod.rs)
- short-lived repository status and branch snapshot caches in [commands/mod.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/commands/mod.rs)
- process caches in [settings_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/settings_service.rs), [forge_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/forge_service.rs), and [pretext_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/pretext_service.rs)

The structural issue is that the backend is still command-shaped, not read-model-shaped.

Symptoms:

- caching policy lives partly in `commands/mod.rs`, partly in services, partly nowhere
- the same repository facts are re-derived by different services
- `remote -v` parsing is duplicated
- repository status, branch list, HEAD, upstream, sync state, and auth guidance are still too isolated
- command handlers are acting as mini query engines instead of delegating to one shared read plane

## Design Principle

Treat every backend read as a query against a repository-local prediction system.

Each repository gets a read plane with:

- a root snapshot
- exact immutable caches
- bounded short-lived stable caches
- volatile read guards
- in-flight dedupe
- prediction-driven warming
- mutation-triggered invalidation

This is the backend equivalent of Logos:

- `F0` root prior -> repository root snapshot
- `O2` exact prior -> exact-key immutable cache
- `Ab` spatial neighbor -> adjacent visible entity prefetch
- `M` exact match injection -> short-circuit exact hit path
- phase state -> cache TTL and invalidation strategy

## Proposed Architecture

### 1. Repository Read Plane

Add one service responsible for all repository read state:

- `RepositoryReadPlane`
- keyed by canonical repository path
- owns cache entries, freshness, in-flight requests, and invalidation counters

Suggested internal partitions:

- `root_snapshot`
- `commit_snapshot`
- `diff_snapshot`
- `remote_snapshot`
- `forge_snapshot`

This should move policy out of command handlers and into a shared backend layer.

### 2. Root Snapshot

The backend needs a cheap root prior for every repo. This is the `F0` equivalent.

The root snapshot should hold cheap, broadly reused facts:

- current HEAD hash
- current branch
- upstream ref
- ahead/behind counts
- conflict state
- worktree dirty bit
- last fetch time if available
- invalidation generation

Purpose:

- many commands can answer quickly from this before deciding whether deeper work is needed
- multiple services stop issuing independent `rev-parse`, `status`, `branch`, and conflict checks

### 3. Query Classes

Every read query should be classified before execution:

- `Immutable`
- `Stable`
- `Volatile`
- `Heavy`

Definitions:

- `Immutable`: commit detail for a specific hash, parsed patch chunks for a specific blob pair
- `Stable`: branch list, remotes, auth adapter matrix, recent sync summary
- `Volatile`: working tree status, staged/unstaged diffs, conflict progress
- `Heavy`: large diff preparation, layout prep, network-backed forge reads

This should drive:

- TTL
- invalidation rules
- prefetch eligibility
- whether stale data may be served while refresh happens

### 4. Exact-Hit Fast Path

This is the `M` axis equivalent.

If a query key is exact and immutable:

- return directly from cache
- do not route through generic freshness logic
- do not emit "loading-like" internal states to the frontend

Examples:

- `repo + commit_hash -> CommitDetailData`
- `repo + old_blob + new_blob + path -> parsed diff payload`

### 5. Spatial And Temporal Prediction

This is where the Logos inspiration becomes concrete.

Every query can be scored by signals:

- current route
- currently visible list window
- selected entity
- previous selected entity
- previous successful query keys
- adjacency in the visible UI
- repository regime

Useful backend analogies:

- temporal signals: recent commands for the repo
- spatial signals: adjacent commits, adjacent files, visible rows, current pane neighbors

Predicted next reads should be warmed in background only if confidence is high enough.

### 6. Trial-Gated Speculation

This comes from Glyph.

Prefetch is not free. It should be budgeted and accepted only when likely to reduce user-visible latency.

Each speculative candidate should be scored on:

- probability of use
- estimated cost
- cache class
- repository volatility

Simple policy:

- always warm cheap immutable neighbors
- warm stable metadata if reused by multiple surfaces
- avoid heavy speculative diff/layout work during volatile repository activity

### 7. Headers-First Reads

This also comes from Glyph.

Backend responses should be split into:

- structural header
- deep payload

Examples:

- commit header: hash, title, author, timestamp, counts
- diff header: changed lines, hunk map, renderer mode, chunk count
- remote header: remote names, host kinds, upstream summary

Then:

- the UI can stay mounted from previous state or cheap metadata
- deep payload can load lazily or be prefetched under budget

### 8. Fused Read Passes

This comes from Lumen.

The backend should stop treating every command as a separate git subprocess pipeline.

High-value fused passes:

- repository root pass:
  - current branch
  - upstream
  - ahead/behind
  - head hash
  - conflict markers
- remote topology pass:
  - `remote -v` parsed once
  - host kind
  - protocol
  - forge adapter eligibility
- branch/sync pass:
  - local branches
  - upstream refs
  - tracking state
  - publish-needed summary

If several UI surfaces need these, one parse should feed all of them.

## Concrete Backend Services To Introduce

### `repository_read_service`

Responsibilities:

- canonical repo key resolution
- root snapshot lifecycle
- query classification
- stale-while-refresh reads
- mutation invalidation
- speculative warming entry points

### `remote_topology_service`

Responsibilities:

- single source of truth for parsed remotes
- remote protocol classification
- host kind classification
- forge adapter compatibility
- auth guidance inputs

Current duplication to collapse:

- [auth_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/auth_service.rs)
- [forge_remote_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/forge_remote_service.rs)

### `repository_topology_service`

Responsibilities:

- branch list
- upstream map
- current branch
- sync target summary
- worktree metadata

This is a stable cache domain, not a command concern.

### `predictive_warm_service`

Responsibilities:

- receive frontend intent hints
- score next-likely backend reads
- run low-cost warming under budget
- suppress warming in volatile regimes

## Regime Model

Use a simple regime model per repository:

- `Crystal`
- `Volatile`
- `Gas`

Definitions:

- `Crystal`: immutable browsing, commit history navigation, read-heavy use
- `Volatile`: active stage/unstage, rebase, cherry-pick, conflict resolution
- `Gas`: noisy, low-repeat navigation or large random diffs where speculation is unlikely to help

Effects:

- `Crystal`: aggressive immutable neighbor warming, longer stable TTLs
- `Volatile`: short stable TTLs, no heavy speculation, eager invalidation
- `Gas`: bypass speculative warming, rely on root snapshot and exact hits

This is the same idea as Logos phase-aware behavior, applied to repo state instead of entropy state.

## Query Contract

Command handlers should shrink to:

1. parse input
2. call read plane or mutation plane
3. wrap result

Suggested internal query contract:

```rust
enum QueryClass {
    Immutable,
    Stable,
    Volatile,
    Heavy,
}

struct QueryPolicy {
    class: QueryClass,
    allow_stale: bool,
    ttl_ms: u64,
    prefetchable: bool,
}
```

Every shared query path should expose:

- `get()`
- `prime()`
- `invalidate()`
- `estimate_cost()`

## Current Hotspots Worth Refactoring Next

### Duplicate remote discovery

`remote -v` parsing exists in multiple places and should become a shared snapshot.

Relevant files:

- [auth_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/auth_service.rs)
- [forge_remote_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/forge_remote_service.rs)

### Command-layer cache policy

Cache logic in [commands/mod.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/commands/mod.rs) works, but it is in the wrong layer long term. It should move behind service boundaries so future commands inherit the same rules automatically.

### Repository topology fragmentation

`get_repository_status`, `list_branches`, sync commands, auth guidance, and forge detection are still too independent. They share input facts and should not probe separately.

### Diff preparation

[diff_service.rs](/C:/Users/mini%20server/Documents/Projects/git-desktop-premium-ultra-promax-plus-R/apps/desktop/src-tauri/src/services/diff_service.rs) already caches prepared payloads well, but it is still a single-command heavy path. The next step is better root/topology sharing plus trial-gated pre-layout warming for only the most likely next file.

## Rollout Plan

### Phase 1

Build the shared read plane without changing product behavior.

- introduce `repository_read_service`
- move status/branch/commit cache policy out of command handlers
- add in-flight dedupe per query key
- centralize invalidation generation per repository

### Phase 2

Unify remote and forge topology.

- add `remote_topology_service`
- remove duplicated `remote -v` parsing
- let auth, forge, local issues, and local pull requests consume one shared snapshot

### Phase 3

Add predictive warming.

- feed backend with visible commit/file windows
- warm immutable neighbors
- warm stable topology snapshots under idle budget
- suppress heavy speculation in volatile regimes

### Phase 4

Fuse repository read passes.

- build one root snapshot pass for head/upstream/ahead-behind/conflict
- build one topology pass for remotes and tracking
- let multiple commands read from these instead of shelling independently

### Phase 5

Instrument prediction quality.

- cache hit rate by query class
- in-flight dedupe hit rate
- speculative warm usefulness
- avoided git process count
- stale-served count
- user-visible miss latency

Without this, the architecture will drift back toward intuition-driven micro-optimizations.

## Rules For Future Backend Work

- do not clear good visible state because a read started
- do not let commands own long-term cache policy
- do not parse the same git fact in multiple services
- do not speculate on heavy work unless confidence is high
- do not invalidate everything when a narrow mutation happened
- do keep immutable data on a direct exact-hit path
- do prefer fused repository passes over repeated subprocesses
- do measure cache usefulness, not just command duration

## Bottom Line

The codec analogy is valid.

The right translation is not "put compression math in the app". The right translation is:

- multi-axis prediction
- confidence-weighted warming
- exact-hit short circuits
- regime-aware cache policy
- lazy derived computation
- fused passes over shared state
- headers-first payload design

That is the backend architecture that will make this desktop app feel consistently static and sharp, not just fast in one screen.
