# Test-Suite System Logic: Research Report

**Date:** 2026-07-17  
**Scope:** Research only (no code changes in the original analysis).  
**Goal:** Design principles for a suite that can eventually **black-box accept no-taste fixes**, stay **anti–regression-spam**, **keep improving**, and **not punish experimentation**.

---

## 1. What you already have (baseline for the research)

The Flutter suite is not a typical unit/regression pile. From the tree and docs, it already implements several research-grade ideas:

| Pattern | Where it shows up | Research name |
|--------|-------------------|---------------|
| Seeded generators + tape shrink + corpus | `test/support/prop.dart` | Hypothesis/Conjecture-style PBT |
| Coverage requirements on generators | `requireCoverage` in prop harness | Generator honesty / partition coverage |
| Metamorphic relations | `engine_metamorphic`, `csr_rank1_metamorphic` | Metamorphic testing (Chen et al.) |
| Differential oracles | hostile gitconfig, cross-OS, POSIX fault | Differential testing (McKeeman) |
| External ground truth | `diff_oracle_laws` vs real `git` | Specified / N-version oracle |
| Crash/fault models | torn write, concurrency chaos, barriers | Fault injection / consistency testing |
| Structural laws + ratchets | `source_laws_test` + `law_corpus` | Architectural fitness functions / debt ratchets |
| “Laws not goldens” | fuzz docs + oracle laws | Property oracles vs characterization |

The hardening plan already documented the right diagnosis: **reach and teeth**, not lack of cleverness. That matches the literature: more tests ≠ stronger oracles.

---

## 2. The core academic problem: tests as “correctness” lie

The future system (“if tests pass, ship the no-taste fix”) is exactly the **test-driven automated program repair (APR)** assumption. The literature is blunt about that assumption.

### 2.1 Patch overfitting (central result)

Smith, Forrest, Weimer et al. (*“Is the Cure Worse Than the Disease? Overfitting in Automated Program Repair,”* FSE 2015) showed that patches that pass the training suite often fail independent held-out tests, and that **higher coverage reduces but does not eliminate** overfitting.

Later work generalized this:

- Semantics-based APR also overfits (Le et al.).
- Surveys through 2024 still treat **overfitting patches** as the dominant correctness failure mode: pass suite, wrong program.
- Ye et al. and follow-ons study **automated patch correctness assessment** precisely because suite-pass is not correctness.

**Implication:**  
“Black-box fix if tests pass” is only safe if the suite is not a bag of examples, but a **multi-oracle correctness envelope** that overfitting cannot easily satisfy.

### 2.2 The oracle problem (Barr et al.)

Barr, Harman, McMinn, Shahbaz, Yoo (*TSE* 2015) classify oracles as:

1. **Specified** — formal/contractual expected behavior  
2. **Derived** — mined from executions, versions, alternate implementations  
3. **Implicit** — crashes, hangs, resource violations, type/system errors  
4. **Human** — taste, UX, product judgment  

The black-box lane should only auto-accept when the failing class is decided by (1)–(3). **Taste lives in (4)** and must stay human-gated.

That is the cleanest academic cut for “no taste required.”

---

## 3. Fields that matter (and what each buys you)

### 3.1 Test adequacy theory (not “more coverage”)

Classic adequacy (Goodenough & Gerhart; Zhu et al. surveys) asks: *when is a suite enough?*

Modern empirical correction (Inozemtseva & Holmes, ICSE 2014): **coverage correlates poorly with fault detection once suite size is controlled**. Coverage is a weak proxy, not a correctness certificate.

**Design rule:**  
Measure **oracle strength** (what wrong behaviors are impossible), not line coverage. The suite already leans this way with laws; keep that as first-class metrics.

### 3.2 Mutation testing (suite quality as a scientific instrument)

Mutation testing injects artificial faults and asks whether tests kill them. It is the standard research proxy for suite strength (Jia & Harman survey; decades of work).

Important nuances:

- Mutation score ≈ “can we detect this fault model?” not “are we correct forever.”
- Equivalent mutants and weak operators inflate scores.
- **Property-based tests** can be far more mutant-killing than unit tests (recent Python corpus study: ~50× per test on average).

**Design rule:**  
Use mutation as a **meta-test of the test system**, not as a PR gate that freezes experimentation. Nightly mutation on **law/property layers**, not on UI snapshot spam.

### 3.3 Property-based testing (PBT)

PBT (QuickCheck lineage; Hypothesis/Conjecture design) encodes **universal statements** over generated domains:

- generators define the input space  
- shrinkers minimize counterexamples  
- corpora turn failures into permanent regressions automatically  

`prop.dart` already implements the research-correct architecture (seed, tape shrink, corpus, coverage quotas). That is the right spine for black-box repair: a fix that passes PBT laws has satisfied a **quantified property**, not one remembered example.

**High-leverage research category:** formalize more product behavior as **for-all laws**, not example cases.

### 3.4 Metamorphic testing (oracle when truth is hard)

Chen’s metamorphic testing: instead of knowing absolute outputs, assert **relations across related executions** (e.g., incremental rebuild ≡ full rebuild; permute isomorphic inputs; rank-1 updates).

Empirically, a **small number of diverse metamorphic relations** can approach full-oracle fault detection for many domains.

**Why this fits Manifold:**  
Spectral/engine/diff/git-parse domains often lack a simple expected value, but they *do* have algebraic relations. The suite already uses this; the research says **diversity of relations** beats volume of cases.

### 3.5 Differential testing (N-version / cross-impl oracles)

McKeeman (1998): feed equivalent inputs to multiple implementations; disagreement ⇒ bug.

Compiler testing surveys generalize this into RDT / EMI / etc.

The suite already does:

- config-swapped git behavior  
- cross-OS differentials  
- parser A vs parser B (with the known “both wrong the same way” hole)

**Research upgrade (already rediscovered in-repo):**  
Differential alone is blind to **common-mode failure**. Ground-truth anchors (`listReflog`/`%09` class) are exactly the fix recommended by experience: **pair differential with absolute anchors** (external `git`, byte reconstruction, fsck, etc.).

### 3.6 Specification mining / dynamic invariants (Daikon line)

Daikon-style systems infer likely invariants from traces, then turn them into oracles/tests.

**Danger for black-box repair:**  
Inferred invariants encode *observed* behavior, including bugs and accidental correlations → **characterization lock-in**. That is Feathers’ characterization/golden-master territory: freeze actual behavior, not desired correctness.

**Design rule:**  
Use mining as a **proposal generator for candidate laws**, then promote only after human/contract review into the law corpus. Never auto-promote traces into hard gates for auto-fix.

### 3.7 Design by Contract / runtime verification

Meyer’s DbC and runtime assertion checking: preconditions, postconditions, invariants as executable specs. Contracts are among the strongest “specified oracles.”

**Design rule:**  
For no-taste domains (CAS, atomic write durability, ref encoding, parse injectivity), **contracts in production paths + tests that violate preconditions / check postconditions** beat example tests. Seams (`Clock`, `writeFileAtomic`, GitSpawn, typed OIDs) are already contract-shaped.

### 3.8 Causal / counterfactual testing

Johnson & Brun’s Causal Testing: find minimal input differences that flip pass/fail to explain root causes.

Useful for:

- auto-repair localization  
- shrinking beyond tape shrink (semantic counterfactuals)  
- “what single axis made this break?”

### 3.9 Adaptive random / diversity testing

Chen’s Adaptive Random Testing: failure regions are often contiguous; **diverse** inputs find faults faster than pure random.

Maps cleanly to generators: diversity over ops, repo shapes, unicode, configs, concurrency schedules — not more of the same happy path.

### 3.10 Flaky-test research (the enemy of black-box trust)

Surveys (Parry et al.; Luo et al. categories) show flakiness destroys the meaning of “green.” If green is noisy, auto-merge is Russian roulette.

In-repo docs already track load-flake / subprocess-storm classes. Research consensus:

- isolate sources of nondeterminism (time, order, resources)  
- separate **order-of-magnitude** performance gates from **exact** counter gates  
- never gate correctness on ambient wall-clock  

The suite already invented the right split (counter budgets vs absolute-ms trends). That is academically aligned.

### 3.11 Regression economics

Regression is often the majority of testing cost in maintenance. Suites that grow only by pinning yesterday’s bugs become **expensive characterization of the past**.

**Design rule against regression spam:**  
Every new test must declare its **oracle class** and **property being protected**. If it only records a snapshot of incidental behavior, demote it to characterization / ratchet / corpus seed — not a first-class correctness law.

---

## 4. A taxonomy of “taste-free” vs “taste-required”

This is the decision procedure the future black-box fixer needs.

### Tier A — Auto-fix eligible (no taste)

Properties where wrongness is objective:

| Class | Examples in this product | Oracle form |
|------|--------------------------|-------------|
| Safety / integrity | repo not corrupt after ops; atomic load ∈ {old,new}; CAS rejects races | fsck, crash-prefix replay, concurrency invariants |
| Parsing fidelity | unquote paths; numstat equals git; reconstruct file bytes | external `git`, reconstruction laws |
| Encoding / injectivity | branch encode/decode; OID width 40/64 | round-trip + rejection of illegal |
| Config invariance | color/mnemonic/signature must not change semantic parse | differential + anchors |
| Resource correctness | dispose disposables; admission bounds | structural laws + leak detection |
| Secret gate | known pattern classes | truth tables + fuzz for false-negatives |
| Complexity class | work counters scale as expected | ratio gates on counters |

### Tier B — Auto-fix only with extra oracles

| Class | Risk | Extra oracle |
|------|------|--------------|
| Heuristic rankings | both “plausible” rankings pass sparse tests | metamorphic order laws + fixed fixtures with known order |
| Performance | flaky wall-clock | counters first; absolute-ms advisory |
| AI text quality | pure taste | never black-box; only structural gates (no secrets leaked, schema valid) |

### Tier C — Never auto-accept (taste / product)

UX copy, layout aesthetics, “feels right” review wording, theme *taste* beyond token compliance, product priority of features.

**Ratchets** (theme debt only shrinks) are perfect for Tier C *process*, not for auto-repair of design.

---

## 5. Why “not just regression spam” is a research stance

Regression spam is usually:

1. **Example oracles** (`expect(x, 3)`) that encode one historical incident  
2. **Goldens** that freeze incidental structure  
3. **Mocks that pass by construction**  
4. **No generator pressure** → suite never explores new space  

Research alternatives that *improve over time*:

| Mechanism | How it improves forever |
|----------|-------------------------|
| **Corpus-backed PBT** | each new failure becomes a permanent minimized seed |
| **Ratchets** | debt can only fall; paste new baseline on progress |
| **Mutation feedback** | weak regions get new laws, not more examples |
| **Metamorphic diversification** | new relations close common-mode holes |
| **Fault models** | new hazard classes (torn write, hostile config) expand the envelope |
| **Law promotion pipeline** | experiment → characterization → reviewed law → exact gate |

Corpus + knownFinding pins + law ratchets already implement pieces of an **always-improving system**. The research move is to make that the *explicit product architecture of the suite*, not an emergent culture.

---

## 6. How not to penalize experimentation

This is where many “strong suites” fail: they freeze implementation choices.

### 6.1 Specify *ends*, not *means*

Research on contracts and algebraic specs: assert **observable contracts**, not call graphs or private structure — except for *structural* laws that exist specifically to ban hazard patterns (raw writes, unbounded diffs).

Split deliberately:

- **Behavioral laws** (what the world may observe) — green means free refactor  
- **Hazard laws** (what implementation shapes are forbidden) — green means risk class closed  
- **Characterization / research probes** — non-blocking, lab-only  

Experiments should be free under behavioral laws. Hazard laws should only ban classes that are *independent of taste* (data loss, OOM, secret leak).

### 6.2 Multi-layer gates (research-aligned CI philosophy)

| Layer | Blocking? | Purpose |
|------|-----------|---------|
| Exact laws + Tier A properties | Yes | Black-box eligible |
| Deep fuzz / mutation / chaos | Nightly / high budget | Continuous improvement |
| Perf absolute-ms | Trend only | Avoid flaky vetoes |
| UI goldens | Opt-in / platform-locked | Taste-adjacent |
| Experiments / research_lab | Never in default gate | Creativity sandbox |

This matches flaky-test and regression-cost literature: **don’t put noisy or exploratory checks in the critical path of green.**

### 6.3 Separate “bug found” from “API preferred”

APR literature shows tools exploit weak suites with weird patches. If laws encode preferred structure (specific function names, specific algorithms) rather than effects, you:

- block good experiments  
- still allow wrong-but-plausible patches that match the structure  

Prefer **effect oracles** (reconstruction, fsck, injectivity, durability) over **style oracles** in the black-box lane.

---

## 7. A research-backed model for the future black-box fixer

Think of the suite as a **multi-oracle verifier**, not a test count.

### 7.1 Correctness envelope

A candidate patch is auto-acceptable only if:

1. **All Tier A laws pass** (properties, metamorphic, differential+anchors, structural hazards).  
2. **Held-out oracle set passes** — independent generators / seeds / fault schedules *not* used during repair search (Smith et al.: held-out tests expose overfitting).  
3. **Mutation/fault residual does not worsen** on the touched module’s operator set (optional but strong).  
4. **No Tier C surface changed**, or Tier C is human-reviewed.  
5. **Flake-quarantine clean** — rerun critical properties under concurrency=1 / multi-seed if needed.

This is essentially **APR + independent patch assessment** (Ye/Monperrus line), specialized to this domain.

### 7.2 Two test stores (critical architectural split)

| Store | Contents | Role |
|------|----------|------|
| **Repair oracles** | generators, laws, differential arms, fault models | search/accept during auto-fix |
| **Validation oracles** | reserved seeds, alternate metamorphic relations, higher `MANIFOLD_FUZZ`, cross-OS | detect overfitting |

If one suite does both jobs, the literature predicts overfitting.

Seeds of this already exist: default fuzz vs `MANIFOLD_FUZZ=3/50`, corpus replay vs random draw, differential vs anchors.

### 7.3 “Bug class closed forever” as the unit of progress

APR and fuzz research agree: the valuable artifact is not “test #4827,” it is:

- a **fault model** (torn write prefixes)  
- a **relation** (incremental ≡ rebuild)  
- a **structural unrepresentability** (argv lint makes config-sensitive diffs impossible)  
- a **corpus seed** that reproduces the edge  

The hostile-gitconfig “Technique B lint” is textbook: after pinning argv, the bug class becomes **unrepresentable**. That is stronger than a regression example.

**Primary quality metric:**  
number of closed hazard classes × residual mutation kill rate — not LOC of tests.

---

## 8. Gaps relative to the research ideal (diagnosis only)

Given the already advanced suite, the high-value research-aligned gaps are about **system logic**, not inventing PBT from scratch:

1. **Oracle taxonomy is implicit.** Laws, examples, goldens, ratchets, and probes coexist; black-box eligibility needs explicit tier labels.  
2. **Repair vs validation split is informal.** Corpus + fuzz scaling exist; formal “held-out” sets for auto-fix don’t.  
3. **Mutation as suite meta-metric** is not first-class (research standard for “are our laws sharp?”).  
4. **Common-mode blindness** is partially solved (anchors) but should be a checklist for every differential suite.  
5. **Generator honesty** (`requireCoverage`) is present but not universal — silent generator decay is a known PBT failure mode.  
6. **Characterization lock-in risk** on numerical/spectral surfaces if “golden floats” proliferate without metamorphic relations.  
7. **Flake classes still poison full-suite green** (documented load flakes) — fatal for unattended black-box trust until stratified.  
8. **CI teeth** (called out in the hardening plan) — without automatic execution, the envelope is philosophical.  
9. **UI / product layers** remain sparsely oracled — fine for taste, but means black-box must not touch them.  
10. **AI quality** must stay outside auto-accept; only safety/schema oracles apply (secret gate is the right pattern).

---

## 9. Creative but grounded directions (from research, fitted to Manifold)

### 9.1 Law lattice, not test pile

Organize oracles as a lattice:

- **Integrity** (fsck, atomic, CAS)  
- **Fidelity** (git ground truth, reconstruction)  
- **Invariance** (config, OS, order)  
- **Algebra** (metamorphic engine/diff/graph)  
- **Hazard unrepresentability** (source laws / lint laws)  
- **Budgets** (work counters, not clocks)  
- **Ratchets** (debt only decreases)  

Black-box only requires the first five + relevant budgets.

### 9.2 Dual-run differential for every “smart” subsystem

For spectral/coupling/Logos: always keep a **slow reference** or **rebuild-from-scratch** path as differential peer. Metamorphic testing literature is built for exactly these scientific-software-shaped oracles.

### 9.3 Promote bugs as operators

When a real bug is found, add:

1. minimized corpus seed  
2. a named operator in the fault model (if generalizable)  
3. preferably a structural law that makes the class unrepresentable  

That is how the suite becomes an **improving knowledge base**, not a scrapbook of `expect`s.

### 9.4 Experimental branches run a thin envelope

Experiments (`experiments/`, research probes) should only need:

- integrity + no-secret + no-corruption  

not the full product law lattice.

This is how strong verification coexists with play — sandbox contracts vs product contracts.

### 9.5 Auto-fix policy as a formal object

Define machine-checkable labels on tests:

- `oracle: specified | derived | implicit | characterization`  
- `tier: A|B|C`  
- `role: repair | validation | probe`  
- `fault_model: crash|race|config|encoding|...`

Then “black-box eligible” is literally a query over labels + green status — not a human vibe.

---

## 10. Synthesis: the system in one paragraph

Academic research converges on this architecture: **correctness is multi-oracle, not suite-size**; **patch acceptance needs held-out validation against overfitting**; **properties, metamorphic relations, differential+anchors, contracts, and fault models** dominate example regressions; **mutation and generator coverage** keep the suite honest; **flakes and absolute timing** must not gate trust; **characterization freezes the past** and should not auto-promote into repair oracles; **ratchets and corpora** give monotonic improvement without punishing all change; **taste stays human**. This codebase already implements many of these pieces better than most industrial systems — the next leap is less “write more tests” and more **formalizing the suite as a stratified, always-improving correctness envelope** designed so no-taste repairs can be accepted without lying.

---

## 11. Suggested reading stack (priority order)

1. Barr et al. — *The Oracle Problem in Software Testing* (taxonomy of oracles)  
2. Smith et al. — *Is the Cure Worse Than the Disease?* (overfitting / why suite-pass ≠ correct)  
3. Chen et al. — Metamorphic testing surveys (relations when truth is hard)  
4. McKeeman — Differential testing (plus compiler-testing surveys)  
5. Jia & Harman — Mutation testing survey (suite strength instrument)  
6. Inozemtseva & Holmes — Coverage ≠ effectiveness  
7. Hypothesis/Conjecture design notes (tape shrink + corpus) — already re-derived in-repo  
8. Parry et al. — Flaky tests survey  
9. Meyer — Design by Contract  
10. Feathers — Characterization tests (what *not* to treat as correctness for auto-fix)  
11. Ye / Monperrus line — automated patch correctness assessment  
12. Adaptive Random Testing surveys (diversity over volume)

---

## 12. Bottom line for the stated goal

| Goal | Research answer |
|------|-----------------|
| Black-box no-taste fixes | Only against **Tier A multi-oracles** + **held-out validation** |
| Not regression spam | Prefer **laws, relations, fault models, unrepresentability** over incident snapshots |
| Always improving | Corpus + ratchets + new fault models + mutation feedback loops |
| Don’t punish experimentation | Gate on **observable contracts**, sandbox thin integrity for labs, keep taste/UI out of auto-accept |

### Suggested next design step (still can be design-only)

A **per-module oracle map**: for each subsystem (git, diff, spectral, stores, AI), list current oracles, tier, repair vs validation role, and the largest remaining common-mode hole. That becomes the blueprint for the black-box system without writing product code yet.
