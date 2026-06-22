# Orrery — Market Analysis & Path to Genuinely Useful

*Synthesis of a six-agent research sweep (market landscape, GitHub issue/PR mining,
community sentiment, academic adoption literature, CodeScene-style actionable
intelligence, and spectral/embedding technique). This dossier is the scope anchor
and roadmap for Orrery. Findings are cross-verified; sources at the end.*

Orrery: a feature in the Manifold desktop git client. It visualizes a repo's
**structural evolution** — each file is a point in a 2D hyperbolic (Poincaré)
disk positioned by structural role (centre = coupling-central, rim = peripheral);
you scrub a timeline and watch files drift, cluster, and separate as the codebase
reorganizes commit-by-commit. It detects **regime changes** (structural inflection
points) and classifies repo structure into **archetypes** (tree / modular / GOE /
crystalline …). Powered by the Logos spectral engine: graph-Laplacian
eigendecomposition of the file co-change graph. *"git log as a watchable
phase-space movie of your architecture."*

---

## 1. The verdict

Orrery sits in a **genuinely uncontested market corner** — temporal visualization
of *code structure* (not people/throughput, not a frozen snapshot). The market
splits cleanly:

- **Productivity / process dashboards** (LinearB, Waydev, Swarmia, Pluralsight
  Flow, Code Climate Velocity, Gitential): a time axis, but over *people and
  throughput metrics*, never code shape.
- **Static structure snapshots** (repo-visualizer, git-truck, CodeCharta,
  CodeCity/JSCity, Software Galaxies, Sourcetrail, CodeFlower, GitDiagram,
  CodeSee): structure drawn at one frozen moment, via Euclidean hierarchical
  (treemap/circle-packing/city) or force-directed layouts.

The **only** tool that animates structural evolution is **Gource** — a
deliberately unanalytical force-directed *directory tree* for storytelling, with
no coupling semantics and no analysis. The spectral × co-change × temporal ×
hyperbolic combination is combined **nowhere**; the individual pillars appear in
research only in isolation, never on a co-change graph.

But the corner is empty **because it is hard to make useful, not because nobody
thought of it.** Every predecessor sank on one of two reefs:

1. **"Pretty but useless" — the Gource trap.** The default developer reaction to
   code viz is earned skepticism. *"Gource is beautiful, but pretty useless… I see
   only beautiful animations"* (HN). Our scrub is structurally the same gesture as
   Gource, so it triggers the same reflex — unless every frame answers a question.
2. **The monetization / language-coverage treadmill.** CodeSee (well-funded) shut
   down Feb 2024 → absorbed by GitKraken; Sourcetrail discontinued ("did not
   succeed as a commercial product… not every developer saw the value"); githru /
   CodeFlower dormant. Standalone structural-viz-as-SaaS is a graveyard.

**The escape, unanimous across all six research streams, reframes the feature:**

> **Orrery is not a visualization. It is an insight engine with a beautiful
> surface.** The disk is the *on-ramp*; the findings are the *product*. Beauty
> earns the first ten seconds; plain, git-grounded, commit-anchored, drillable
> findings earn the Tuesday.

---

## 2. What all six research streams converged on

- **Beauty on-ramps; findings retain.** The bar that matters: *"would a developer
  open it on a Tuesday to answer a real question?"*
- **Anchor every claim to real commits/files — show receipts.** The reef every
  tool sank on is *"what does this even mean?"* The one viz that *got adopted*
  (SeeSoft, 1992) won by a direct 1:1 mapping to the artifact with drill-down to
  real code. Every dot must drill to the real file + the commits that moved it.
  Keep eigen-anything out of the UI surface.
- **Stable layout is a truth-claim, not polish.** *"Small changes to the codebase
  can have a large impact on the visualization"* (akdas, HN). For a *timeline*
  tool this is existential — if scrubbing jitters from layout instability rather
  than real change, **the motion lies** and users stop trusting it.
- **Animation is for explore/present; static is for analyze.** Robertson et al.
  (IEEE VIS Test-of-Time): for analytic tasks animation is *least* effective;
  small-multiples most accurate, static overlays fastest; animation is fastest and
  most *enjoyable* but error-prone. Tversky's review concurs (transient frames
  overload working memory). → Scrub to explore; pair with a **static comparative
  surface** (a filmstrip of regime-boundary snapshots) for actual comparison.
- **Scale or die — aggregate, don't blob.** *"Globally visualizing a massive graph
  is basically useless."* Default to a handful of *components*, not thousands of
  *files*. The hyperbolic disk's natural focus+context is the asset to lead with.
- **Auto-derived from git = immune to staleness** — the #1 complaint about all
  code viz (decoupled diagrams rot). Orrery is computed live from the repo; lean
  in loudly.
- **Don't oversell the science.** CodeScene's own research was dismissed on HN as
  *"a glorified advert."* Demonstrate on the user's own repo; don't claim.

---

## 3. The most-requested features in the field (from issue-tracker mining)

Ranked by demand across Gource, git-of-theseus, git-truck, repo-visualizer,
code-maat, CodeCharta, Sourcetrail trackers:

1. **A second dimension per node = change magnitude.** The single most-demanded
   feature in the corpus — Gource #91 (35 reactions, a $100 bounty, open since
   2014, four duplicates). The maintainer admits the *fixed spiral layout can't
   carry it*. Orrery's layout owns position via centrality, so node size/colour
   can carry churn/coupling intensity natively (log-scaled, min-size floor).
2. **Animate / scrub structural evolution over time** — requested *on tools that
   lack it* (git-truck #763, JSCity HN). Orrery's exact premise.
3. **Selecting a file drives the timeline** (cross-highlighting) — git-truck #861.
4. **"Show me what files are connected"** — the co-change graph itself
   (repo-visualizer #57). Orrery's engine.
5. **Filter bulk/mechanical commits** — reformatting/vendoring commits manufacture
   false signal (git-of-theseus #94, git-truck #695). CodeScene drops changesets
   touching >50 files.
6. **Author-identity resolution** (`.mailmap`) — universal, chronically unsolved
   (Gource #219, git-of-theseus #47).
7. **Timeline windowing / zoom to a date range** (git-of-theseus #93).
8. **Render the repo state *before* the scrub point** (mid-history seeding) —
   Gource #116 (19 reactions, never fixed): scrubbing to *t* must reconstruct the
   real tree at *t*, or files flash in and out.
9. **Export / interop + headless rendering** — Gource #45, Sourcetrail #1181.
10. **Graceful degradation at scale** — repo-visualizer #63 / git-truck #579 die
    on big repos ("a bunch of grey circles").

### Failure modes to avoid (also from the trackers + sentiment)

"Pretty but useless" interpretability wall · derived metrics misread as bugs when
meaning isn't on-screen · **unstable/non-deterministic layout** (git-truck #584) ·
hairball/fog at scale · no checkpointing → literal abandonment (git-of-theseus
#71: "ETA 40 days… I'm not going to try it again") · correctness bugs that erode
trust · install/onboarding friction · the monetization/language treadmill.

---

## 4. Roadmap

### P0 — make it true and useful (the credibility floor)

Without these it is an admired screensaver.

1. **UASE stabilization.** Replace per-snapshot embedding + Procrustes with **one
   joint SVD over all snapshots** (Unfolded Adjacency Spectral Embedding,
   Gallagher et al., NeurIPS 2021) → a single shared basis, *provable*
   cross-sectional + longitudinal stability, sign-flips/teleport unrepresentable
   by construction. Still spectral (keeps "physics not knobs"). Do the
   stabilization in Euclidean latent space; keep the Poincaré map a fixed
   post-transform (else the rim re-introduces apparent jitter). *This is the
   product's core truth-claim, not cleanup.*
2. **The Findings rail** — *the single highest-leverage move.* Orrery already
   computes the events; it does not yet **name** them. Wire `regimeChanges`,
   `archetypeTransitions`, and per-node centre↔periphery drift into plain-language,
   commit-anchored cards that **end in an imperative**: *"At commit 9f3a your repo
   split into two loosely-coupled halves — was that intended?"* Converts the
   feature from interesting to actionable in one stroke.
3. **Drill-down everywhere** — click a dot → the file + the commits and co-changes
   that moved it (SeeSoft's adopted-tool discipline).
4. **Filter bulk/mechanical commits before regime detection** (CodeScene's
   >50-file heuristic). Reformatting/vendoring commits manufacture false regime
   changes — a correctness bug in disguise.

### P1 — make it scale and read

5. **Hierarchical aggregation / LOD** — collapse to module super-nodes past a
   node-count threshold (the Laplacian already yields the clustering); drill to
   files. Answers the hairball objection; the hyperbolic disk's focus+context is
   the asset.
6. **Second encoding dimension = change magnitude** (the field's #1 demand). Node
   size/colour ← churn or coupling intensity, log-scaled, min-size floor.
7. **Mid-history seeding** (Gource #116) — reconstruct the real tree at scrub time.
8. **Static comparison surface** — a filmstrip of regime-boundary snapshots for
   side-by-side comparison (the animation literature's prescription).
9. **Make the spectral axis legible** — label core/rim; on click, answer *"why did
   this file move here?"*

### P2 — the actionable-intelligence payoff

Map Orrery's existing spectral engine to CodeScene-grade findings — several of
which **CodeScene cannot produce** because Orrery has signals it lacks
(turbulence = thrashing, Berry phase = silent role-reassignment, archetype =
structural identity, forecasting = decline prediction):

- *"`auth_manager.dart` is coupled to 23 files — a change-amplifier, likely a
  God-file. Start here."* (`jaccardCentralityMap` = Sum-of-Coupling.)
- *"`payment_flow.dart` is drifting core→periphery over 40 commits — decoupling,
  or quietly rotting."* (Unique to the hyperbolic embedding.)
- *"This subsystem is thrashing — the last 15 commits keep reversing each other's
  structural direction."* (`turbulence` + `antiMomentumCurve` — net-new.)
- *"At the current trend the spectral gap crosses the splitting threshold in ~12
  commits — intervene now."* (`forecastScalar` — a leading indicator.)
- *"Stopped being modular, became a tangled bulk at commit 7e22."*
  (`archetypeTransitions`.)
- *"Commit c4d1 looked cosmetic but silently reassigned which files are central —
  review carefully."* (`berryPhase` spike with low eigenvalue step distance.)
- Plus: silent cross-module coupling, hidden clones (spectral-profile similarity
  without git history), bus-factor / off-boarding risk (author × drift).

**Surfacing meta-pattern (what makes any of this land):** MAP (a spatial metaphor
to triage by eye) → TREND (better or worse / did my fix work) → PRIORITY (a short
ranked list, not a dashboard) → STORY (a memorable handle) — and **every finding
terminates in one concrete next action**, never a bare metric.

---

## 5. Positioning

- **Claim a synthesis, not a primitive.** "A spectral co-change manifold, animated
  per-commit, in hyperbolic space" — each word is prior art alone; the sentence is
  novel. Do not claim to have invented spectral software analysis (NPS thesis;
  Myers 2003 predate us) or the solar-system metaphor.
- **Pre-empt the name collision.** Graham et al. 2004, *"A Solar System Metaphor
  for 3D Visualisation of OO Software Metrics"* — theirs paints metrics onto fixed
  orbits; Orrery *earns* position from the co-change spectrum and lets it move.
- **Differentiate in one line each:** vs Gource → "measured coupling +
  classification, not file-tree fireworks"; vs CodeScene → "the coupling view that
  doesn't become a hairball"; vs CodeSee/Sourcegraph/Cursor maps → "structural
  *drift over history*, not a force-directed dependency snapshot."
- **Desktop-native + fully local is the moat.** The SaaS graveyard proves
  standalone structural viz is fragile; "your history never leaves the machine" is
  a real edge — and counters the surveillance unease around git-analytics SaaS.

---

## 6. Risks that remain

- **Legibility at scale** — dots-in-a-disk fogs out at thousands of files; P1 #5
  (aggregation) must land.
- **Archetype credibility (horoscope risk)** — anchor each classification to an
  inspectable spectral quantity (eigenvalue gap, Fiedler value), so it reads as
  measurement, not vibe. Aligns with the engine's "physics not knobs" principle.
- **Animation-for-analysis weakness** — mitigated by the static comparison surface
  and by keeping scrub controllable + default-paused.

All three are addressable; none is fatal.

---

## 7. Project-principle alignment

The research independently re-derived several of Manifold's standing principles:
**physics not knobs** (archetype thresholds must be inspectable spectral
quantities), **no-history-fake** (findings anchored on real git observables),
**no band-aids** (UASE makes the teleport bug-class unrepresentable rather than
smoothing it), and the **manifold-universal dream** (co-change is the swappable
edge source; the spectral/archetype framing is the portable part — keep that seam
clean).

---

## 8. Sources

**Market landscape / tools** — Gource https://gource.io/ · git-of-theseus
https://github.com/erikbern/git-of-theseus · CodeScene https://codescene.com/ ·
Code Maat https://github.com/adamtornhill/code-maat · git-truck
https://github.com/git-truck/git-truck · repo-visualizer
https://github.com/githubocto/repo-visualizer · CodeCharta https://codecharta.com/
· CodeCity https://wettel.github.io/codecity.html · Software Galaxies
https://anvaka.github.io/pm/ · Sourcetrail
https://github.com/CoatiSoftware/Sourcetrail · CodeSee→GitKraken
https://www.gitkraken.com/blog/gitkraken-launches-devex-platform-acquires-codesee

**GitHub demand signals** — Gource #91 (file-size, 35r + bounty)
https://github.com/acaudwell/Gource/issues/91 · Gource #116 (prior-state, 19r)
https://github.com/acaudwell/Gource/issues/116 · git-truck #763 (animate
evolution) https://github.com/git-truck/git-truck/issues/763 · git-truck #584
(unstable positions) https://github.com/git-truck/git-truck/issues/584 ·
git-of-theseus #94 (ignore commits) https://github.com/erikbern/git-of-theseus/issues/94
· CodeScene temporal-coupling >50-file cutoff
https://docs.enterprise.codescene.io/versions/3.2.9/guides/technical/temporal-coupling.html

**Community sentiment** — "Visualizing a Codebase" HN
https://news.ycombinator.com/item?id=28074827 · Gource "pretty but useless"
https://news.ycombinator.com/item?id=9950787 · "globally visualizing a massive
graph is basically useless" https://news.ycombinator.com/item?id=41132095 ·
CodeScene "glorified advert" https://news.ycombinator.com/item?id=31834387

**Academic / adoption** — Tversky, Morrison & Betrancourt, *Animation: can it
facilitate?* (IJHCS 2002)
https://hci.stanford.edu/courses/cs448b/papers/Tversky_AnimationFacilitate_IJHCS02.pdf
· Robertson et al., *Effectiveness of Animation in Trend Visualization* (IEEE TVCG
2008, ToT 2018)
https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tvcg2008-trendvis.pdf
· Sillito et al., *Questions Programmers Ask During Software Evolution Tasks* (FSE
2006) https://www.cs.ubc.ca/~murphy/papers/other/asking-answering-fse06.pdf ·
Eick et al., *SeeSoft* (IEEE TSE 1992)
https://www.sdml.cs.kent.edu/library/Eick92.pdf · Wettel & Lanza, *Software
Systems as Cities* (ICSE 2011) https://wettel.github.io/download/Wettel11a-icse.pdf

**Actionable intelligence (CodeScene / Tornhill)** — *Your Code as a Crime Scene*
https://pragprog.com/titles/atcrime2/ · *Software Design X-Rays*
https://pragprog.com/titles/atevol/ · Tornhill & Borg, *Code Red: The Business
Impact of Code Quality* (TechDebt 2022) https://arxiv.org/abs/2203.04374 ·
Nagappan & Ball, *Relative Code Churn… Defect Density* (ICSE 2005)
https://www.microsoft.com/en-us/research/publication/use-of-relative-code-churn-measures-to-predict-system-defect-density/

**Spectral novelty + temporal-embedding technique** — Gallagher, Jones &
Rubin-Delanchy, *Spectral embedding for dynamic networks with stability
guarantees* (UASE, NeurIPS 2021)
https://proceedings.nips.cc/paper_files/paper/2021/file/5446f217e9504bc593ad9dcf2ec88dda-Paper.pdf
· code https://github.com/iggallagher/Spectral-Embedding · eigenvector continuation
review https://arxiv.org/pdf/2310.19419 · AlignedUMAP
https://umap-learn.readthedocs.io/en/latest/aligned_umap_basic_usage.html ·
Poincaré Embeddings (Nickel & Kiela, NeurIPS 2017) https://arxiv.org/abs/1705.08039
· Hyperbolic Function Embedding (closest prior art) https://www.mdpi.com/2073-8994/11/2/254
· Graham et al., *Solar System Metaphor for OO Metrics* (2004, name collision)
https://dl.acm.org/doi/10.5555/1082101.1082108
