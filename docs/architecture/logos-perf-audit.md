<!--
SPDX-FileCopyrightText: 2026 Woflo Labs
SPDX-License-Identifier: LicenseRef-WLCSL-1.0
See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.
-->

# Logos Engine Performance Audit — 2026-06-15

Pre-release performance audit of the Manifold git-logos attention engine. Two-round
multi-agent audit (Opus subagents) with an **empirical benchmark track**: real
`dart` wall-clock + RSS + per-phase timings, several findings validated **bit-for-bit
identical** (same engine output, faster). No engine source was modified — `lib/**`
was treated as read-only; the only write workshop is `experiments/logos_bench/`.

## TL;DR

The engine is **not algorithmically broken**. The live cold build is **near-linear**
(edge count `m ~ n^1.03`), HEAD-gated behind an LRU cache + isolate offload, and the
only true `O(n²)` in the engine proper is **dead/guarded code**. The wins are
**constant-factor**: redundant work, allocation churn, and redundant disk I/O — all
removable with **numerically-identical** changes. Nothing here requires nerfing the
math or adding tuning knobs.

The single highest-leverage item is **measured and bit-for-bit validated**:
eliminating a double `TransportRoles` materialization in coupling calibration is a
**2.14× speedup of a phase that is 40% of a large-repo build**, with provably
identical `CouplingConstants`.

## Method

- **Round 1** mapped + analyzed 9 subsystems but a transient *server-side* rate limit
  killed 7 maps + the entire benchmark track; only `file_coupling` survived.
- **Round 2** (throttled: fat audit agents, batches of 2, bench in its own lane)
  re-covered the 7 lost subsystems **and ran the empirical track end-to-end**.
- Every surviving finding passed a **default-to-overstated adversarial verifier**
  (re-derive the O(); is it already cached? actually hot? would the fix change
  output?). **10 of 20 round-2 findings were refuted** — mostly dead/test-only code.

### Important corrections discovered during the audit

1. **The engine subgraph is NOT Flutter-free** (an earlier scouting claim was wrong).
   `logos_git.dart → file_coupling.dart → correlatedness_hunk_sort.dart →
   logos_hunks.dart → engram_bootstrap.dart` pulls `package:flutter/services.dart`
   (`rootBundle`); the closure also reaches `diagnostics_state.dart` (foundation) and
   `shared_preferences`. The benchmark links under plain `dart` via a pure-Dart
   `experiments/logos_bench/flutter_stub/` providing only the referenced compile-time
   symbols (all platform methods throw if called). **`buildFromStats` never executes a
   stubbed method**, so the numbers are untainted.

2. **The engine is HEAD-SHA-gated, not change-set-gated.** Staging, unstaging, and
   working-tree edits do **not** move git HEAD, so they hit the resolver cache
   (`logos_git_resolver.dart:402-415`, `:448-462`) and **never rebuild the engine**.
   This *refutes* the scary "full rebuild on every file change" framing — the felt
   "refresh lag" is **disk I/O + UI re-clustering**, not engine rebuilds (see Tier 2).

## The measured profile

Cold `LogosGit.buildFromStats`, dart 3.11.4 (windows_x64), 7 trials/size, warmup
discarded. Synthetic large-repo stats with power-law commit fan-out (85% touch 1–4
files, 13% touch 5–20, 2% touch 40–200), jaccard top-50 capped per row.

| n (files) | median | p95 | RSS | scoreLoop | coupling-calibration | everything else |
|---:|---:|---:|---:|---:|---:|---:|
| 200    | 21.3 ms   | 67.9 ms   | 259 MB | 67.4% | 18.8% | 13.8% |
| 1 000  | 53.4 ms   | 163.6 ms  | 259 MB | 69.6% | 21.1% | 9.3% |
| 5 000  | 443.6 ms  | 485.0 ms  | 269 MB | 57.5% | 35.7% | 6.8% |
| 20 000 | 3 028 ms  | 3 123 ms  | 295 MB | 55.7% | 39.7% | 4.6% |

**Two phases are 95% of the n=20 000 build.** Work-item count is near-linear
(`pairsScored` 6 750 → 767 582 ≈ `n^1.03`; `transportCalls = 2·pairsScored`), but the
two hot phases run **steeper than edge count** at the large end (scoreLoop `~1.37`,
coupling-calibration `~1.47` over 5k→20k). So the superlinearity is **per-edge cost**
(allocation / cache-miss / GC pressure), **not** algorithmic edge blow-up. RSS grows
sublinearly (259 → 295 MB over 100× files): memory is not the bottleneck; CPU in two
phases is.

> Scale note: on a normal repo (hundreds of files) the whole build is tens of ms and
> dominated upstream by the `git log` subprocess. These wins matter at **large-monorepo
> scale** (5k–20k+ files), which is exactly the stated concern.

## Ranked findings

Severity × confidence, measured items first. Every optimization direction is
**numerically identical** (same scores/edges/spectra) unless explicitly flagged.

### Tier 1 — measured & bit-for-bit validated

**1. Double `TransportRoles` materialization in coupling calibration** — `logos_git_integrity.dart:492` · sev 4 · conf 0.88 · risk none
`calibrateCouplingConstants` is a free function taking only `List<String>` paths, so
it can't see the `transportRoles` list `buildFromStats` already built
(`logos_git.dart:2518-2519`). It re-runs `TransportRoles.of` (one lowercase+replaceAll,
one seedKey, ten `_looks*Like` pattern sweeps) for **every node in the same node set** —
duplicating work the build already optimized away once for the scoreLoop (the prior
TransportRoles fix).
- **Measured:** coupling-calibration is the 2nd-largest and fastest-growing phase
  (share 18.8% → 39.7%; ~1.2 s at n=20 000; large-end exponent ~1.47). Isolated kernel:
  the redundant rebuild loop alone is **74.2 ms** at n=20 000; threading the existing
  list in cuts the kernel **203.5 ms → 94.9 ms (2.14×)**, **bit-for-bit identical**
  across all 7 `CouplingConstants` fields at every size.
- **Fix:** add an optional `rolesByPath`/indexed-list param to
  `calibrateCouplingConstants`; `buildFromStats` passes the roles it built at `:2519`.
- **Bug-class:** make per-path normalization-computed-twice *unrepresentable* — hoist
  `TransportRoles` to one owned build artifact threaded to *every* consumer (calibrate,
  scoreLoop, transport lanes) so no call site receives a bare path list to re-derive from.

**2. scoreLoop per-node candidate-set allocation** — `logos_git.dart:2640-2711` · sev 3 · risk none
The per-node `Set<int>` candidate assembly allocates a fresh hash-set per node + per-element
hashing + rehash-on-grow.
- **Measured + validated:** replacing it with a reused `Int32List` membership-epoch buffer
  is **1.5–1.7× faster** on the assembly portion at n≥5000, **bit-for-bit identical**
  candidate id lists (membership *and* insertion order) across all 26 200 nodes.
- **Honest scope caveat:** candidate assembly is only **~5–7% of scoreLoop**. The bigger
  scoreLoop superlinearity (1.65× per-edge growth 5k→20k) is a **memory-hierarchy/GC
  effect** (isolated RSS blows to 1 GB+ at n=20 000) that **survives the fix** — it is
  *not* hash-set churn. The deeper cost is per-pair Born-mixer + transport-lane
  double-eval + boxed `transportRows` writes (finding 3), which can't be isolated without
  reimplementing private engine symbols and forfeiting the bit-identity guarantee.

**3. Per-edge boxing + per-row sort in transport CSR build** — `logos_git.dart:2617, 2975` · sev 3 · conf 0.7 · risk none
`transportRows` is `List<Map<int,double>>` with boxed `int→double` entries written
inside the scoreLoop, then a per-row `entries.toList()..sort()` at finalize. Boxed map
entries (~64 B each) + per-row alloc + comparator sort are prime suspects for the
per-edge growth.
- **Fix:** accumulate into typed-array scratch keyed by node id (parallel to the existing
  `Float64List` rawRows/degree/transportMass), emit CSR by ascending-id scatter (no
  comparator sort). `max`-symmetrize semantics preserved exactly → bit-identical CSR.
- **Requires** a CSR-equality validation gate in `experiments/logos_bench/` before landing.

### Tier 2 — the "refresh when lots of files change" reframe (the actual felt pain)

The engine is HEAD-gated, so the lag the user feels on working-tree churn is **not** an
engine rebuild. It's these, all numerically-identical, none touching engine output:

**4. Unconditional full-cache re-serialization + disk write on every HEAD move** — `logos_git_resolver.dart:216` · sev 3 · conf 0.85 · risk none
`_persistCache` fires after *every* cold resolve, re-emitting all four typed-array blocks
(~4 800 B/entry) into a `BytesBuilder` and writing the whole blob to disk — **even when
every entry was a cache hit** and the bytes would be byte-identical. The `unawaited` write
contends with the foreground build during the warming window — a direct contributor to
felt refresh lag.
- **Fix:** thread a `dirty` flag (set when `missPaths.isNotEmpty` OR a prior cache key is
  absent from the new entry set, preserving stale-flush) and gate `_persistCache` on it.
  A clean resolve then writes nothing. Output is the returned `EngramFileKTable`, built
  from `merged` regardless — zero engine-output impact.

**5. `clusterFiles` topology cache over-invalidates on stage/unstage toggle** — `changes_page.dart:1641` (+ `file_coupling.dart:1492`) · sev 2 · conf 0.86 · risk none
The cluster cache key includes `Object.hashAll(_includedPaths)`, but the expensive
topology phase (candidate enumeration, union-find roots, members) is **invariant to
`includedPaths`** — only the cheap ordering phase reads inclusion. So **every checkbox
toggle busts the whole cache** and repays the `O(n²)` cluster build **on the UI thread**.
This scales with changeset size → "lags exactly when the changeset is large." Most likely
the dominant source of the user's felt stutter.
- **Fix:** split into (a) an include-independent topology cache keyed on
  `status/matrix/engine/sortGuide/...` (NOT `includedPaths`), and (b) a pure include-aware
  ordering pass applied on toggle. Once topology output doesn't close over `includedPaths`,
  a toggle structurally cannot invalidate it. Identical clusters + ordering.

**6. `stat()` storm before extension filtering** — `logos_git_resolver.dart:156` · sev 2 · conf 0.82 · risk none
The classification loop `statSync()`s every path in the node-path union **before** any
extension gate; non-indexable files are stat'd synchronously on the calling isolate and
the result thrown away (the gate lives downstream in the encode isolate).
- **Fix:** hoist the `_kIndexableExtensions` check above `statSync`, sharing one const with
  the isolate gate (single source of truth). The set of encoded files is unchanged.

### Tier 3 — derived, lower priority (real but not hot / capped / off-thread)

| # | Finding | Location | sev | Notes |
|---|---|---|---|---|
| 7 | `O(h²)` engram-only hunk pair scan | `logos_hunks.dart:725` | 2 | Background AI-prompt isolate, once per prompt-pack; only bites on 1000+-hunk diffs. **Fix must be an exact norm-bound prefilter — LSH/random-projection is rejected (false negatives = output nerf).** |
| 8 | 3× redundant HEAD `rev-parse` per cold resolve | `logos_git_resolver.dart:595` | 2 | Private `_headSnapshots` bypasses the shared coalesced `RepoHeadCache` + subprocess semaphore. Constant-factor I/O on the cold path. |
| 9 | Symmetrise allocates `n` transient `Map<int,int>` back-ref indexes/build | `logos_git.dart:2896` | 2 | `O(E)` hashmap entry allocs; replace with typed-array scratch. |
| 10 | Per-hunk `O(L)` line rescan building the per-file context plan | `diff_logos_facade.dart:1864` | 2 | `O(h·L)` per file open (interactive). |
| 11 | EngramBrain + full disk cache re-parsed every resolve (again per encode isolate) | `logos_git_resolver.dart:144` | 2 | Redundant parse on cold builds. |

> **`file_coupling.dart` co-change ingestion** (round-1 finding) — `computeFileCoupling`
> lag-0/lag-1..3 nests at `:1066-1130` accumulate co-change into `Map<String,Map<String,double>>`
> with per-pair string hashing + inner-map births. **Still valid as a cold-build
> (stats-ingestion) cost** with the same int-interning fix (intern paths to dense ints,
> bit-identical Jaccard), but it is **upstream of the measured `buildFromStats` closure**
> (not timed here) and is **HEAD-gated** — it does *not* fire on working-tree changes, so
> it's lower urgency than round-1's framing implied.

## The latent O(n²) landmine

`calibrateCouplingConstants` has a dead all-pairs branch (`logos_git_integrity.dart:516-529`)
taken only if its `jaccardEdges` callback is `null`. Measured extrapolation: **~200 M pairs
at n=20 000** — a multi-second catastrophe. Currently never reached (the build always passes
a non-null callback → the `O(m)` branch). **Make the null callback unrepresentable** (require
a non-nullable param, delete the else-branch) rather than guarding it — a null-check
band-aid leaves the `O(n²)` path representable.

## Refuted (and why it matters)

10 findings were dropped by the adversarial pass — this is the rigor that makes the
survivors trustworthy:

- **`spectral_ricci.dart` dense `n×n` all-pairs hop matrix** (400 MB) — real quadratic,
  but `ricciField()` has **zero production callers**. Dead code. (sev 4→1)
- **`spectral_walks.dart` bridge/sharpest walk redundant `exp()`** — real, but **no
  production callers**; explain-back feature unimplemented. (sev→1)
- **`logos_diff_attention.dart:528` "O(F²)"** — `F` is structurally **capped at h≤16**
  (the `2^h` Walsh spectrum forces it); worst case 256 microsecond ops. (sev→1)
- **`flowIsContradictory` O(arrivals²)** — the *proposed fix was mathematically wrong*:
  empirically 137 629/200 000 random cases give a different `seedA/seedB`, flipping the
  `contradictory` boolean = an **output nerf**. Correctly rejected. (sev→1)
- **Trajectory Lanczos "warm-start"** — would reseed the deterministic Krylov subspace
  (fixed LCG `0xA1ECDA15`) → different eigenpairs = breaks determinism/golden tests. Half
  the proposal was a nerf. (sev→2)
- Plus the three round-1/round-2 "full rebuild on any change-set flip" findings — all
  **mislocated the trigger** (HEAD-gated, not change-set-gated).

## Coverage

All 9 subsystems mapped (build-spine, resolver/stats, core-math, spectral, engram,
diff/hunk features, triggers, graph-coupling, tokenizers). Per-cluster hot-path
inventories recorded in the run transcript.

### Caveats / still underived

- The harness times **only `buildFromStats`** (the cold compute). The **resolver disk/IO
  layer** (findings 4, 6, 8, 11), **UI clustering** (5), and **hunk ranking** (7) are
  **derived from code, not wall-clock measured**. A follow-up harness timing `_persistCache`
  and the resolver classification loop (cold vs warm FS cache) would convert these.
- Numbers use **synthetic** stats (single fan-out distribution, ~200-dir tree). The large-end
  exponents (1.37–1.47) should be re-validated against a real large repo's exported
  `LogosGitStats` before treating them as universal.
- The scoreLoop superlinear knee is attributed to allocation/GC from counters + RSS, **not**
  confirmed with an allocation profiler. A Dart Observatory profile at n=20 000 would pin the
  exact dominant allocation (transport-map boxing vs roles strings vs obsBuf churn).
- A **bit-identical CSR validation gate does not yet exist** — it's a **prerequisite** for
  landing findings 3 and 7 under the no-nerf constraint.

## Benchmark harness

Reusable, in `experiments/logos_bench/` (pure scratch, outside the app):

- `headline.dart` — synthesizes stats at n ∈ {200, 1k, 5k, 20k}, times `buildFromStats`
  with per-phase `probeTimingsUs`, RSS, log-log scaling fit.
- `scoreloop_candidates.dart` — isolates the candidate-assembly sub-kernel; validates the
  reused-buffer optimization bit-for-bit.
- `coupling_calibration_kernel.dart` — isolates `calibrateCouplingConstants`; validates the
  double-`TransportRoles` fix bit-for-bit; demonstrates the latent `O(n²)` catastrophe.
- `flutter_stub/` + `package_config.json` — pure-Dart shim so the engine links under plain
  `dart` (see correction 1).

Run: `dart --packages=experiments/logos_bench/package_config.json experiments/logos_bench/headline.dart`

## Implementation status (2026-06-15)

**Landed (numerically-identical, validated):**
- **Finding 1 — double `TransportRoles`.** `calibrateCouplingConstants` now takes an
  optional `rolesOf` read-through (`logos_git_integrity.dart`); `buildFromStats` threads
  its existing `transportRoles` via `pathToId` (`logos_git.dart`) — no throwaway map, the
  owned artifact is reused. Bit-identity confirmed: the deterministic transport-graph
  test value is unchanged to the last digit with vs. without the change. Measured 2.14×
  on the isolated calibration kernel; in-build it's a clean ~1.35–1.6× on the calibration
  *phase* at realistic sizes (n≤1000), shrinking into noise at 20k where the phase is
  dominated by the irreducible O(m) edge-classification loop.
- **Finding 6 — stat-gate hoist.** New single-source `isEngramIndexablePath`
  (`engram_file_index.dart`) used by both the encoder and the resolver's pre-stat gate;
  non-indexable paths now skip `statSync` (`logos_git_resolver.dart`). Output-neutral
  (the encoder dropped exactly these anyway).
- **Finding 4 — resolver dirty-flag.** `_persistCache` now gated on
  `missPaths.isNotEmpty || cache.size != hits.length` — a clean all-hit resolve skips the
  ~1–10 MB re-serialize+disk-write; any prune (stale entry) still writes. Semantic no-op
  on the skip path.

All four touched files pass `dart analyze` clean and the engine test suite shows no new
failures (the two reds are pre-existing: an R&D test pinned to live-repo data, and a
transport-value test drifted by unrelated uncommitted `logos_core.dart` edits).

## Suggested landing order (remaining)

3. **`clusterFiles` cache split** (5) — the interactive stutter on large changesets.
4. **Non-nullable `jaccardEdges`** — close the latent O(n²) landmine.
5. Transport CSR unboxing (3) + scoreLoop buffer (2) — *after* a bit-identical CSR gate exists.
