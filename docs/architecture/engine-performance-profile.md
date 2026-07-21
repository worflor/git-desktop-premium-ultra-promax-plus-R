<!--
SPDX-FileCopyrightText: 2026 Woflo Labs
SPDX-License-Identifier: LicenseRef-WLCSL-1.0
See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.
-->

# Logos Engine — Whole-Engine Performance Profile (2026-06)

A board-level profile of the spectral engine and everything it touches: where time
actually goes, what recomputes on every refresh, and a ranked backlog of
clever-engineering wins (no capability removed). Built from a 6-agent code sweep +
the real `spectrum_profile.dart` profiler + the `review-evidence` gather telemetry.

**Confidence tags:** `[MEASURED]` (real profiler/telemetry), `[VERIFIED]` (I read the
code and confirmed the mechanism), `[AUDIT]` (matches a prior dossier/memory),
`[EST]` (agent reasoning, magnitude unverified).

---

## 0. Headline corrections (where intuition/agents were wrong)

- **The spectral core is cheap, not the bottleneck.** `[MEASURED]` Lanczos
  `lanczosSmallEigenpairs` (k=20) solves in **2.4–6.7 ms** on real repos
  (git-desktop 6.7ms, others ~2–2.5ms; synthetic cliques 0.1–0.3ms). An agent
  guessed "100–500ms" — off by ~50×. Eigen-decomposition, observables (gap/chaos/
  dimension), and the spectral dimension stochastic trace are all **lazy and O(k)
  or O(k·n)** — not worth optimizing for speed.
- **The cost lives in the gather**, specifically the recurrent diffusion +
  per-iteration diagnostics, the graph *build* (cold-start), and the *refresh*
  recompute paths — not the linear algebra.

---

## 1. Cost map by subsystem

| Subsystem | Entry | Real/est cost | Hot spot |
|---|---|---|---|
| **Cold-start / graph build** | `LogosGit.buildFromStats` (logos_git.dart:2320) | ~100–300ms build + ~150ms git I/O `[EST]` | scoreLoop (98% of build), transport-lane double classify |
| **Spectral core** | `lanczosSmallEigenpairs` (logos_core.dart:1934) | **2–7ms** `[MEASURED]` | not a bottleneck |
| **Diffusion / evidence** | `gatherEvidence` (logos_git.dart:3817), `gatherEvidenceRecurrent` (4459) | **~2.2s** gather `[MEASURED]` | per-iteration summary diagnostics (recomputed, discarded) |
| **Ranking / planner** | `plan` (logos_git.dart:5804), `_packTopPhi` | O(K·\|E\|) diffuse + O(n log topK) | no de-hub → `.metadata` dominates |
| **Flow engine** | `extractFlowGraph` (logos_flow.dart:136), `_yaaStarPropagate` (621) | ~60ms/file `[EST]` | `_PathChain.signature()` String alloc |
| **AI producers** | `assembleAndStitch` (ai_context_engine.dart) | **assembly 3.1s** `[MEASURED]` | structural_verification 2.9s, shadow_history 2.4s→∅ |
| **Refresh paths** | changeset_controller, palette_scorer, repo_xray | varies | cache-defeating recompute (see §3) |

### Measured gather phase split (`review-evidence`, 17-file diff, `[MEASURED]`)
`git 0.3s · diffusion 2.2s · bundle 0.1s · assembly 3.1s` (total ~5.7s, cold engine).
Producer wall-times: structural_verification 2.9s, file_context 2.8s,
shadow_history 2.4s (→ 0 output), file_metadata 1.9s, relevance_neighborhood 0.7s.

---

## 2. The verified high-value findings

### 2.1 Recurrent diagnostics recomputed every iteration, only the last is used `[VERIFIED]`
`gatherEvidenceRecurrent` (logos_git.dart:4492) loops `gatherEvidence` and passes
`includeSummaryDiagnostics: includeSummaryDiagnostics` (4509) to **every** iteration.
`gatherEvidence` then computes — gated on that flag (4304–4423) — coherence,
`diffuseStability` (4310; itself `nTrials+1` Chebyshev diffusions, 5496–5514),
fieldAlignment, flowRollup, flowDiagnostics, transport, semanticMotion,
witnessResidual, inquiryPlan, witnessSyndrome. The loop only consumes
`evidence.ranked`'s residuals for novelty/weight adaptation (4529–4543); the
intermediate diagnostics are **discarded**. → Gate `includeSummaryDiagnostics=false`
for all but the final iteration. Magnitude: 2–3× of the diagnostics block;
**measure on the harness before claiming a number** (the "800ms" estimate was inflated —
diffusions are few-ms each).

### 2.2 Transport-lane double classification in the score loop `[AUDIT]`
`buildFromStats` scoreLoop calls `logosTransportLaneStrengthOfRoles` →
`_classifyTransportLane` **twice per pair** (forward + reverse;
logos_git.dart:~2805/2820 + the transport-candidate loop ~2850/2865). Transport is
~36–44% of the score loop. → one `_classifyTransportLaneSymmetric(A,B)` returning
`(fwd, rev)`, optionally memoised by `(min,max)` pair key. Matches the memory note
"2nd un-fixed TransportRoles redundancy ~2.14× measured". Est ~15–20% build speedup.

### 2.3 YAA* path dedup allocates O(depth²) strings `[AUDIT]`
`_PathChain.signature()` (logos_flow.dart:610) builds a String per push/arrival
(used at the `seenPaths`/`arrivedPaths` dedup). On a dense search that's hundreds of
thousands of short-lived strings. → rolling 64-bit hash threaded down the chain
(O(1)/step). Flagged in the earlier code review too. Est 20–40% flow speedup.

### 2.4 No specificity / IDF down-weighting → `.metadata` hub `[VERIFIED]`
`couplingStrengths` normalises degree by max degree but there is **no inverse-degree
/ IDF penalty** anywhere in the F0/CC axes or the Born mixer. A file that co-changes
with everything (`.metadata`, lockfiles, `Runner.rc`, `LICENSE`, `.gitignore`)
accumulates φ by popularity and ranks "dominant". → degree-aware confidence in the
Born mixer (e.g. attenuate by `1/log(1+min(deg_a,deg_b))`) or inverse-degree on the
CC Jaccard evidence. Keeps real coupling, kills false dominance. (Task #20.)

### 2.5 Refresh recompute that defeats its own cache `[AUDIT]`
Matches `wiring-redundancy-audit`:
- **effectiveMatrix fresh-identity defeats cluster cache** (changeset_controller.dart
  :192) — `matrix.withSpectral(...)` makes a new wrapper + `couplingVersion++` every
  `_fuse()`, so the cluster cache key changes even when the Jaccard structure didn't.
- **computeFileDimOpacity O(n²) every fuse** (changeset_derivation.dart:74) — centrality
  is from the Jaccard, not the spectral overlay; recomputed even on spectral-only refresh.
- **palette `diffuseWeighted` ×2 per keystroke, no result cache** (palette_scorer.dart:227)
  — two Chebyshev diffusions (t=0.5, t=2.0) per query after the 300ms debounce; identical
  queries (backspace-retype) recompute from scratch.

---

## 3. Cache & refresh inventory

| Cache | Key | Invalidation | Miss cost |
|---|---|---|---|
| Engine LRU (logos_git_resolver) | repo + HEAD hash | HEAD change / 15-min decay / LRU(5) | 0.5–5s build |
| FileCouplingMatrix | repo + HEAD | HEAD change | 100–500ms git walk |
| SpectralBasis | engine identity | engine lifetime | 2–7ms `[MEASURED]` |
| Chebyshev basis | (rhoFingerprint, K) | none (immutable) | O(K·\|E\|) |
| analyzeFlowCached LRU | (path, mtime) | mtime / extra-context bypass | 5–50ms/file |
| palette diffusionField | — (not cached) | every keystroke | O(K·\|E\|) ×2 |
| shadow history | repo | ~10-min memo | 100–200ms cold git |

Missing debounces: palette diffusion (only the keystroke is debounced, not the
diffuse); git watcher fires immediate cascade (no batch window).

---

## 4. Notable design facts (not bugs)

- **Lightweight snapshot** skips `gatherEvidence` entirely on big diffs (>12 files /
  >24 hunks / >64KB; diff_logos_facade.dart:1767). This is the `evidence-null` gap the
  review-evidence harness surfaces — speed over depth, by design.
- **`_ExecutionFlowProducer` under-produces** (38KB budget → ~4.5KB) because it filters
  findings to `certainty < 0.3` (only confident problems) and healthy code has few
  `[EST]`. Budget is held "just in case" a diff touches pathological flow. Not a bug.
- **The trace→full planner puzzle is unresolved.** Both I and the ranking agent could
  not derive from `plan()` alone how a trace file gets `full` tier (breadcrumb always
  wins on density). Empirically it happens; the renderer tier-cap (shipped) fixes the
  *symptom* safely. Root cause likely in how `scored` is built/filtered upstream —
  worth a dedicated trace if we touch the planner.

---

## 5. Opportunity backlog (ranked by value × confidence ÷ risk)

| # | Opportunity | Value | Conf | Risk | Where |
|---|---|---|---|---|---|
| 1 | Gate recurrent diagnostics to final iteration | high | VERIFIED | low | logos_git.dart:4492–4514 |
| 2 | Transport-lane atomic dual classify | high | AUDIT | low | logos_git.dart scoreLoop + logos_git_integrity.dart |
| 3 | De-hub φ (degree-aware Born confidence) | high (quality) | VERIFIED | med (touches ranking) | the Born mixer |
| 4 | palette diffusion result cache (≤500ms) | med-high (UX) | AUDIT | low | palette_scorer.dart:227 |
| 5 | effectiveMatrix / dimOpacity cache by Jaccard identity | med | AUDIT | low | changeset_controller/derivation |
| 6 | YAA* rolling-hash path dedup | med | AUDIT | low | logos_flow.dart:610 |
| 7 | Lower spectral-basis threshold (256→~160) | low-med | EST | low | logos_git.dart:2048 |

**Method going forward (the loop that works):** pick one, measure it on a frozen
input (`review-evidence --diff stable.diff` for gather/ranking/producers;
`spectrum_profile.dart` for the spectral core; a micro-bench for build/flow),
A/B before/after, run `flutter test test/backend/`, ship only if the numbers prove it.
Nothing changes the engine on an estimate.
