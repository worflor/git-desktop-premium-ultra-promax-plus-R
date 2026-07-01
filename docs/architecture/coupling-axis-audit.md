# Coupling Axis Audit — the temporal-holdout jury

The file-coupling surface (cluster stripes, nudges, atlas coherence) makes one
promise: *these files belong together — you will edit them together.* This
dossier records the program that put every signal behind that promise on trial
against its only honest ground truth: **held-out future co-change**.

## The instrument

Train on older commits, hold out the most recent window (~80–400 commits),
score each signal by AUC ranking held-out co-changed pairs (co-occurring ≥2
commits) against random pairs. Five repos, three languages:

| repo | lang | files | commits |
|---|---|---|---|
| MANIFOLD (this repo) | Dart | 271 | 223 |
| worflor.github.io | TS/JS | 105 | 515 |
| dio | Dart | 103 | 912 |
| express | JS | 140 | 5757 |
| flask | Python | 47 | 5539 |

Two methodology rules, both learned the hard way:
1. **Never define "hard pairs" relative to the baseline you're challenging** —
   the spectral embedding won every benchmark whose hard set was
   low-bag-similarity pairs, then lost the real objective outright.
2. **Single-repo wins are mirages** — kizuna bond charges hit 0.823 on MANIFOLD
   and lost on the other four. Convene the full jury before shipping.

## Scoreboard — singles (held-out co-change AUC)

| signal | MANIFOLD | worflor | dio | express | flask | verdict |
|---|---|---|---|---|---|---|
| jaccard (+lag) history | 0.672 | 0.703 | 0.748 | 0.612 | 0.666 | keep (baseline) |
| **IDF identifier bag** | 0.759 | 0.743 | 0.838 | 0.684 | 0.855 | **SHIPPED** |
| **token coupling charge** | 0.794 | 0.749 | 0.932 | 0.893 | 0.870 | **SHIPPED** (best single) |
| spectral embedding (PPMI eigenmap) | 0.664 | 0.548 | — | — | — | killed |
| kizuna bond charge | 0.812 | 0.692 | 0.897 | 0.868 | 0.824 | killed (4–1) |
| eigenAddress histogram (real engine) | 0.469 | 0.499 | 0.664 | 0.606 | 0.725 | **killed** |
| flow coherence (real engine) | 0.507 | 0.473 | 0.567 | 0.281 | 0.630 | **killed** |
| pathAffinity | 0.512 | 0.706 | 0.581 | 0.520 | 0.510 | keep (fallback-only, delta ≈ 0) |
| Gemma-4 embedding surgery | 0.680 | — | — | — | — | killed |
| Walsh/sign bag compression (32–128d) | 0.58–0.61 | 0.58–0.63 | — | — | — | killed |

Fusion deltas that forced the kills: adding the eigenAddress histogram to the
composite cost −0.09..−0.30 on every repo; flow coherence was worse — the
shipped composite scored 0.34–0.63 *with* it vs **0.75–0.92 without** (it fires
densely on 56–100% of all pairs with high values, so max-merge drowned every
real signal). Both harnesses dump the *real engine's* outputs
(`tool/axis_audit.dart`, `tool/flow_audit.dart`) — no python proxies.

## Fusion tournament

Candidates (all knob-free; weights measured on train only): raw `max`,
floored max, noisy-or, rank-calibrated max, train-Gini-weighted percentile sum.
**No candidate beats raw `max` robustly** (each wins one repo, loses others;
wsum wins MANIFOLD 0.805 but loses dio/express). `max` is therefore
*evidence-backed*, not merely conventional. Floors (0.25) cost ~0.015 on one
repo and buy overlay sparsity — kept.

Also killed at fusion level: adaptive token/bond selection via train-tail
validation (picks wrong on 3/5 — the meta-knob doesn't pay), directed lag
(no gain over symmetric lag), global Sinkhorn competition (0.744 < 0.769).

## What ships (the overlay after the audit)

`computeSpectralCoupling` = max-merge of exactly two content signals, both
repo-native, both jury-validated, plus receipts:

1. **IDF identifier bag** — FNV-1a hashed 2048-dim, df≥2 vocabulary, per-repo
   IDF. Co-change is literal (shared imports/constants/contracts); exact sparse
   matches are the signal, which is also why every smoothing/compression of the
   bag lost.
2. **Token coupling charge** — charge(w) = P(two files sharing w co-changed),
   measured over w's carriers (2≤df≤120) against the jaccard matrix; pair score
   = mean of top-5 shared charges. The analogue of a transformer's trained
   attention weights, read out of the git log. Pools across pairs, so it
   predicts co-change for files with zero history (0.92–0.94 on the OSS repos).
3. **Receipts** — `CouplingReceipt {token, charge, lineA, lineB}` per coupled
   pair, collected in the same read pass. Bilinearity makes attribution exact:
   the mean of the receipts *is* the score (test-verified to 1e-12). Surfaced
   in the coupling-nudge tooltip.

`score(a,b) = max(jaccard, overlay)`, pathAffinity fallback only when both are
silent (measured harmless). Charges memoized per (matrix HEAD, embedding);
model cached per HEAD in `RepoEmbeddingState`.

## EN axis (LogosGit Born mixer) — audited, kept in place

The last unaudited content signal: per-file engram K-vector cosine (identifier
runs → GloVe(300) → AR(2) fit), dumped by the real encoder
(`tool/en_audit.dart`) and scored on the jury:

| | MANIFOLD | worflor | dio | express | flask |
|---|---|---|---|---|---|
| EN single | 0.524 | 0.617 | 0.862 | 0.799 | 0.858 |
| max-fusion delta | −0.199 | −0.056 | −0.022 | −0.077 | +0.002 |

Verdict: EN carries real signal (beats the bag on dio) but is dense-and-high
like flow coherence, so **max-merge poisons it on 4/5 repos**. It is NOT in a
max-merge — it lives inside LogosGit's Born mixer, whose confidence gating and
amplitude caps are exactly the right container for this shape of signal. Keep
as-is; never max-merge it; a GloVe→repo-native coordinate swap (closing the OOV
hole) is a plausible future upgrade but needs its own Born-calibration trial.

## Open items

- Richer receipt surfaces beyond the nudge tooltip and rail stripe (atlas
  cards).
- The GloVe→repo-native EN coordinate swap above.

Benchmark corpora: shallow clones in the session scratchpad `bench/`
(re-clone dio/express/flask as needed); harness scripts exp22–exp30 in the
session scratchpad. `git read-tree HEAD` fixes clones whose `.git/index` the
Temp-sweeper eats.
