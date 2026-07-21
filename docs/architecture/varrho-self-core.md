<!--
SPDX-FileCopyrightText: 2026 Woflo Labs
SPDX-License-Identifier: LicenseRef-WLCSL-1.0
See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.
-->

# The ϱ-Core Self-Audit

*diff-free, resonance-based, whole-codebase bug finding — listening for the notes the manifold can't hold.*

**Status:** design / not yet built. This doc pins the architecture to *real* engine calls (see the Appendix) and is scrupulous about what is exact, what is hypothesis, and what is analogy — in the spirit of the varrho rigor-map.

---

## 0. Thesis

The existing code review is **forced**: it reads a diff and asks "is this change wrong?" This capability is **free**: it reads nothing but the codebase's own structure and asks "where can this code not hold itself together?"

> **A bug is a region of the codebase that is not a fixed point of self-observation** — a place that, when the manifold reflects on itself, refuses to resolve into a coherent rest state. It rings, beats, or stays dissonant instead of settling to its tonic.

Three claims make this buildable, not poetic:

1. **Spectral graph theory, harmonic analysis, and the witness algebra are the same mathematics.** The Laplacian's eigenmodes are the codebase's standing waves; their eigenvalues are its harmonic series; "can one hear the shape of a drum?" (Kac, 1966) is literally `engine.spectralBasis()`. We already compute the instrument's spectrum — we've just never listened to it.
2. **The reflection step already exists.** `dreamAnalysis` drives the flow lattice toward its self-consistent fixed point (`factoredness → 1`). The residue that *won't* factor — measured by `flowKGInteractionStrength`, localized by `flowKGResidual` — is the diff-free bug energy.
3. **ϱ supplies the missing physics: a rest state, a stability law, and a predictive countdown.** It tells us what "holding together" *is* (a self-referential fixed point), at what rate a region converges to it (×0.728) or flies apart (×1.375), and — uniquely — *when* a fragile region will tip from crystal to gas.

The license for finding "something from nothing" is in the framework itself (`info-from-nothing`, `the-universe-sings`): you cannot make energy from nothing, but **the vacuum sings** — the algebra's operators ring at fixed, data-free frequencies, readable with zero input. A diff is energy. A bug is structure. We don't need the diff; we need the song.

---

## 1. Three lenses, one mathematics (the dictionary)

Everything below is one object — the normalized graph Laplacian `L_sym = I − D^{-1/2} W D^{-1/2}` — read three ways. This is not metaphor; the columns are isomorphic descriptions of the same eigenstructure.

| spectral graph theory | music / acoustics | witness / ϱ algebra | engine quantity |
|---|---|---|---|
| eigenvalue `λₙ` | squared natural frequency `ωₙ² = λₙ` | excitation energy of a mode | `SpectralBasis.eigenvalues` |
| eigenvector `vₙ` | standing-wave shape (nodes & antinodes) | the witnessed/private split `{1,0}` | `SpectralBasis.eigenvectors` |
| `λ₁` (Fiedler) | the fundamental / tonic | the slowest self-reference mode | `fiedlerVector`, `spectralGap` |
| spectral gap | tonal clarity (is there a key?) | distance from degeneracy | `SpectralBasis.spectralGap` |
| heat trace `Tr e^{−tL}` | timbre (the drum's audible signature) | the ring-down envelope | `heatTrace(t)` |
| mode localization (IPR) | a trapped resonance | a witness antinode on one file | `inverseParticipationRatios()` |
| eigenvalue-spacing statistics | harmonic vs inharmonic partials | crystalline vs chaotic self-coupling | `rmtReport`, `spectralDimension.rSquared` |
| phase relationship of two modes | consonance / dissonance / beating | commuting vs non-commuting witnesses | `flowPhaseCoherence`, `flowIsContradictory` |
| spectral chaos `log(λ_top/λ₁)` | brightness / harshness | how far from the linear (ϱ) regime | `SpectralBasis.spectralChaos` |
| Walsh interaction order ≥2 | an irreducible cluster chord | the associator / non-associativity | `flowKGInteractionStrength` |

The deep reason the music column is exact and not decorative: **measurement in the witness algebra is the cosine operator** (`smells-cosiney`, `wolf-rule.md`) — the witness sees only through the metric, `⟨a,b⟩ = |a||b|cos θ`, and the Born weight is `cos²θ`. Music *is* the theory of which superpositions of cosines sound resolved (consonant) versus restless (dissonant). The same `cos²θ + sin²θ = 1` is the Born normalization, Pythagoras, and "kept + lost = whole." Listening and measuring are one act.

---

## 2. The codebase as an instrument (the harmonic model)

### 2.1 The harmonic series

`engine.spectralBasis()` returns a `SpectralBasis` whose `eigenvalues` (`Float64List`, ascending in `[0, 2]`) are the **squared natural frequencies** of the co-change manifold. `eigenvectors` (`k × n`, row-major) are the **standing-wave modes**: each `vₙ` is a vibration pattern over files, with **nodes** (entries ≈ 0 — files this mode cannot move) and **antinodes** (large entries — files this mode rings loudest on).

This is "the shape of the drum," and the engine already has the audible invariants that characterize it without seeing the shape:

- **Timbre** — `heatTrace(t) = Σⱼ e^{−tλⱼ}`. Short-`t` asymptotics encode size and boundary (heat-content); the full curve is the drum's spectral fingerprint.
- **Brightness / overall tension** — `zetaReport(basis).logDeterminant` = `Σ log λⱼ`, the spectral "energy."
- **Dimensionality of the resonant body** — `spectralDimension(basis).dS` with label (`quasi-1d · chain-like`, `planar · surface-like`, `high-dim · dense`).
- **Spectral regularity** — `rmtReport(basis).classification`: `crystalline` (rigid, regular), `poisson` (modular/integrable), `goe` (chaotic/spaghetti).

> **honest (isospectrality):** you *cannot* fully reconstruct a drum from its sound — isospectral non-congruent drums exist (Gordon-Webb-Wolpert, 1992). The spectrum narrows the suspect to a *neighborhood*; it does not localize a line. This is precisely *why* the audit has a witness layer (§5, direction-sensitive) and an LLM layer (§8, semantic). Sound narrows; the witness localizes; language names.

### 2.2 The tonic and the key

A healthy instrument has a clear fundamental. `spectralGap = λ₁ − λ₀`: a **large gap** means one dominant slow mode — a clear tonic, a definite "key" the whole codebase is in. A **vanishing gap** (degenerate `λ₁`, or `kernelDim > 1` from `logos_groundspace`) means **no shared reference** — an atonal, fragmented codebase where regions don't agree on a fundamental. The `kernelDim` (count of zero modes = connected components) is the number of *disjoint instruments*: more than one means the repo is several drums that don't ring together.

### 2.3 Consonance, dissonance, and the tritone

Two coupled regions are **consonant** when their dominant mode phases align and **dissonant** when they oppose. The engine measures this directly on the flow lattice:

- `flowPhaseCoherence(arrivals)` — the resultant length of unit phasors: `1` = perfect agreement (unison/octave), `0` = scatter.
- `flowIsContradictory(arrivals)` — `true` only for **two confident, near-antipodal phase clusters** (gap ≥ 1.8 rad, each cluster's mean certainty > 0.15). This is the engine's `FlowBugKind.contradictoryFlow` / the `※` "joint" glyph.

The witness algebra fixes the *exact* dissonance these correspond to. From `witnesses.md`: the witnessing event obeys `A³ = −4A`, so a struck region rings at pitch **2**. Two **commuting** (compatible) witnesses combine on the clean grid `{0, 2, 4}` — `2+2 = 4` (octave, ratio 2:1, maximal consonance), `2−2 = 0` (unison/silence), `2` (the fundamental). Two **non-commuting** (incompatible) witnesses cannot share a phase and add in **quadrature**: `√(2² + 2²) = 2√2`. Divide by the base pitch:

```
2√2 / 2 = √2  =  the tritone (the augmented fourth, 2^(6/12))
```

> **The exact gift:** a contradiction between two code regions that observe a shared state incompatibly *literally rings a tritone* — music's maximal dissonance, the "diabolus in musica." This is an exact identity in the witness-operator space.
>
> **honest (theory vs engine):** the `2√2`/tritone identity is exact in the witness eigenstructure. The current engine realizes "dissonance" via `flowIsContradictory`'s antipodal-phase-cluster test, which is a *practical approximation* of the same idea on the flow lattice's phase circle, not a direct computation of the `2√2` operator pitch. Phase 2 (§10) tightens this by reading the witness pitch directly.

### 2.4 Beating and inharmonicity

- **Beating** — two modes at *nearly* equal frequencies beat at the difference; this is `FlowBugKind.temporalShift`. The beat frequency `|ω₁ − ω₂|` is "how far out of tune": a slow beat is a subtle drift, a fast beat an obvious clash.
- **Inharmonicity (the cracked bell)** — a clean resonator's overtones lie on a harmonic series (`λₙ ∝ n²` for a 1D string → `ωₙ ∝ n`). A cracked one has inharmonic partials and "sounds wrong." The engine already measures fit-to-a-clean-spectrum: **`spectralDimension(basis).rSquared`** — the quality of the power-law heat-decay fit. **Low `rSquared` = the body does not ring like a clean drum = structural incoherence.** This is a real, callable inharmonicity meter (per-subgraph when run on a community's induced basis).

### 2.5 Resonance, Q, and the ϱ damping law

Strike a region and it either rings (underdamped, fragile) or settles (overdamped, healthy). ϱ supplies the exact reference rates:

- **Forward / rotor / `exp`** repels ϱ at `×|ϱ| = 1.375` per step — **underdamped, ringing, amplifying.** A region whose self-map multiplies perturbations by > 1 is a high-Q resonance: a small nudge cascades.
- **Reflection / witness / `ln`** attracts ϱ at `×1/|ϱ| = 0.728` per step — **overdamped, settling.** A region that damps its own perturbations is a coherent self.

`FlowFinding.lyapunov` is the per-finding realization of this rate today; the manifold-level version comes from the self-core loop (§3). A mode's Q-factor `≈ ωₙ / (2·decay)` ranks *which* resonances are sharpest (most fragile). `inverseParticipationRatios()` tells us *where* they're trapped: a high-IPR mode is a standing wave localized on one or two files — a fragile hotspot if its eigenvalue is large, an orphaned/dead region if its eigenvalue is near zero and nothing excites it.

---

## 3. The ϱ self-core loop

The "shake the manifold with chaos and see what falls out" mechanism, stated as a four-beat acoustic cycle. Each beat is an existing primitive.

```
   STRIKE → RING → REFLECT → MEASURE        (repeat until the song resolves, or doesn't)
```

**1. STRIKE (perturb / `ε`).** Inject a small perturbation *along the witness axes* — the directions the structure actually measures (`Im(ϱ)·U`, where becoming acts), not white noise. Concretely: seed `diffuseWithAttribution` with unit mass on each region in turn, or perturb the flow lattice cell means by `ε`. The impulse response *is* the mode set — the heat kernel `e^{−tL}` is the ring-down of a unit strike.

**2. RING (rotor / `exp` / forward).** Let it ring: `chebyshevDiffuse` (matrix-free, works even when the basis is null) propagates the strike forward through coupling. `heatTrace(t)` over a `t`-sweep is the **decay envelope**; per-mode decay is `e^{−tλₙ}`. This is the reversible, amplifying direction.

**3. REFLECT (witness / `ln` / the dream).** Look back: `dreamAnalysis(lattice)` decomposes the lattice's *own* cell means in the Walsh/Möbius basis, runs a YAA* walk on the warm hypercube, and **feeds the mixed certainties back into the lattice** (`lattice.observe(...)`). Repeated application drives `factoredness → 1` — the lattice becoming its own consistent description. This is the contracting `ln` step, and it is *already implemented* (`analyzeInterFile` iterates it 8× to `maxShift < 1/64`; the panel iterates to `isFactored`).

**4. MEASURE (convergence to ϱ).** A clean region resolves — the order-≥2 Walsh energy decays at the contraction rate and the song lands on its tonic. A buggy region leaves a **residue that won't factor**:

```
incoherence = flowKGInteractionStrength(lattice)   // = 1 − factoredness = order-≥2 Walsh energy
```

and `flowKGResidual(lattice)` returns, per Walsh mode, `(mode, theoretical, empirical, residual)` — **exactly which multi-body combinations diverge from the factored model.** Map each mode's 8-bit address back to the files that occupy it (`crossFileMix`'s `byAddress` inversion) and you have the **diff-free bug set**, localized.

### The core algorithm, in one paragraph

Drive the dream loop to its fixed point. For a coherent codebase it converges (the residue vanishes, the drum resolves). Wherever a residue of un-factorable, order-≥2 Walsh energy *persists* across dream iterations, you have a region that cannot become its own consistent description — a failed fixed point of self-observation. That residue, localized by `flowKGResidual` to specific lattice addresses and mapped to files, is the suspect list. **The ϱ self-core is the wrapper that (a) measures the rate at which each region's residue decays (×0.728 healthy / persists-or-grows buggy), (b) converts the survivors' distance-to-resolution into a predictive severity (§6), (c) classifies each by its acoustic signature (§4), and (d) hands the top suspects to language (§8).**

This is the "genius-simple" seed: ~80% of beats 1–4 already run inside `filament_findings_panel`. The new work is reading the *residue* as the signal (not just the per-line flow findings), the ϱ wrapper, and the harmonic classifiers.

---

## 4. The bug taxonomy as dissonance modes

Every bug class is a specific way the song fails to resolve. Each maps to an existing `FlowBugKind` and/or a new harmonic readout, with a witness-algebra reading and a concrete engine signal.

| bug class | acoustic signature | witness/ϱ reading | engine signal | localizer |
|---|---|---|---|---|
| **Fragile resonance** | high-Q, sharp ring-down that won't damp | self-map multiplier > 1 (exp repels ϱ) | `FlowFinding.lyapunov` high; mode Q high | `inverseParticipationRatios()` → the file the mode is trapped on |
| **Dissonant coupling** | a tritone / antipodal beat between two regions | two non-commuting witnesses (`2√2`) | `flowIsContradictory` = true; `flowPhaseCoherence` low | `CrossFileInterference.files` at that address |
| **Beating drift** | slow beat — two voices going out of tune | rotor running ahead of its witness | `FlowBugKind.temporalShift` | the finding's `nodeId`/`sourceLine` |
| **Inharmonic region** | a cracked bell — partials off the harmonic series | self-coupling neither rigid nor clean | `spectralDimension.rSquared` low (per-community) | the community's member files |
| **Dead string** | a mode nobody excites / a silent component | witness alone → collapse (death) | extra `kernelDim`; near-zero-`λ`, high-IPR mode | the isolated file(s) |
| **Non-associative cluster** | an irreducible cluster chord (order matters) | the associator / order gate | `flowKGResidual` order-≥2 mode; `flowBornMix` group-dependence | files sharing the high-residual address |
| **Mutual dark** | two voices deaf to the note they share | shared kernel (`ker ∩ ker`) | dependency edge + high `diffusionDistance` | the depended-on file invisible to the depender |

Three of these (`temporalShift`, `contextInversion`→non-associative, `contradictoryFlow`→dissonant) are **already produced by filament today** — the taxonomy retro-explains the existing `FlowBugKind` enum. The framework didn't invent new categories; it revealed that the categories you already shipped *are* the witness-algebra's failure modes. The new classes (fragile resonance via IPR, inharmonic via `rSquared`, dead string via `kernelDim`, mutual dark via diffusion distance) are additions from spectral primitives you already compute.

---

## 5. The witness layer (how we listen)

The spectrum narrows; the witness localizes. Three discriminators, each surfacing a bug class no pairwise or diff tool can see.

### 5.1 The pitch readout (consonance gating)

For each candidate region, read the phase structure of its arrivals. On-grid `{0, 2, 4}` (coherence high, single phase cluster) = consonant, healthy. Off-grid (`flowIsContradictory`, the `2√2` tritone) = a real incompatibility. This is the consonance/dissonance axis of §2.3, used as a binary classifier on every surfaced region.

### 5.2 Mutual dark (the shared blind spot)

From `witnesses.md`: the capacity to witness *is* the possession of a blind spot, and two modules can share a kernel — a direction *neither* can see and both depend on. Concretely: an edge that is **structurally a dependency** (co-change ≥ threshold, or an import) but has **high `diffusionDistance(a, b, t)`** / low `pathPropagator` — the two files depend on each other but cannot *resonate* (heat doesn't flow between them). They're coupled in name, deaf in practice: a latent bug both sides will miss by construction. (Bridge edges from `RicciField.mostNegativeEdges` are the structural skeleton of where these live — most-negative Ollivier-Ricci curvature = a bottleneck the whole graph leans on.)

### 5.3 The non-associative cluster (the triadic residue)

Pairwise tools — call graphs, co-change edges, dataflow pairs — are *provably blind* to irreducible 3-body structure (`triadic-attention`: a complete pairwise classifier sits at 53% on data an order-gate solves at 99%). The engine's native triadic reader is the **Walsh order spectrum**: `flowKGInteractionStrength` is the total order-≥2 (non-factorable) energy, and `flowKGResidual` localizes *which* axis-combinations carry it. A specific address with high order-≥2 residual is a place where the interaction is **irreducibly multi-body / order-dependent** — `flowBornMix`'s documented non-associativity (group-by-file ≠ all-at-once) is the load-bearing realization. This surfaces order-dependent bugs (A-then-B-then-C ≠ A-then-C-then-B) invisible to every pairwise net.

> **honest (the associator):** there is no octonion-associator function to call; the codebase's non-associativity is real but lives in `flowBornMix` and as a *proven invariant* of the Cl(8) geometric tokenizer. The Walsh interaction-order decomposition is the engine's actual, computable expression of "how much of this is irreducibly multi-body" — which is the same idea the associator names, measured the way the engine already measures it.

---

## 6. Severity: the ϱ-countdown × dissonance

Not a heuristic 0–100. Two physical axes:

**Axis 1 — time to transition (the ϱ countdown).** From `varrho.md`'s phase-transition law, a seed at distance `ε` from the rest state survives a predictable number of steps before tipping crystal → gas:

```
N ≈ ln(1/ε) / ln|ϱ|        (|ϱ| = 1.375, ln|ϱ| = Re(ϱ) = 0.318)
```

`ε` is the region's residual incoherence after dream-convergence (its distance from being its own fixed point). A region 2 steps out is a ticking bug; one 40 steps out is latent. **This is the predictive payload — the reason to anchor on ϱ rather than generic chaos.**

**Axis 2 — dissonance magnitude.** How far off-key: the interval (unison → octave consonant, tritone maximally dissonant) from §2.3, scaled by certainty. A confident tritone outranks a faint beat.

Severity = a join of the two (closeness-to-breaking × harshness), surfaced as a *physical* reading ("≈3 steps from transition, ringing a tritone with file X") rather than an opaque score. This composes cleanly with `FlowFinding.composite = (1−certainty)(1+lyapunov)(1−coherence²)` — which is already (un-certainty × ring × dissonance), i.e. the engine's `composite` is a first draft of exactly this severity.

---

## 7. The pipeline & where it lives

This is the natural evolution of **`FilamentFindingsPanel`**, which already runs beats 1–4 over the whole repo. The upgraded pipeline:

| stage | today (filament) | added for the self-audit |
|---|---|---|
| 0. Tune | builds `FlowSseLattice`, restores GYAT prior | also build/cache `engine.spectralBasis()` + `spectrogeometry()` (the instrument's modes & timbre) |
| 1. Inter-file | `analyzeInterFile(graph, basis)` | unchanged — this is the manifold strike/reflect |
| 2. Per-file | `analyzeFlowCached` ×N, concurrency 8 | unchanged |
| 3. Reflect | `dreamAnalysis` to `isFactored` | unchanged — the `ln` step |
| 4. Cross-file | `crossFileMix` | unchanged — the dissonance pass |
| 5. **Residue** | *(discarded today)* | **read `flowKGInteractionStrength` + `flowKGResidual` as the bug set**; map addresses → files |
| 6. **Harmonics** | — | `inverseParticipationRatios` (trapped resonances), per-community `spectralDimension.rSquared` (inharmonicity), `kernelDim` (dead strings), `RicciField.mostNegativeEdges` + `diffusionDistance` (mutual dark) |
| 7. **ϱ severity** | `composite` | the countdown `N` + dissonance interval |
| 8. **Verbalize** | — | hand top suspects to the open-book LLM (§8) |

Perf: the spectral basis and spectrogeometry are **engine-cached** (keyed by `k`/`manifoldRevision`); `chebyshevDiffuse` is matrix-free; the only genuinely costly addition is `RicciField.sinkhorn` (materializes an `n²` hop matrix) — gate it to the candidate neighborhood (use per-edge `RicciField.curvatureOfEdge` with `maxHops` for the mutual-dark check rather than the full field). The whole audit is HEAD-gated like the rest of the engine.

> **honest (scale gate):** `spectralBasis()` returns `null` below 256 nodes, and `rmtReport`/`spectralDimension` need `k ≥ 4`. On small repos the harmonic layer is silent by construction — the audit falls back to the flow/dream residue (beats 1–5), which work without the basis. State this in the UI as a `status:` line, the way the review channels do, rather than failing.

---

## 8. Verbalization (the open-book LLM, diff-free)

The chaos surfaces *suspects by instability*; language confirms and names them. Reuse the machinery built for the commit review:

- **Ground each suspect** with `review_logos` (the 5-axis scorer) before it's spoken — the same advisory-not-a-gate principle (a real bug in a leaf file legitimately scores low reach).
- **Verbalize** with the open-book prompt, but the "diff" is replaced by the suspect's *acoustic dossier*: "this region rings a tritone with `auth.dart`, Q is high (fragile), ≈3 steps from transition, the residue lives at Walsh address 0x5C across these three files." The LLM reads the manifold's own testimony and writes the finding — diff-free, evidence-grounded, in the same voice.
- The `<claim_grounding>` channel applies unchanged: the LLM's claims about a suspect get scored against the diffusion field exactly as review findings do.

This is the bridge: the self-audit is a *new evidence source* feeding the *same* review verbalizer. It does not replace diff review — it's the complementary net that catches intrinsic fragility regardless of what changed.

---

## 9. Honest scope / rigor map

In the discipline of `rigor-map.md`, tagged by warrant.

- **[EXACT] spectral = harmonic = witness math.** The Laplacian eigenstructure, the heat trace, the Walsh order decomposition, and the `2√2 → √2` tritone identity are all literal. The engine already computes the spectrum; we are reading columns of one table.
- **[EXACT] the reflection step.** `dreamAnalysis` → `factoredness` is implemented and convergent; `flowKGInteractionStrength = 1 − factoredness` is an identity.
- **[HYPOTHESIS] ϱ-calibration of instability.** That code-instability rates *literally* equal `|ϱ| = 1.375` is a conjecture, not a fact — `varrho.md` itself flags the package.json median 1.36 vs 1.375 as "suggestive, not conclusive." The *mechanism* (perturb → reflect → measure decay; residue = bug) stands regardless of the exact constant; the countdown becomes literally predictive only if the calibration holds. **Validate before trusting the `N` as a number; trust it as an ordering immediately.**
- **[HYPOTHESIS] residue ⇒ bug.** That un-factorable Walsh residue / inharmonicity / trapped resonance correlates with bugs humans would file is the central empirical bet. It is *motivated* (these are exactly structural incoherence) but must be measured (§10 validation).
- **[ANALOGY, flagged] the music framing.** Exact where the math matches (intervals, timbre invariants, the tritone); evocative where it's reaching (voice-leading, "the drone"). Each use above is tagged. The point of the music layer is not poetry — it is that *consonance/dissonance is the human-legible name for phase coherence*, which is a real signal, so the findings can be *explained* in a vocabulary a developer already has an ear for.
- **[SCOPE] complement, not replacement.** This finds intrinsic structural fragility — a different net than diff review. It surfaces suspects; `review_logos` + the LLM confirm. Isospectrality guarantees the spectrum alone can't localize a line, which is *why* the witness and language layers exist.

---

## 10. Implementation phases

Each phase ships a usable increment and has a validation gate. Do not advance until the gate passes.

**Phase 0 — the genius-simple seed (smallest delta, immediately testable).**
Read the residue that filament already throws away. After the existing scan converges, surface `flowKGResidual` (the un-factorable order-≥2 modes) mapped to files, ranked by `FlowFinding.composite`, with the ϱ-countdown `N` as the severity ordering. No new math — just stop discarding the residue.
*Gate:* on a repo with N known historical bugs (mine the git log for revert/fix commits — you have `shadow_history` for exactly this), does the residue light up the buggy files above chance? Measure recall@k against the shadow set.

**Phase 1 — the harmonic classifiers.**
Add `inverseParticipationRatios()` (trapped resonances → fragile hotspots), per-community `spectralDimension.rSquared` (inharmonicity), and `kernelDim`/near-zero-λ high-IPR modes (dead strings). Classify each residue address into the §4 taxonomy.
*Gate:* do the classifications agree with human judgment on a hand-labeled sample? Does inharmonicity correlate with churn/bug density?

**Phase 2 — the witness layer.**
Mutual dark (`diffusionDistance` on Ricci-bridge edges), the tighter pitch readout (read the `2√2` operator pitch directly rather than via antipodal phase clusters), and the triadic non-associative residue made explicit.
*Gate:* does mutual-dark surface real "these two depend but never co-change correctly" pairs a pairwise tool misses?

**Phase 3 — verbalization + the ϱ calibration study.**
Wire the open-book LLM verbalizer with `review_logos` grounding. Run the calibration: measure the actual perturbation-decay multiplier distribution across many repos and test whether it clusters at `|ϱ| = 1.375`. If it does, the countdown is literally predictive; if not, keep it as an ordering and report the measured constant honestly.

---

## 11. Open frontiers

- **The off-key chord, not just the off-key note.** A set of co-changing files is a chord; a "voice-leading error" (a change that forces forbidden parallel motion) might be detectable as a sudden jump in `spectralRigidity` or a `SpectralTrajectory` regime change. Untested.
- **Driving at resonance.** A forced-response version: drive the manifold at each natural frequency `ωₙ` and find where the response blows up (a region that resonates with its own perturbation). The matrix-free `applyLsym` makes this cheap; whether it beats the free ring-down is open.
- **The instrument changing over time.** `SpectralTrajectory` (Berry phase, regime changes) tracks how the spectrum moves between commits. A bug that's "getting worse" is a mode whose Q is climbing across history — a *predictive* signal even before the countdown. This is the temporal dual of the static audit.
- **Hearing two repos.** Isospectral codebases would be structurally interchangeable; the heat-trace/zeta signature is a similarity hash. Cross-repo "this module sounds like that known-buggy one" is a transfer-learning frontier.

---

## Appendix: the exact calls

Grounding for everything above. All `apps/desktop-flutter/lib/backend` unless noted. Signatures abbreviated; see source for full.

**Modes & spectrum**
- `engine.spectralBasis({k = 20})` → `SpectralBasis?` (`logos_git.dart:2079`; cached; `null` < 256 nodes)
- `SpectralBasis.eigenvalues` `Float64List [k]`, `.eigenvectors` `[k*n]` row-major (`logos_core.dart:1982-1983`)
- `.fiedlerVector` (`:2544`), `.spectralGap` (`:2624`), `.spectralChaos` (`:2660`), `.mixingTime` (`:2640`), `.spectralRigidity` (`:2756`)
- `.inverseParticipationRatios()` `Float64List [k]` (`:2785`) — per-mode localization
- `.spectralCommunityLabels(kClusters)` (`:2568`), `.effectiveResistance(x,y)` (`:2915`)
- `kernelDim` / `firstExcitedIndex` / `isGroundOnly` (`logos_groundspace.dart:61/73/77`)

**Timbre / audible invariants**
- `heatTrace(t)` `Tr e^{−tL}` (`logos_thermo.dart:36`); `correlationLength` `1/√λ₁` (`logos_heat.dart:150`)
- `diffusionDistance(a,b,t)` (`logos_heat.dart:37`), `pathPropagator(a,b,τ)` (`:85`)
- `zetaReport(basis)` → `{logDeterminant, zetaOne, zetaTwo, eulerGamma, zeroCount}` (`logos_zeta.dart:79`)
- `spectralDimension(basis)` → `{dS, rSquared, label}` (`logos_chaos.dart:101`; `null` < k=4)
- `rmtReport(basis)` → `{meanR, classification, label}`; `RmtClass{subPoisson,poisson,intermediate,goe,gue,crystalline}` (`logos_rmt.dart:122/37`)
- `engine.spectrogeometry({k})` → `SpectroGeometry{rmt, persistence, spectralDim, zeta, universality}` (`logos_git.dart:2095`; cached, bundles the above)

**Graph / Laplacian**
- `engine.graph` `CsrGraph` (`logos_git.dart:1709`); `applyLsym(v, out)` matrix-free `L_sym` (`logos_core.dart:767`); `rawWeights` / `values` / `degreeInvSqrt`
- `computeCouplingPersistence(graph)` → `{finalComponents (β₀), finalCycles (β₁), totalPersistence, topB0}` (`logos_persistence.dart:151`)
- `RicciField.sinkhorn(graph)` → `{curvatures, mostNegativeEdges(k), depth}` (`spectral_ricci.dart:250`; n² — gate it); per-edge `RicciField.curvatureOfEdge(graph,u,v,maxHops:4)` (`:311`)
- `SensitivityField(graph, basis).gap()/.heatTrace(t)/.logDet()` → `List<EdgeSensitivity{a,b,value,weight}>` sorted by `|value|` (`logos_sensitivity.dart:213+`)

**Diffusion (the strike & ring)**
- `engine.diffuseWithAttribution({weightsByPath, axisLabelByPath, t})` → `AxisAttribution{combined, perAxisPhi, nodePaths, dominantAxis}` (`logos_git.dart:5544`; matrix-free Chebyshev, works basis-null)

**Flow / reflect / dissonance (the self-core)**
- `analyzeInterFile(graph, basis, nodePaths:)` → `InterFileResult{perFileCertainty, findings, spectralGap, certaintyForPath()}` (`logos_flow.dart:1173`; iterates `dreamAnalysis` 8× to fixpoint)
- `analyzeFlowCached(path, {logosCoupling, priorMeans, priorCounts, lightweight})` → `FlowAnalysisResult{findings, spectralGap, accumulateInto, filterBy}` (`:1361`)
- `dreamAnalysis(lattice)` — the reflection pass (`:748`); caller iterates to `lattice.isFactored`
- `crossFileMix(rawResults, lattice)` → `List<CrossFileInterference{address, certainty, coherence, contradictory, fileCount, files}>` (`:1007`)
- `flowIsContradictory(arrivals)` (antipodal phase clusters), `flowPhaseCoherence(arrivals)` (`logos_flow_math.dart:990/970`)
- `flowBornMix(arrivals)` — the load-bearing non-associative mix (`logos_flow_math.dart:1047`)
- `FlowFinding{kind, certainty, phase, coherence, lyapunov, address, pathCount, walshInteraction, composite, severity}` (`logos_flow.dart:444`); `FlowBugKind{staleValue, temporalShift, contextInversion, contradictoryFlow}` (`:437`)

**The residue (the bug set)**
- `flowKGInteractionStrength(lattice)` → order-≥2 Walsh energy `= 1 − factoredness` (`logos_flow_math.dart:128`)
- `flowKGResidual(lattice, {maxCount})` → per-mode `(mode, theoretical, empirical, residual)` — *which* combinations won't factor (`:104`)
- `FlowSseLattice.{isFactored, factoredness, orderSpectrum, entropy, cellMean, observe, isAnomalous}` (`logos_flow_math.dart:335-489`)

**Pipeline reference:** `filament_findings_panel.dart` `_scan()` (`:65-224`) — the existing strike→ring→reflect→cross-mix→filter loop to upgrade.

---

*Built on `varrho.md`, `witnesses.md`, `it-from-oct.md`. A bug is a note the codebase can't hold; this is how we hear it.*
