<!--
SPDX-FileCopyrightText: 2026 Woflo Labs
SPDX-License-Identifier: LicenseRef-WLCSL-1.0
See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.
-->

# Spectral Context Projection

## The Problem

The AI context engine allocates a finite character budget across four
producers (file\_context, file\_metadata, relevance\_neighborhood,
execution\_flow). The current allocation uses an algebraic partition
on two intermediate scalars (coherence, yield) that sums to unity for
three producers — but execution\_flow is bolted on as an additive
urgency `(diffLen/10000).clamp(0.1, 0.6)` that breaks the partition,
distorts softmax normalisation, and ignores every signal the spectral
engine computes.

The fix: replace the scalar partition with a geometric projection from
the heat kernel's spectral energy distribution directly onto the
producer simplex. One geometric object, zero free parameters, four
producers in a closed partition of unity.

---

## Theoretical Foundation

### 1. The Heat Kernel as Attention Field

The normalised graph Laplacian `L = I − D^{−½}WD^{−½}` on the
co-change graph has eigendecomposition `L = UΛU^T` with eigenvalues
`0 = λ₀ ≤ λ₁ ≤ ⋯ ≤ λ_{k−1} ≤ 2` and orthonormal eigenvectors
`u₀, …, u_{k−1}`. The engine computes this via Lanczos factorisation
in `SpectralBasis.fromGraph` (logos\_core.dart:1945) with default
`k = 20` eigenpairs.

The heat kernel operator at time `t` is:

```
K(t) = exp(−tL) = U · diag(e^{−tλ₀}, …, e^{−tλ_{k−1}}) · U^T
```

Applied to a source distribution `ρ` (the diff's footprint on the
graph, built by `DiffProbe.sourceWeights` in logos\_git\_probe.dart:58),
the diffused field is:

```
φ(t) = K(t)ρ = Σⱼ cⱼ e^{−tλⱼ} uⱼ
```

where `cⱼ = ⟨uⱼ, ρ⟩` are the source's spectral coefficients,
obtainable via `SpectralBasis.project(rho)` (logos\_core.dart:2120) in
`O(kn)`.

This field `φ(t)` IS the attention the AI review needs — it encodes
how the diff's influence propagates through the repository's coupling
structure at scale `t`. The diff attention engine already uses it to
rank hunks by `φᵢ` (logos\_diff\_attention.dart:6–15). The context
engine should read the same field.

### 2. Spectral Energy and the Partition Function

The **source-weighted partition function** (logos\_thermo.dart:52–59)
measures total heat retention:

```
Z(ρ, t) = ρ^T K(2t) ρ = Σⱼ cⱼ² e^{−2tλⱼ}
```

(The factor `2t` arises because `ρ^T exp(−tL) exp(−tL) ρ = ρ^T exp(−2tL) ρ`.)

Each summand `Eⱼ = cⱼ² e^{−2tλⱼ}` is the **spectral energy** in
mode `j` — how much of the diff's self-correlation survives in that
eigenmode at time `t`. The mode's eigenvalue determines its character:

- **Low `λⱼ`** (near `λ₁`): slow decay, global reach. These modes
  carry long-range correlations across the entire graph. Energy here
  means the diff has cross-module effects that propagate far from the
  source.

- **High `λⱼ`** (near `λ_max`): fast decay, local detail. These modes
  oscillate rapidly and carry fine-grained, within-file structure.
  Energy here means the diff is localised, affecting tightly-coupled
  neighbours.

- **Mid `λⱼ`**: intermediate reach. Module boundaries, structural
  interfaces, architectural seams. Energy here means the diff operates
  at the mesoscale — touching structural edges between components.

This spectral energy decomposition is the natural basis for attention
allocation. Each eigenmode's energy tells us what *kind* of context
the review needs, and at what *scale*.

### 3. The Bernstein Projection

To partition spectral energy into producer basins, we need a smooth
partition of unity on `[0, 1]`. The **Bernstein basis polynomials** of
degree 2 provide exactly this:

```
B₀(s) = (1 − s)²         ← global basin
B₁(s) = 2s(1 − s)        ← meso basin
B₂(s) = s²               ← local basin
```

These satisfy:

```
B₀(s) + B₁(s) + B₂(s) = (1−s)² + 2s(1−s) + s² = 1    ∀ s ∈ [0,1]
```

Each eigenmode has a **spectral address** `sⱼ = λⱼ / λ_max ∈ [0, 1]`
— its position in the normalised spectrum. The Bernstein polynomials
evaluated at `sⱼ` give smooth weights that determine how mode `j`'s
energy distributes across the three basins:

```
r_nbhd = Σⱼ Eⱼ · B₀(sⱼ) / Z = Σⱼ Eⱼ · (1 − sⱼ)²       / Z
r_meta = Σⱼ Eⱼ · B₁(sⱼ) / Z = Σⱼ Eⱼ · 2·sⱼ·(1 − sⱼ)   / Z
r_ctx  = Σⱼ Eⱼ · B₂(sⱼ) / Z = Σⱼ Eⱼ · sⱼ²               / Z
```

where `Z = Σⱼ Eⱼ = Z(ρ, t)`.

By the Bernstein identity, `r_nbhd + r_meta + r_ctx = 1` exactly.
No rounding, no renormalisation. The partition is algebraically closed.

**Why Bernstein and not hard bands?** Hard spectral band boundaries
(e.g. "below median = global, above = local") introduce discontinuities
at the boundary eigenvalues, making the allocation unstable under small
perturbations of the graph. Bernstein polynomials are `C^∞` and form
the unique partition of unity on `[0,1]` that is symmetric under
degree-elevation — a property the Möbius stack in `logos_mobius.dart`
exploits when projecting between lattice levels. The graded projection
`gradedProjectProduct` (logos\_mobius.dart:339–363) uses the same
principle: factor a joint lattice 2^[a]×2^[b] into marginals and
cross-terms via smooth weighting, not hard cutoffs. The Bernstein
partition is the continuous-spectrum analogue of this discrete
factorisation.

**Connection to existing heat kernel machinery.** The partition function
`Z(ρ, t)` is already computed by `SpectralThermo.partitionFunction`
(logos\_thermo.dart:52). The free energy `F = −log Z` is already used
for anomaly detection. The Bernstein partition adds three weighted
variants of the same sum — same `O(k)` cost, same numerical path, just
three different weight functions on the eigenvalues.

### 4. Structural Concentration and the Flow Basin

The Bernstein partition accounts for three producers. The fourth —
execution\_flow — measures **structural surprise**: whether the diff
excites an anomalous resonance in the graph rather than spreading
smoothly.

The **spectral entropy** of the source projection quantifies this:

```
pⱼ = Eⱼ / Z(ρ, t)
H  = −Σⱼ pⱼ ln pⱼ
```

This is `SpectralThermo.spectralEntropy(rho, t)` (logos\_thermo.dart:87).
When the diff's energy distributes evenly across modes, `H → H_max = ln k`
and the diffusion is smooth — no structural anomaly, low flow need.
When energy concentrates in a few modes, `H → 0` and the diff excites a
resonance — a specific structural feature of the graph traps attention.

The **concentration** is the complement:

```
κ = 1 − H / ln(k)    ∈ [0, 1]
```

Concentration alone doesn't determine structural risk. A concentrated
source on a robust graph (large spectral gap) is just a focused change.
A concentrated source on a fragile graph (small gap) is a structural
anomaly — perturbations propagate unpredictably through the weak mode.

The spectral gap `λ₁` (accessible via `SpectralBasis.spectralGap`,
logos\_core.dart:2060) measures graph robustness. Its reciprocal is the
mixing time `τ_mix = 1/λ₁` — how long it takes the heat kernel to reach
equilibrium. The correlation length `ξ = 1/√λ₁` (logos\_heat.dart:150)
is the characteristic distance over which perturbations propagate.

The **structural risk** `σ` combines concentration with fragility:

```
σ = κ · (1 − λ₁ / λ_ref)
```

where `λ_ref = 1.0` (the gap of a complete graph on the normalised
Laplacian, representing maximum robustness). For connected graphs on
the normalised Laplacian, `λ₁ ∈ (0, 2]`, so `(1 − λ₁/λ_ref)` maps
`λ₁ = 0 → 1.0` (maximally fragile) and `λ₁ ≥ 1 → 0.0` (maximally
robust). This is the same gap normalisation used by the spectrogeometry
engine's crystallinity metric (logos\_spectrogeometry.dart:144), where
tight eigenvalue spacing maps to ordered, predictable structure.

**Why the gap and not universality class?** The universality vector
(logos\_spectrogeometry.dart:114) is a derived fingerprint built from
four lenses (RMT, persistent homology, spectral dimension, zeta).
The gap `λ₁` is the raw geometric invariant those lenses interpret.
Using `λ₁` directly keeps the projection theorem-tight; using the
universality vector would inject operational design choices from the
fingerprinting pipeline. The universality class can modulate *how*
producers spend their budget (e.g. neighbourhood ordering), but the
*allocation* should come from the invariant, not its interpretation.

### 5. The Complete Projection

Combining the Bernstein partition (three basins) with structural
concentration (fourth basin) via complementary scaling:

```
u_flow = σ
u_ctx  = (1 − σ) · r_ctx
u_meta = (1 − σ) · r_meta
u_nbhd = (1 − σ) · r_nbhd
```

Verify:

```
u_flow + u_ctx + u_meta + u_nbhd
  = σ + (1 − σ)(r_ctx + r_meta + r_nbhd)
  = σ + (1 − σ) · 1
  = 1    ∎
```

These four values are the producer urgencies, replacing the current
`urgency()` methods entirely. They feed directly into the Hamilton
apportionment in `AiContextEngine.assemble` (ai\_context\_engine.dart:201)
without softmax normalisation — they already sum to 1.

### 6. Connection to Existing Structures

**Heat kernel ↔ diff attention.** The hunk ranker
(logos\_diff\_attention.dart) and the context allocator now share the
same geometric object: the source projection `c = U^Tρ` and the
diffusion time `t`. The hunk ranker projects the heat kernel onto
per-hunk φ scores for LOD tiering. The context allocator projects the
same kernel onto the Bernstein partition for budget allocation. One
field, two views. When the packer drops a low-φ hunk, its energy is
already in the spectral coefficients — the Bernstein partition
automatically routes its budget contribution to the appropriate basin
(typically neighbourhood, since dropped hunks tend to have
low-frequency character).

**Chebyshev diffusion ↔ projection.** The engine's Chebyshev
expansion `φ(t) = Σ_k c_k(t) T_k(L−I) ρ` (logos\_core.dart:1066)
computes the diffused field without materialising the eigenvectors.
For the Bernstein partition, we need the spectral coefficients
`cⱼ = ⟨uⱼ, ρ⟩` and eigenvalues `λⱼ` directly — which the
`SpectralBasis` already stores. The Chebyshev path serves
large-scale diffusion (n > 10⁴ nodes); the eigendecomposition path
serves the partition (k = 20 terms, always fast). No conflict; both
coexist.

**Born mixing ↔ spectral address.** The Born mixer
(logos\_git.dart:346) combines five axis observations via
`p_mixed = A²/(A² + Ā²)` — a quantum-inspired confidence-weighted
combination. The Bernstein partition is analogous: each eigenmode is
an "observation" of the diff at a specific spectral address, and the
basin weights `B₀, B₁, B₂` are the confidence functions that route
each observation to the correct producer. The Born mixer routes axis
evidence to a fused probability; the Bernstein partition routes
spectral energy to a fused budget allocation. Same structure,
different domain.

**Walsh–Möbius grading ↔ Bernstein grading.** The Walsh spectrum
decomposes a function on 2^[n] into interaction orders via
`walshOrderSpectrum` (logos\_mobius.dart:176). Order 0 = DC component,
order 1 = pairwise, order k = k-body interaction. The Bernstein
partition is the continuous analogue: spectral address `s = 0` is the
DC/global component, `s = 1` is the highest-frequency local component,
and the Bernstein polynomials smoothly grade energy across these scales.
The Walsh transform is the discrete Fourier transform on the hypercube;
the Bernstein partition is the continuous Fourier transform on the
spectral interval. Both decompose a signal into spatial frequencies
and measure energy per scale.

**Thermodynamic grounding.** The source-weighted partition function
`Z(ρ, t)` is the normalising denominator of both the spectral entropy
and the Bernstein partition. The free energy `F = −ln Z` already drives
anomaly detection (logos\_thermo.dart:72). The spectral entropy `H`
already measures information content. The Bernstein partition adds
no new thermodynamic quantities — it re-reads the existing ones through
a geometric lens.

**Spectral trajectory coherence.** The trajectory's `turbulence`
metric (spectral\_trajectory.dart:570) measures how erratically the
spectrum evolves over commits. High turbulence = chaotic development
history = fragile graph. This signal is downstream of `λ₁` (gap
instability implies turbulence) and could modulate the structural
risk `σ` for repos where the trajectory itself is a risk indicator.
Not required for v1, but the projection's `σ` term is the natural
attachment point.

---

## Implementation Plan

### Phase 0: Infrastructure — Spectral Energy Partition Function

**File:** `logos_thermo.dart`
**What:** Add a method to `SpectralThermo` that computes the Bernstein
partition and concentration from a source projection.

```
Extension method on SpectralBasis:

  spectralEnergyPartition(Float64List rho, double t)
    → ({double ctx, double meta, double nbhd, double flow})

  Inputs:
    rho   — source distribution (n-vector from DiffProbe.sourceWeights)
    t     — diffusion time (from LogosDiffusionResult.resolvedT)

  Internals:
    c     = project(rho)                        // O(kn), cached
    λ_max = eigenvalues[k-1]
    Eⱼ    = cⱼ² · exp(−2t·λⱼ)                  // O(k)
    Z     = Σ Eⱼ                                // O(k)
    sⱼ    = λⱼ / λ_max                          // O(k)

    r_ctx  = Σ Eⱼ·sⱼ²          / Z             // O(k)
    r_meta = Σ Eⱼ·2sⱼ(1−sⱼ)   / Z             // O(k)
    r_nbhd = Σ Eⱼ·(1−sⱼ)²     / Z             // O(k)

    pⱼ    = Eⱼ / Z                              // O(k)
    H     = −Σ pⱼ ln pⱼ                         // O(k)
    κ     = 1 − H / ln(k)                       // O(1)
    σ     = κ · (1 − min(spectralGap, 1.0))     // O(1)

    flow  = σ
    ctx   = (1 − σ) · r_ctx
    meta  = (1 − σ) · r_meta
    nbhd  = (1 − σ) · r_nbhd

  Output:
    Named record with the four basin weights.

  Total cost: O(kn) for projection (usually cached), O(k) for partition.
  For k=20, the partition step is 20 multiplies + 20 exponentials +
  60 polynomial evaluations — vanishes against any I/O.
```

Guard rails:
- If `Z < ε` (source has negligible energy — degenerate diff or
  disconnected graph), fall back to uniform `(0.25, 0.25, 0.25, 0.25)`.
- If `k < 3` (fewer than 3 eigenpairs — tiny graph), fall back to
  `(1.0, 0.0, 0.0, 0.0)` (all file\_context, since the graph is too
  small for spectral analysis to be meaningful).
- Exclude `λ₀` from the entropy computation when the graph is
  connected (the zero mode carries no information). Use `j = 1..k−1`.

### Phase 1: Wire Partition into AiContextRequest

**File:** `ai_context_engine.dart`

Extend `LogosDiffusionResult` (or `AiContextRequest`) with the
partition:

```
Add field to LogosDiffusionResult:
  final ({double ctx, double meta, double nbhd, double flow})? partition;

Computed lazily from:
  engine.spectralBasis().spectralEnergyPartition(
    probe.sourceWeightsAsVector(engine),
    resolvedT,
  )
```

This requires `DiffProbe.sourceWeights` (a `Map<String, double>`) to be
converted to a dense `Float64List` aligned with `SpectralBasis.nodePaths`.
Add a helper:

```
Float64List sourceWeightsAsVector(LogosGit engine)
  — maps sourceWeights keys to node indices via basis.pathToId
  — returns n-vector with weights at matching indices, 0 elsewhere
```

The `SpectralBasis.labelProject` method (logos\_core.dart) already
does this mapping for the file-level diffusion. Reuse the same path.

### Phase 2: Replace Producer Urgency Methods

**File:** `ai.dart`

Replace the four producers' `urgency()` implementations:

**Before (current):**
```dart
// FileContextProducer
urgency = _logosYieldOf(probe).coh;

// FileMetadataProducer
urgency = y.dispersion * (1.0 - y.yieldFraction);

// RelevanceNeighborhoodProducer
urgency = y.dispersion * y.yieldFraction;

// ExecutionFlowProducer
urgency = (req.diffText.length / 10000).clamp(0.1, 0.6);
```

**After (spectral projection):**
```dart
// All four producers read from the same partition:
final p = req.logos?.partition;

// FileContextProducer
urgency = p?.ctx ?? 1.0;           // cold-start: all to file context

// FileMetadataProducer
urgency = p?.meta ?? 0.0;

// RelevanceNeighborhoodProducer
urgency = p?.nbhd ?? 0.0;

// ExecutionFlowProducer
urgency = p?.flow ?? 0.0;
```

The urgencies now sum to 1.0 by construction. The Hamilton
apportionment in `AiContextEngine.assemble` still applies (it handles
the integer rounding to char counts), but the softmax normalisation
step becomes a no-op since the inputs are already normalised.

Remove `_logosYieldOf` — it is no longer called from any producer.
The coherence, dispersion, and yield fraction scalars are still
available on `ProbeStats` for diagnostics, but they no longer drive
allocation.

### Phase 3: Measure Template Overhead Dynamically

**File:** `ai.dart`

Replace:
```dart
const _kReviewOverheadChars = 12000;
const _kSynthesisOverheadChars = 9000;
```

With dynamic measurement: assemble the template body (system prompt +
schema + framing) before computing the context budget, and deduct its
actual length.

```
final templateBody = _assembleReviewTemplate(guardrail, customPrompt);
final overhead = templateBody.length;
final rawContextBudget = _maxPromptChars - diffBundle.promptBody.length - overhead;
```

The template assembly is already a pure string function — it just
needs to be called before the budget computation rather than after.
This recovers ~2–4K on light guardrail profiles and eliminates silent
truncation on heavy ones.

### Phase 4: Surface Partition in Diagnostics

**File:** `ai.dart` (command lifecycle logging)

Log the four basin weights alongside existing diagnostics so the
spectral projection's behaviour is observable without debugger
attachment:

```
DiagnosticsState.instance.recordCommandLifecycleEvent(
  type: 'info',
  command: 'ai.context.partition',
  message: 'ctx=${p.ctx.toStringAsFixed(3)} '
           'meta=${p.meta.toStringAsFixed(3)} '
           'nbhd=${p.nbhd.toStringAsFixed(3)} '
           'flow=${p.flow.toStringAsFixed(3)} '
           'σ=${sigma.toStringAsFixed(3)} '
           'κ=${concentration.toStringAsFixed(3)} '
           'H=${entropy.toStringAsFixed(3)} '
           'gap=${spectralGap.toStringAsFixed(4)}',
);
```

### Phase 5: Cold-Start and Degenerate Cases

When the spectral basis is unavailable (repo too small, engine not
warm, or graph disconnected), the projection returns `null` and the
producers fall back to their cold-start defaults:

| Producer | Cold-start urgency | Rationale |
|---|---|---|
| file\_context | 1.0 | Without spectral data, raw file context is the safest bet |
| file\_metadata | 0.0 | Metadata without spectral ranking is noise |
| relevance\_nbhd | 0.0 | Neighbourhood without diffusion is random |
| execution\_flow | 0.0 | Flow analysis without graph structure is guessing |

This matches the current cold-start behaviour (coherence defaults to
1.0 when the engine is absent, sending all budget to file\_context).

For partially-degenerate cases (graph exists but is nearly
disconnected, `λ₁ < ε`):

- The spectral gap approaches 0, so `σ → κ` (full concentration
  risk). If the diff also concentrates energy in a few modes,
  execution\_flow absorbs a large share. This is correct: a
  disconnected graph with concentrated excitation is structurally
  anomalous and needs investigation.

- If the source is uniformly spread (`κ → 0`), then `σ → 0`
  regardless of gap. The Bernstein partition handles allocation.
  On a disconnected graph with uniform source, low-frequency modes
  dominate (the zero modes of each component), sending budget to
  neighbourhood. This is correct: a scattered diff across
  disconnected components needs cross-component context.

---

## Mathematical Properties

### Partition of Unity (Proof)

**Claim:** `u_flow + u_ctx + u_meta + u_nbhd = 1` for all valid
inputs.

**Proof.** By the Bernstein identity on degree-2 polynomials,
`B₀(s) + B₁(s) + B₂(s) = 1` for all `s ∈ [0,1]`. Therefore:

```
r_ctx + r_meta + r_nbhd
  = Σⱼ Eⱼ [sⱼ² + 2sⱼ(1−sⱼ) + (1−sⱼ)²] / Z
  = Σⱼ Eⱼ · 1 / Z
  = Z / Z
  = 1
```

Then:

```
u_flow + u_ctx + u_meta + u_nbhd
  = σ + (1−σ)(r_ctx + r_meta + r_nbhd)
  = σ + (1−σ) · 1
  = 1    ∎
```

### Smoothness

The Bernstein polynomials `Bₘ(s) = C(2,m) · s^m · (1−s)^{2−m}` are
`C^∞` on `[0,1]`. The spectral address `sⱼ = λⱼ/λ_max` is a linear
function of the eigenvalues. The energy `Eⱼ = cⱼ² exp(−2tλⱼ)` is
`C^∞` in `(cⱼ, λⱼ, t)`. Therefore the basin weights `r_ctx, r_meta,
r_nbhd` are `C^∞` functions of the spectral data. Small perturbations
of the graph (adding/removing a file, changing coupling weights)
produce small perturbations of the eigenvalues, producing small
perturbations of the allocation. No discontinuities, no mode-switching.

### Correct Limiting Behaviour

| Regime | Gap | Source shape | σ | Bernstein | Allocation |
|---|---|---|---|---|---|
| Tight coherent diff | large | high-freq | ~0 | r_ctx ≫ | file\_context dominates |
| Scattered cross-module | small | low-freq | moderate | r_nbhd ≫ | neighbourhood dominates |
| Single resonant anomaly | small | concentrated | high | — | execution\_flow dominates |
| Large balanced refactor | moderate | broad | ~0 | balanced | even split |
| Complete graph (K_n) | 1.0 | any | 0 | by source | σ=0, gap kills risk |
| Star graph | small | leaf-concentrated | high | r_ctx | flow + local |
| Disconnected | 0 | component-spread | κ-dependent | r_nbhd | neighbourhood or flow |

### Cost

```
Projection:   O(kn)    — matrix-vector multiply (cached by SpectralBasis.project)
Partition:    O(k)     — k exponentials + 3k polynomial evaluations + k logs
Total:        O(kn)    — dominated by the projection, which is already computed
                          for hunk diffusion (logos_diff_attention.dart)
```

For `k = 20` and `n = 500` (typical repo), the partition step is
~200 FLOPs. The projection is ~10,000 FLOPs but is already cached
from the diffusion pass. Net additional cost: effectively zero.

---

## Files Modified

| File | Change | Lines affected |
|---|---|---|
| `logos_thermo.dart` | Add `spectralEnergyPartition` method | New extension method (~40 lines) |
| `logos_git_probe.dart` | Add `sourceWeightsAsVector` helper | New method (~15 lines) |
| `ai_context_engine.dart` | Add `partition` field to `LogosDiffusionResult` | ~5 lines |
| `ai.dart` | Compute partition in `_runLogosDiffusion` | ~10 lines |
| `ai.dart` | Replace 4 producer `urgency()` methods | ~20 lines changed |
| `ai.dart` | Remove `_logosYieldOf` | ~15 lines removed |
| `ai.dart` | Dynamic template overhead measurement | ~10 lines changed |
| `ai.dart` | Diagnostic logging | ~10 lines added |

Total: ~70 lines added, ~35 lines removed, ~35 lines changed. The
projection is a small, surgical change that replaces scattered scalar
formulas with a single geometric computation. No new files, no new
dependencies, no new data structures beyond a 4-field record.
