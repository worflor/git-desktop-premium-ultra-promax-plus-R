# Wiring Redundancy Audit — 2026-06-19

Six read-only subagents swept the app's *logistical wiring* (not the engine math —
that's profiled-tight) for redundant work, duplicate computation, over-invalidated
caches, and wasted allocation. Every fix below is **same-output / bit-identical** —
no capability is changed. Several findings **cross-validated** (independent agents
converged), marked ⊗.

## Shipped this pass (validated bit-identical)
- **`logos_chunks` `symNumerator` flattened** (`logos_chunks.dart:341`) — was the nested
  `Map<int,Map<int,int>>` regression the hunk twin already fixed; now `Map<(int,int),int>`,
  zero auxiliary allocs per chunk-graph build. Bit-identical (each canonical pair counted
  once → `addEdge` order irrelevant). `dart analyze` clean.
- **`_classifyHunkTag` regexes hoisted** (`diff_logos_facade.dart:2021`) — 9 compile-time-constant
  `RegExp` were recompiled per hunk × (snapshot + per-file-context passes); now module-level
  `final`. Same patterns/flags → identical classification.

## Tier 1 — cross-validated / highest-leverage (not yet shipped)
1. ⊗ **Double `git rev-parse HEAD` per cold resolve** — `logos_git_resolver.dart:442`
   (`runGitProbe`) + `_resolveShadowCoupling:612` (raw `Process.run`, bypasses the in-flight
   dedup), both inside the same `Future.wait`. Fix: thread the already-read `hash` into
   `_resolveShadowCoupling` (it only uses it for a freshness compare). Same HEAD, one fewer spawn.
2. ⊗ **`_recomputeFileDimOpacity` — uncached O(n²) coupling-centrality on *every* changes
   `build()`** (`changes_page.dart:6039`, body `:2071`). `combinedCouplingScore` per pair, no
   memo; fires per AI-notify / dream-hint / hover-propagation. Fix: single-slot memo on
   `identical(engine)·identical(coupling)·same status path-set` (the triad already used at
   `:6204`/`:1331`). Output map byte-identical. **Biggest UI win.**
3. ⊗ **`effectiveMatrix`/`logosEngine` get fresh identities every frame**, defeating the
   `identical()`-keyed `_clustersFor` cache → O(n²) `clusterFiles` *per frame* when spectral
   coupling is warm (`changes_page.dart:6074-6093` producers, `:1644` cache). `withSpectral`/
   `withSpectralEdges` always allocate. Fix: memoize the wrappers keyed on their stable inputs
   (the basis/spectral caches are already shared, so reuse is safe). Worse than the known
   `_includedPaths` exemplar — fires every frame, not just on toggle.
4. **Double 1000-commit `git log` walk across state owners** (`file_coupling_state.dart:15`
   + `logos_git_stats.dart:68`) — every `resolveLogosGit(repoPath)` caller that does NOT thread
   `coupling:` (branches_page, palette, settings, ipc, most `ai.dart` paths) re-walks the same
   1000 commits `FileCouplingState` is walking (~1086ms, measured). `changes_page.dart:5808`
   does it right (threads the matrix); the others don't. Fix: thread `coupling:` everywhere.

## Tier 2 — high-confidence, clearly bit-identical
- **Commit list sorted twice with the identical comparator** — `commit_tagger.dart:827` builds
  `chronological..sort(cmp)`, then `_computeBorrowedLabels:1515` rebuilds the identical sort
  (O(n log n) `DateTime.parse` ×2). Pass the sorted list down. conf 0.95.
- **`coherenceFor` recomputed 3× / `parseSubjectPrefix` 3-4× per commit** —
  `commit_tagger.dart:785/1055/1290` and `:743/1063/1158/1894`. Per-commit memo. conf 0.85-0.9.
- **Command-telemetry write-amplification** — `command_telemetry_store.recordSample` loads the
  full `.jsonl`, double-encodes (measure + write), and rewrites the whole file on *every backend
  command*; `diagnostics_state.dart:626` ALSO persists an overlapping store. Fix: append-only +
  dirty-gate. conf 0.85-0.9. **Largest avoidable disk churn.**
- **Settings re-encoded + `flush:true` fsync'd per drag frame** — `settings_store.persist` has no
  dirty-gate; `setLogosPad` is on the pad's drag `onChanged`. Fix: equality-gate `persist`
  (give `AppSettingsSnapshot` value `==`). conf 0.85. Most latency-visible (interactive gesture).
- **`AI audit O(n²) re-encode` in retention** (`ai_audit_store.dart:145`) — re-serializes the
  whole list per dropped entry; + unconditional rewrite on every read. Running-total trim +
  dirty-gate. conf 0.9.

## Tier 3 — solid, lower-leverage (the tail)
- BlobLoader runs `cat-file -s` then `cat-file blob` per blob → one `cat-file --batch`
  (`blob_loader.dart:89`). `desk_pr_diff` runs `--numstat` then full patch → `--numstat --patch`
  (`desk_pr_diff.dart:35`). conf 0.8.
- Manifold pane rebuilds the full 3D scene every breath frame (60fps) + per hover
  (`manifold_pane.dart:1643/2164`) → memoize `_ChartData` keyed on `line.fastKey`. conf 0.9.
- Branches `_PrExpanded.build` runs uncached `clusterFiles` + heat-kernel diffusion per PR-row
  build / per PR-search keystroke (`branches_page.dart:6886`). conf 0.9.
- Command palette re-scores + re-sorts the whole candidate list synchronously, undebounced, per
  keystroke (+ spectral witness field every keystroke) (`palette_state.dart:247`). Frame-coalesce
  the in-memory rescore. conf 0.9.
- `clusterFiles` builds `.values.toList()..sort()` just to read median+max (`file_coupling.dart:1549/1592`)
  → quickselect/linear-max. `topKSymmetriseEdges` sorts rows even when `row.length≤topK`
  (`top_k_symmetrise.dart:49`) → skip-when-small. `phiByKey` rebuilt twice
  (`correlatedness_hunk_sort.dart:71` + `file_coupling.dart:1718`). conf 0.65-0.85.
- IPC frame double header-parse + extra payload copy (`pipe_protocol.dart:55`); `_resolveScope`
  repeated `where().firstOrNull` per path (`pipe_commands.dart:1040`) → index map. conf 0.75-0.8.
- History `TextPainter.layout()` per tag-pill per row (`history_page.dart:2764`) + `_TimelinePainter`
  full repaint on any setState (`:380/979`); Settings 27 `TextPainter` premeasure unmemoized
  (`settings_page.dart:11997`); workspace `_DeskRow` double state-lookup per comparator
  (`workspace_shell.dart:1198`); `sidebar_rail.dart:2330` RegExp per build. conf 0.7-1.0.
- `_engramSignal` pre-gate: skip the curvature dot when `k < τ²` (τ²≈0.135) — **must be τ², not τ**
  (`logos_hunks.dart:725`). conf 0.7.

## Confirmed already-fixed (the reference pattern)
Resolver dirty-gate (`:218`), filter-before-stat (`:156`), HEAD-cache dedup, blob-walk
consolidation, CSR-native coupling, the `LogosTransportLane` strength path, `dtos`
`==`/`hashCode`. These are the shapes the Tier 1-3 fixes should copy.

**No-nerf discipline:** every fix yields the same value/bytes/UI — memoize, dedup, merge,
reuse, skip-when-unused, tighter cache key. Flagged FP-order/tie-break risks (the coupling
cross-matrix re-sum, the `τ²` gate) must reuse the accumulated value, not re-derive in a new order.
