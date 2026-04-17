# Whisper -> Logos Borrowings Notes

## Purpose

This document records concrete borrowable ideas from the Whisper codec family in `C:\Users\mini server\Documents\Projects\worflor.github.io\src\scripts\whisper` and maps them onto the current Logos/Engram engine in this repo.

This is not a metaphor dump. It is a grounded extraction of operator ideas, witness schemes, axes, sidecars, and control laws that can be implemented in Logos without turning the project into decorative math.

## Files examined

Primary reads:

- `live-loop.ts`
- `live-wasm-glyph.ts`
- `live-wasm-kizuna.ts`
- `live-wasm-logos.ts`
- `live-wasm-loup.ts`
- `live-wasm-spatial.ts`
- `LICENSE.md`

Existing in-repo grounding also matters:

- `apps/desktop-flutter/lib/backend/logos_git.dart`
- `apps/desktop-flutter/lib/backend/logos_git_integrity.dart`
- `apps/desktop-flutter/lib/backend/logos_hunks.dart`
- `apps/desktop-flutter/lib/backend/logos_chunks.dart`
- `apps/desktop-flutter/lib/backend/pr_shape.dart`
- `apps/desktop-flutter/lib/backend/repository_xray.dart`

## Current Logos situation

Current Logos is already:

- semantic-history aware
- integrity-aware
- ambient-aware
- multiscale at the file level
- weakly higher-order through commit hyperedge sidecars
- witness-emitting
- flow-aware at PR/query level

Current representational ceiling is still:

- pairwise graph core
- effectively symmetric transport operator
- scalar path ranking remains dominant
- typed/directional relations mostly influence rescue/gating/explanation, not the native diffusion operator
- most context consumers still collapse rich evidence into compact path summaries

That makes Whisper useful mainly for:

- sidecar logic
- witness hierarchies
- predictor competition
- regime-aware gating
- derivative / second-moment axes
- boundary-aware computation

Not for:

- forcing Logos into literal codec algebra
- replacing the repo graph with Möbius arithmetic
- importing compression-specific machinery where the decision problem is different

## Concrete borrowings from Whisper Logos

Source: `live-wasm-logos.ts`

### Logos 0D axes

The codec describes a predictor with these axes:

- `L`: intra-byte tree context
- `U`: bit-lane temporal AR(2)
- `X`: cross-subspace prefix proxy
- `O2`: full previous byte identity
- `Z`: XOR derivative, explicitly framed as a temporal derivative / velocity term
- `E`: AR(2) trajectory predictor over bytes
- `P2N`: coarse bigram / nibble class
- `V`: volatility / local temperature / second moment
- `M`: exact match witness
- `A`: structural attention witness

### Borrowable ideas

1. `Z` axis -> derivative / velocity lane for Logos

Current Logos has support, ambient, spectral residual, and integrity. It does not yet have a native derivative-style lane that asks:

- where is inquiry accelerating
- where do relation patterns change abruptly between adjacent context layers
- where is the diff introducing a directional transition, not just a static hotspot

Best mapping:

- a query-path derivative lane over support fields across scale or expansion step
- a “transition witness” for inquiry routes
- a delta lane comparing near vs far support, or current field vs previous interaction step

This is stronger than just `highFrequencySurprise`; it is a directional rate-of-change observable.

2. `V` axis -> second-moment / local temperature observable

Whisper Logos is explicit that `V` is not another first-moment predictor. It tracks local loudness / envelope / volatility.

Best mapping:

- add a repo/query temperature observable separate from support
- distinguish:
  - hot but coherent zones
  - hot and noisy zones
  - cold but structurally important zones
- use this as a controller input for proof budgets and witness escalation

Current Logos partially approximates this via integrity, cadence, and stress, but does not yet expose a clean second-moment lane.

3. Independent witness injection (`M` / `A`)

Whisper Logos separates correlated pooled axes from independent witness channels injected in log-odds space.

Best mapping:

- preserve a carrier vs witness distinction in Logos
- do not force all modalities into one mixed score
- allow exact-match / mirror / generated-companion / ownership / test witnesses to remain separately legible, then corroborate or override when needed

This aligns directly with the current typed witness work in `logos_git.dart`, but the next step is to make witness agreement/disagreement first-class rather than flattening witnesses into labels.

4. 3-state SSE regimes -> repo/query regime calibration

Whisper Logos uses explicit regimes like gas / volatile / crystal.

Best mapping:

- query / repo context regimes such as:
  - quiet / coherent
  - volatile / transitional
  - crystallized / strongly matched
- calibrate evidence thresholds and witness expectations differently per regime
- do not let volatile-zone behavior contaminate the steady-state calibration surface

Current Logos calibration is still mostly probe-axis utility tuning. Regime-aware calibration is an obvious next control improvement.

5. Entropy monitor -> noise bypass

Whisper Logos bypasses expensive match/attention axes in near-random regions.

Best mapping:

- skip expensive witness/higher-order enrichment in noise-dominated or low-integrity regions
- use selective compute more aggressively:
  - cheap pass first
  - enrich only when support/surprise/stress justify it

This has already started to land in Logos through `detailBudget` and selective enrichment in `gatherEvidence(...)`. It should go further.

## Concrete borrowings from Whisper Glyph

Source: `live-wasm-glyph.ts`

### Core ideas

From comments and structure:

- `(x,y)` treated as a complex oscillator with `K` and `G`
- pressure / tilt / azimuth are witness channels
- sidecar / delta / coupling / micro-residual trials are gated
- when witness confirms shared dynamics, it compresses almost for free
- when witness disagrees, the codec falls back

### Borrowable ideas

1. Carrier / witness separation

This is one of the cleanest mappings to Logos.

- carrier: diff + file graph support field
- witnesses: tests, ownership, generated/source relation, telemetry, symbols, docs, rollback lanes

Rule:

- only bind witness channels tightly when the same local dynamics explain them
- otherwise keep them as separate evidence, not merged confidence theater

2. Metric sidecars

Glyph/Harmonic-style sidecars are the strongest immediate borrow.

Best mapping:

- when reducibility gap, field surprise, or structural stress crosses a threshold, attach a local metric sidecar rather than just ranking more files
- sidecars can carry:
  - generated/source transport map
  - local symbol/dataflow slice
  - test-to-code witness map
  - service boundary transport hints
  - migration/rollback pair map

This is the repo equivalent of transmitting the local metric when the geometry changes too fast.

3. Micro-residual local retry

Glyph runs gated local trials rather than globally committing to one richer model.

Best mapping:

- a second-pass local model for a suspicious neighborhood only
- for example:
  - local route re-ranking inside one subsystem
  - local witness corroboration around one top candidate
  - local higher-order escalation when pairwise loss is high

This is a much better fit than making the global operator exotic too early.

## Concrete borrowings from Whisper Kizuna

Source: `live-wasm-kizuna.ts`

### Core facts

- 16D Möbius residual over a 65536-byte block
- factored as 8D x 8D
- exposes 256 row-wise 8D sub-witnesses “for free” via factorization
- those sub-witnesses localize corruption / mismatch without extra communication

### Borrowable ideas

1. Witness hierarchy / syndrome localization

This maps almost perfectly onto Logos.

Current Logos has:

- file-level evidence
- hunk inheritance
- chunk witness headers

The Kizuna lesson is:

- every global anomaly should come with localizable sub-witnesses

Best mapping:

- repo witness
- subsystem witness
- package witness
- file witness
- hunk witness
- chunk witness

Then if a global evidence packet is “wrong” or insufficient, the syndrome shows where the disagreement sits.

2. Factorized diagnosis, not only factorized scoring

The key point is not just hierarchy for hierarchy’s sake. It is:

- preserve the ability to localize error sectors cheaply

Best mapping:

- when a packet is weak or contradictory, surface which blanket / subsystem / file sector is under-witnessed
- do not just lower confidence globally

This is a cleaner path to proof budgeting than another flat confidence score.

## Concrete borrowings from Whisper Loup and Spatial

Sources:

- `live-wasm-loup.ts`
- `live-wasm-spatial.ts`

### Core facts

Loup:

- higher-dimensional Möbius predictors
- explicit boundary theorem
- huge free-zero boundary fraction
- interior points carry the real residual burden

Spatial:

- multiple coding modes per block chosen adaptively (`fixed`, `sparse`, `rice`, `raw`, `dual`, `rawsparse`, `binarysurf`)
- topology recursion: 3D surface encoded by descending into 2D structure
- explicit statement that block entropy is a decomposition bound, not the final compression bound

### Borrowable ideas

1. Boundary-aware exactness

Best mapping:

- some repo regions are boundary regions with effectively exact transport law:
  - direct generated companions
  - obvious manifest/lockfile pairs
  - test fixtures bound to one implementation pocket
- other regions are interior and should carry the model uncertainty burden

This suggests:

- boundary-aware witness privilege
- interior-focused escalation
- better separation of “obvious companion” vs “structurally ambiguous dependency”

2. Local model competition

Spatial’s adaptive coding modes map directly to Logos control.

Best mapping:

- do not force one retrieval operator everywhere
- allow local competition among bounded models:
  - plain pairwise diffusion
  - higher-order sidecar lift
  - typed transport lane
  - symbol-local route
  - test witness route
- choose the cheapest adequate local model

This is very compatible with the project’s existing multi-predictor instincts.

3. Topology recursion across scales

Spatial’s surface recursion is a strong argument for:

- treat subsystem/package/file/hunk/chunk as a real multiscale pyramid
- let some evidence objects recurse into lower-dimensional structure rather than just listing files

This already partially exists in Logos. The missing piece is to make the witness chain explicit and decision-aware.

## Concrete borrowings from Whisper Loop

Source: `live-loop.ts`

### Core facts

The loop uses multiple competing coders / models:

- `BitM`
- `Bit1`
- `BitX`

`BitX` is explicitly a derivative / velocity-flavored model inspired by the Logos Z-axis.

### Borrowable ideas

1. Predictor competition

Do not pretend one evidence mixer is the oracle.

Best mapping:

- let multiple bounded routing models compete on a local problem
- keep them all cheap
- emit the winner or pooled result only when justified

This is better than endlessly growing one universal score.

2. Velocity / derivative witness

This independently reinforces the `Z`-axis idea from Whisper Logos.

A good next experiment in Logos is a derivative witness over:

- support field change across expansion steps
- query state change across user interaction steps
- route instability between scales

## Concrete borrowings already compatible with current Logos

These map cleanly right now:

1. Metric sidecars
- attach local metric/transport maps only in high-curvature or high-reducibility zones

2. Witness syndrome / hierarchy
- explicit agreement / disagreement report across file/hunk/chunk and later package/subsystem

3. Derivative / velocity lane
- separate from support and surprise

4. Regime-aware calibration
- quiet / volatile / crystallized contexts

5. Noise bypass / selective compute
- expand only when structural value warrants it

6. Carrier vs witness separation
- do not collapse all modalities into one scalar too early

7. Local model competition
- pairwise diffusion vs typed lane vs higher-order sidecar vs symbol-local map

## Borrowings that should wait

These are interesting, but not the next build step:

1. Literal Möbius or hyperdimensional algebra in the main repo operator
2. Full sheaf / signed operator rewrite across the whole graph
3. Full dynamic hypergraph escalation in the hot path
4. Free-energy or quantum framing as architecture
5. Generalized condensate/workspace machinery before witness syndromes and metric sidecars exist

## Current codebase changes that already move in the right direction

Already implemented in this repo:

- semantic history weighting and semantic commit clock
- integrity / ritualness profile with shrinkage
- ambient prior and utility ranking
- dual support/surprise fields
- commit hyperedge sidecar
- typed relation and transport witnesses
- file -> hunk -> chunk witness propagation
- PR flow diagnostics
- repo X-Ray flow summary
- selective evidence enrichment via `detailBudget`
- primitive-safe isolate transport for chunk witness headers

These are all compatible with the Whisper borrowings above.

## Best next native seam after this note

If the goal is maximum leverage without destabilizing the engine, the next order should be:

1. `MetricSidecar`
- attach local geometry/transport patches when surprise/reducibility/stress is high

2. `WitnessSyndrome`
- explicit agreement/disagreement and missing-witness reporting across scales

3. derivative / velocity lane
- a real transition observable, not just scalar surprise

4. regime-aware calibration
- quiet / volatile / crystallized evidence/query modes

5. local model competition
- bounded operator selection in suspicious neighborhoods

## One-line summary

Whisper’s strongest gift to Logos is not exotic algebra. It is a disciplined design language:

- transmit the metric when local geometry shifts
- keep witnesses separate from the carrier until shared dynamics justify binding them
- localize anomalies with hierarchical sub-witnesses
- let small bounded models compete
- spend extra compute only where the medium becomes structurally interesting

## Additional grounding from Wegener review (2026-04-15)

- `src/scripts/whisper/lumen-logos.wat`: extra witness/context axes worth studying for PR-flow decomposition and directional evidence fields: `Ab`, `Dg`, `Sp`, `J2D`, plus the `V`-style volatility lane described by companion JS. `J2D` is especially relevant because it encodes entangled directional structure rather than another scalar confidence.
- `src/scripts/whisper/live-wasm-logos.ts`: confidence-weighted witness mixing pattern is directly reusable in Logos when multiple witness pools disagree. The implementation combines correlated vs independent evidence families instead of pretending one universal pool exists.
- `src/scripts/whisper/live-wasm-logos.ts`: concrete sidecar telemetry pattern already exists via `_lastDiag` and `diagHist`. Useful design rule: keep heavy internal state private, expose compact diagnostic sidecars only when requested.
- `src/scripts/whisper/live-wasm-logos.ts`, `src/scripts/whisper/live-wasm-spatial.ts`, `src/scripts/whisper/live-wasm-akasha.ts`: selective-compute gating based on entropy / amplification quality. This matches Logos's need to avoid paying full topology cost on noisy or low-confidence queries.
- `src/scripts/whisper/prism.ts`: low-cost order-spectrum gate (`highOrderFraction`) is a good template for deciding when Logos should escalate into higher-order or sidecar-heavy treatment.
- `src/scripts/whisper/live-loop.ts` and `src/scripts/whisper/prism.ts`: witness / handshake continuity patterns can inform future proof-budget and syndrome design in Logos.
- `src/scripts/whisper/campfire/topology.ts` and `src/scripts/whisper/campfire/types.ts`: bounded-degree neighbor topology with churn-aware rebalancing is a grounded design reference for local PR/desk topology caches.
- Practical caution: the WASM-heavy Whisper pieces rely on explicit memory layout and export conventions. Borrow the operator ideas and telemetry envelopes, not the raw offset-coupled implementation style.
