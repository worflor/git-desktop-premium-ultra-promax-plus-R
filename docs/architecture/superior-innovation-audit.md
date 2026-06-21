# Superior-Innovation Audit — 2026-06-15

A read-only, 40-agent audit cross-referencing the git-logos engine against the 123
Principia engineering Circles and the alpha-math exact engine, hunting objectively-
better geometric objects that make unoptimized structures (and whole issue-classes)
unrepresentable — each required to name a **Circle**, an **alpha-math/exact witness**,
and a **bit-for-bit invariant**. 86 Circles catalogued, 36 targets, **24 proposed → 8
survived adversarial verification, 16 refuted.**

## The honest verdict

**The engine is already tight.** The most valuable output of this audit is the
*refutation* set: two-thirds of the "beautiful object" proposals died because the
engine already does the optimal thing, the target is dead code, or the replacement
would silently change output. The no-nerf bar worked exactly as intended — it killed
every probabilistic / reorder shortcut. There is no pile of free beautiful-object wins
sitting in the live hot path.

What the refutations teach (the real signal):
- **Already implemented** — "replace eager eigenbasis with matrix-free screened g(L)":
  `logos_core.dart:1066 chebyshevDiffuse` *already* is matrix-free Chebyshev/Clenshaw;
  `:1042 adaptiveK` *already* is "K* set by t not n"; the cached eigenbasis is a
  *deliberate* amortization across same-spectrum queries (the 60 Hz slider), not an
  accident. Replacing it would be slower.
- **Dead code** — the Ricci n² matrix and the GYAT `_encodeSpan` O(span²) are real
  quadratics but live on paths with **zero production callers** (confirmed in
  `logos-perf-audit.md`). Worth fixing *before* they're ever wired, not for current perf.
- **Would nerf** — Eytzinger (no CMOV in Dart AOT), SWAR bitset co-occurrence (drops
  the lag-1..3 transfer-entropy edges → false negatives), Lanczos selective-reorth
  (flips `spectralFingerprintTable` sign bits + targets <1% of cold start), Hutch++
  (stochastic estimate of a deterministic golden-tested trace), the GYAT Clifford-XOR
  (false novelty on a zero-consumer field), Morton/Int64 addressing (fabricated wall +
  heuristic prefilter that misses the true k-ball). All correctly rejected.

## What genuinely survives (live, faithful, constant-factor)

These are allocation/GC kills on the two measured hot phases — they *sharpen* the
earlier perf-audit findings, they don't replace the engine's algebra.

**1. Coupling Gram accumulator** — `file_coupling.dart:1063-1142` · the strongest live win
- Current: `Map<String,Map<String,double>>` co-change storm — per mega-commit `O(k²)`
  `String.compareTo` + `putIfAbsent` + boxed `double` + Map-node alloc, re-walked three
  times (pairCount build / Jaccard rewalk / CSR rewalk). The named n=20k GC/calibration
  offender.
- Superior object: keep incidence `B` sparse, accumulate `C = BᵀB` at its nnz via one
  reused `Float64List` scatter over interned int ids, **fused into a single CSR pass**.
  Circle LVII (private scatter accumulation) + LXIII (int-keyed store). Witness: S1
  (`rankOf(C) ≤ #commits`, proven) + a Freivalds gate + the load-bearing golden-diff.
- **Honest scope:** constant-factor + allocation + pass-fusion, **NOT** asymptotic (on a
  dense k-file commit nnz ≡ k²/2; Jaccard needs the materialized nnz, so the
  "file-count-independent matrix-free" headline does **not** reach this hot path).
- **Fidelity (resolved here):** the dossier worried sorted-id read-out vs Map-iteration
  order breaks bit-identity. It doesn't — per-cell sums accumulate in **commit order**
  in both; read-out order only changes CSR emission order, not the order of additions
  *within* a cell. So bit-identity is preserved **by construction** as long as commits
  are processed in the same order (they are). This win is green.

**2. Transport COO triple-buffer** — `logos_git.dart:2626, 2984`
- Current: `n` boxed `Map<int,double>` rows + `n` throwaway `entries.toList()..sort()`.
- Superior object: one contiguous COO `(Int32 rowSrc, Int32 col, Float64 val)` buffer →
  counting-sort by `(row,col)` → linear segment-MAX merge (the Map's max-on-improve
  semantics). Circle LVII + III (row-major key) + XIV (AoSoA). `holdsOn(max)` proves the
  segment-max is order-independent.
- **Fidelity caveat (must respect):** `transportMass` is currently a *telescoped*
  running-delta sum in arrival order (`:2814/2829/2859/2874`) and feeds `inv =
  1/transportMass` scaling every value. A clean re-summed max diverges at ULP scale
  (float non-associativity). To stay bit-identical, accumulate the mass as a **separate
  arrival-order running-delta** (preserve the telescoping); COO+segment-max for the
  values only. Then it's clean.

**3. Ricci n² → per-edge local BFS** — `spectral_ricci.dart:250/527` · latent-wall, dead path
- `RicciField.sinkhorn` allocates `Int32List(n*n)` (~400 MB at n=1e4; allocation fails
  past n≈46341 — **not** an arithmetic overflow; Dart ints are 64-bit). Replace with the
  bounded local BFS that `curvatureOfEdge` (`:311`) *already* implements — bit-identical
  because every `(a∈N(u), b∈N(v))` pair resolves via `a-u-v-b` (≤3 hops) so `maxHops=4`
  returns the exact integers the dense matrix held. Circle LVII + S4 screening.
- **Status:** `ricciField()` has zero production callers today → this is "make the latent
  quadratic-memory wall unrepresentable before wiring," not a current perf win. Honest
  time caveat: per-edge re-BFS can regress by ~deg on small/dense graphs → gate on n.

## Issue-classes made unrepresentable (the real prize)
- *Materialize-n²-for-an-O(local)-quantity* (Ricci): no length-n² buffer in the type
  surface → the OOM cannot be written.
- *O(k²) nested-String clique allocation per commit* (coupling): with `B` sparse and `C`
  scattered through a typed buffer over int ids, no `Map<String,Map<String,double>>`
  exists to write the boxing storm into.
- *Per-edge boxed Map row + throwaway per-node comparator sort* (transport): typed COO
  lanes + idempotent segment-max leave nothing to box or per-node-sort.

## Validation-harness plan (extend `alpha-math/scale-free-proofs.ts`)
- Coupling: golden-diff every `jaccard[a][b]` (==) between the String-map and int-scatter
  pipelines on real repos (incl. the asymmetric non-dedup lag cross-product + empty rows);
  Freivalds `Bᵀ(Br) == C·r` over GF(2³¹−1) as the O(nnz) structural gate; `rankOf(C) ≤
  commits`. Determinism guard: run twice, assert byte-identical.
- Transport: golden-diff `transportValues/Indices/Indptr/Mass`; `holdsOn(max)` idempotence;
  the mass kept as a separate arrival-order delta.
- Ricci: dense vs screened curvature elementwise `==` on path/ER/cluster graphs + a
  maxHops-sufficiency assertion; sweep n past 46341 to confirm no n² allocation.

## The standing conclusion
No-nerf + already-optimized means the micro-win surface is largely exhausted. The genuine
1→10²³¹⁰³²⁴ prize is **not** more micro-refactors — it is the **scale-free architecture**
(proven exactly: S1 CC=BBᵀ rank≤commits, S2 git-tree H-matrix, S3 abelian multipliers, S4
screening, S5 Born-non-assoc forces the tower; `scale-free-proofs.ts`). The micro-wins
above are worth installing (faithful, measured offenders), but they are *tightening*, not
*superior innovation*. The superior innovation is the factored, tree-addressed,
locally-evaluated operator.
