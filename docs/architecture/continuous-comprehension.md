# Continuous Comprehension — Working Snapshots & "While You Were Away"

*Two lenses on the **time axis**. **Snapshots**: a dense, continuous record of what
you're doing right now, fine enough for the physics engine to measure motion in
real time. **While You Were Away**: a measured, ranked digest of what happened
since you last looked, scoped to your code. Both are local, deterministic, and
reuse engine Manifold already has (SpectralTrajectory, the co-change graph, the
Orrery findings). This dossier is the design anchor for both.*

---

## 1. The frame

Git samples a codebase **once per commit** — a sparse, deliberate, after-the-fact
signal. Two things change the sampling rate, and both are interesting precisely
because Manifold is a *measuring* instrument, not a VCS front-end:

1. **Up-sample the present.** Jujutsu's model treats the working copy as a commit
   that is **re-snapshotted on every operation** — no staging, no stash, and an
   operation log you can scrub and undo *anything* from. Read as a data model
   (not a CLI to adopt), it means ~1 sample per *save* instead of per *commit*.
   That is a dense time-series, and the engine is starved for one: trajectory,
   turbulence, breathing-period, and forecast all sharpen with resolution.

2. **Name the gap.** For a solo dev every team metric dies — "other developers"
   is the empty set. It comes back to life under one substitution: **"others" →
   "past-you / an agent / whoever touched it while you were gone."** Swap the
   *people* axis for a *time* axis and "what did everyone else do" becomes "what
   landed since I last looked."

These are **duals**. Snapshots is the fine-grained *present* ("what I'm doing,
where it sits in the structure"). While-You-Were-Away is the *gap* ("what
happened without me"). Together they make Manifold a continuous personal
comprehension timeline: open it and instantly know where your live work sits and
what changed since you left — both **measured**, neither **narrated from a guess**.

---

## 2. Snapshots — the dense working-copy signal

### 2.1 What it is

Manifold passively snapshots the working tree as you edit, building a dense local
history *below* the commit grain. It adopts Jujutsu's **continuous-snapshot
model** as a read model — never its CLI, never its storage format. The point is
not a new VCS; it's feeding the lenses a higher frame-rate.

### 2.2 The linchpin: decouple decomposition from projection

The reason this is feasible (and not a re-compute-the-universe-on-every-keystroke
trap): **the expensive step stays sparse, the cheap step goes dense.**

- **Per commit (expensive, unchanged):** the spectral decomposition — the
  eigenbasis of the co-change graph — is recomputed at commit grain exactly as
  the `SpectralTrajectory` already does. This is the stable *basis*.
- **Per snapshot (cheap, new):** the working diff is a transient set of touched
  files — a hyperedge. **Project** that hyperedge onto the *existing* committed
  eigenbasis (`logos_core` already exposes `project(ρ)` for exactly this: a diff's
  coordinates in the spectral modes). A projection is a handful of inner
  products, not an eigensolve.

So you get **dense motion of a live node** without dense re-decomposition. That
single decoupling is what turns "continuous snapshots" from a fantasy into a
background task.

### 2.3 Capture — side-effect-free and git-native

- A debounced file-watcher (Manifold already watches the active repo) fires on
  save / pause-in-typing.
- Capture via **`git stash create`** — it writes a *dangling* commit object for
  the current WIP state **without touching the working tree or the stash list**.
  No mutation, no porcelain surprises, a real tree to diff against.
- Record `{snapshotSha, timestamp, changedPaths}` in an append-only log under a
  gitignored sidecar (`.manifold/snapshots/`), and pin each dangling commit with
  a ref under `refs/manifold/snapshots/*` so GC doesn't reap it. Ring-buffer /
  time-bound it so it never grows without bound.
- Bonus identity: this *is* a **legible reflog**. It closes git's worst safety
  hole — uncommitted work is normally unrecoverable — and labels each entry by
  *what structurally changed* instead of a bare SHA.

### 2.4 The lenses it unlocks

- **Live node in the disk.** Project the live diff onto the committed basis → a
  point in the Poincaré disk that **moves as you type**: "here's where your
  current edits sit in the structure," continuously. The purest expression of
  "understand, don't operate."
- **Structural op-diff.** Between two snapshots, show not "12 files changed" but
  the *structural* delta: the live case is a projection delta; a wider range is a
  partition delta — "**module M split off; A↔B coupling dropped 40%**." Nobody
  renders structural deltas between repo *states*; only a structure-measuring
  engine can.
- **The Orrery breathes.** Dense samples mean the scrub moves smoothly instead of
  jumping commit-to-commit, and the FFT breathing-period / `forecast` curves
  finally have the resolution they want.

### 2.5 What already exists vs. what's new

Already: `SpectralBasis` + `project(ρ)`, `SpectralTrajectory`, the co-change graph
(`file_coupling.dart`), the Poincaré map + the Orrery surface. **New infra is
small:** the debounced watcher, the snapshot log + refs, and the wiring that
projects a live diff and drops a node on the disk.

### 2.6 Roadmap

- **P0 — capture + live node.** The watcher → `git stash create` → log/ref, and
  the projection → a moving point on the disk. Smallest visible win; proves the
  decoupling.
- **P1 — op-diff + scrub.** Structural delta between two snapshots; a scrubber
  over the snapshot stream (your own session as a timeline).
- **P2 — breathing + recovery.** Feed dense samples into the trajectory/forecast
  so the Orrery breathes; a restore-a-working-state affordance over the log.

### 2.7 Risks

- **Cost / frequency** — debounce hard; `git stash create` is cheap; projection
  is inner products. Never eigensolve on save.
- **Stale basis** — projecting onto a basis that's many commits old drifts;
  re-anchor the basis on each commit (the trajectory already does).
- **Repo hygiene** — sidecar + dedicated `refs/manifold/*`; never write to the
  user's history or stash list.
- **Storage** — ring-buffer / TTL the log.
- **Privacy** — local-only, gitignored, never leaves the machine (the moat).

---

## 3. While You Were Away

### 3.1 What it is

On launch (or on demand) Manifold shows a **ranked digest of what landed since
your last visit**, scoped to code you own, ranked by **measured structural
importance** — not recency, not commit message. It is the emptiest category in
the comprehension landscape: raw `git log --since` is an unranked wall, changelog
tools categorize by message type, team SaaS ranks *people*, and GitHub *still*
has no "since I last looked" boundary.

### 3.2 Architecture

- **Last-seen.** Persist per-repo `{lastSeenHead, lastOpenedAt}` in the sidecar /
  settings.
- **Delta window.** `git log <lastSeenHead>..HEAD` for what landed; optionally
  `HEAD..@{upstream}` for incoming-but-unpulled.
- **Ownership scope.** Per-file authored-line ratio via `git blame` (blob-keyed
  cache, so it dedupes across history for free). "Your code" = high own-ratio.
  The n=1 reframe makes this matter most when *someone else* — or an **agent** —
  moved things while you were out.
- **Ranking = engine signals, not git metadata.** Order the changed files by
  co-change **centrality** (hub-ness, already computed), **churn**, and
  **coupling to your owned files** — and, the Manifold move, flag any change that
  crossed a **regime boundary**, shifted **archetype**, or triggered a
  **reshuffle / drift** finding. In other words: *run the Orrery's finding engine
  on the delta window.*
- **Render.** A catch-up digest reusing the finding-card design; each item drills
  to the file/commit and its structural story.

### 3.3 Why it isn't just `git log`

The difference is measurement. Not "12 commits landed" but: "**while you were
away — module X split off; your auth files gained a coupling to Y; one commit
looked routine but reshuffled which files are central.**" Ranked, scoped, and
**reusing the exact regime / reshuffle / drift / forecast machinery already built
for the Orrery.** Deterministic; it abstains on *why* (rationale is human) and
narrates only the *what* it measured.

### 3.4 What already exists vs. what's new

Already: the Orrery findings (`regime`, `reshuffle`, `driftOut/In`, `forecast`),
co-change centrality, the trajectory. **New infra:** last-seen tracking, the
ownership/blame scoping, and the digest surface.

### 3.5 Roadmap

- **P0 — the digest.** Last-seen tracking + `last..HEAD` + a ranked list
  (centrality × churn). Pure git + existing centrality, *no new engine work.* The
  smallest build in this dossier — **start here.**
- **P1 — ownership + structural stories.** Blame-ratio scoping; reuse Orrery
  findings on the window so each item carries its structural "what changed."
- **P2 — incoming + agents.** Unpulled-awareness; an agent-activity digest ("the
  agent touched 40 files; structurally it did 3 things") — the comprehension
  surface for machine-speed editing.

### 3.6 Risks

- **Defining "away"** — last-open timestamp vs. last-HEAD-seen; pick HEAD-seen so
  it survives across machines/sessions.
- **Squash / rebase** — `last..HEAD` can be messy under history rewriting; degrade
  gracefully (fall back to time-window), never error.
- **Solo noise** — on a one-author repo ownership scoping is a no-op; degrade to
  "everything is yours" and lean on the structural ranking.
- **Over-notifying** — rank hard and cap; a digest, not a firehose.

---

## 4. Build order

1. **While-You-Were-Away P0** — pure git + existing centrality, zero new engine
   work, and it's the first thing a comprehension-first client should do *on
   launch*. Fastest blood.
2. **Snapshots P0** — the watcher + live node; proves the decompose/project
   decoupling.

They share the trajectory + findings substrate, so each makes the other richer:
dense snapshots give the away-digest a finer "since" boundary, and the away-digest
gives the snapshot stream its committed anchor points.

---

## 5. Project-principle alignment

- **Measure then show, never lie** — the digest is ranked by *measured* structure;
  the live node is a *real* projection; both **abstain on "why."** Faithfulness is
  a hard check against measured truth, not a soft score.
- **Local; your history never leaves the machine** — sidecar `.manifold/`
  (gitignored), dedicated `refs/manifold/*`, no cloud, no telemetry.
- **Braindead-simple** — no config: a point that moves, a digest on launch. The
  eigenmath stays invisible.
- **Physics, not knobs** — projection coefficients and co-change centrality are
  measurements, not tuning sliders.
- **Manifold-universal** — the *time axis* and the *structure measure* are the
  portable parts; the git capture (`stash create`, `log`, `blame`) is just the
  swappable edge source. Keep that seam clean for the eventual non-git corpora.

---

## 6. Sources

**Continuous-snapshot model** — Jujutsu working copy
https://docs.jj-vcs.dev/latest/working-copy/ · operation log
https://docs.jj-vcs.dev/latest/operation-log/ · `jj op diff` (structural state
diff) https://man.archlinux.org/man/extra/jujutsu/jj-operation-diff.1.en ·
git-branchless event log / `git undo`
https://github.com/arxanas/git-branchless/wiki/Command:-git-undo · "Use Jujutsu,
not Git" (agents make dense op-streams)
https://slavakurilyak.com/posts/use-jujutsu-not-git · commits-are-snapshots-not-diffs
https://github.blog/open-source/git/commits-are-snapshots-not-diffs/ · reflog's
limits (can't recover uncommitted work)
https://blog.codeminer42.com/git-reflogs-a-guide-to-rescuing-your-lost-work/

**Catch-up / ownership / coupling** — Krüger et al., *Do You Remember This Source
Code?* (ICSE 2018 — own-code familiarity; ownership rs≈0.55) · code-maat change
coupling (lift / Dice) https://github.com/adamtornhill/code-maat · git-standup
(yesterday, not a gap) https://github.com/kamranahmedse/git-standup · GitHub
Activity has no "since last visit" boundary (long-standing request).
# Continuous Comprehension — Working Snapshots & "While You Were Away"

*Two lenses on the **time axis**. **Snapshots**: a dense, continuous record of what
you're doing right now, fine enough for the physics engine to measure motion in
real time. **While You Were Away**: a measured, ranked digest of what happened
since you last looked, scoped to your code. Both are local, deterministic, and
reuse engine Manifold already has (SpectralTrajectory, the co-change graph, the
Orrery findings). This dossier is the design anchor for both.*

---

## 1. The frame

Git samples a codebase **once per commit** — a sparse, deliberate, after-the-fact
signal. Two things change the sampling rate, and both are interesting precisely
because Manifold is a *measuring* instrument, not a VCS front-end:

1. **Up-sample the present.** Jujutsu's model treats the working copy as a commit
   that is **re-snapshotted on every operation** — no staging, no stash, and an
   operation log you can scrub and undo *anything* from. Read as a data model
   (not a CLI to adopt), it means ~1 sample per *save* instead of per *commit*.
   That is a dense time-series, and the engine is starved for one: trajectory,
   turbulence, breathing-period, and forecast all sharpen with resolution.

2. **Name the gap.** For a solo dev every team metric dies — "other developers"
   is the empty set. It comes back to life under one substitution: **"others" →
   "past-you / an agent / whoever touched it while you were gone."** Swap the
   *people* axis for a *time* axis and "what did everyone else do" becomes "what
   landed since I last looked."

These are **duals**. Snapshots is the fine-grained *present* ("what I'm doing,
where it sits in the structure"). While-You-Were-Away is the *gap* ("what
happened without me"). Together they make Manifold a continuous personal
comprehension timeline: open it and instantly know where your live work sits and
what changed since you left — both **measured**, neither **narrated from a guess**.

---

## 2. Snapshots — the dense working-copy signal

### 2.1 What it is

Manifold passively snapshots the working tree as you edit, building a dense local
history *below* the commit grain. It adopts Jujutsu's **continuous-snapshot
model** as a read model — never its CLI, never its storage format. The point is
not a new VCS; it's feeding the lenses a higher frame-rate.

### 2.2 The linchpin: decouple decomposition from projection

The reason this is feasible (and not a re-compute-the-universe-on-every-keystroke
trap): **the expensive step stays sparse, the cheap step goes dense.**

- **Per commit (expensive, unchanged):** the spectral decomposition — the
  eigenbasis of the co-change graph — is recomputed at commit grain exactly as
  the `SpectralTrajectory` already does. This is the stable *basis*.
- **Per snapshot (cheap, new):** the working diff is a transient set of touched
  files — a hyperedge. **Project** that hyperedge onto the *existing* committed
  eigenbasis (`logos_core` already exposes `project(ρ)` for exactly this: a diff's
  coordinates in the spectral modes). A projection is a handful of inner
  products, not an eigensolve.

So you get **dense motion of a live node** without dense re-decomposition. That
single decoupling is what turns "continuous snapshots" from a fantasy into a
background task.

### 2.3 Capture — side-effect-free and git-native

- A debounced file-watcher (Manifold already watches the active repo) fires on
  save / pause-in-typing.
- Capture via **`git stash create`** — it writes a *dangling* commit object for
  the current WIP state **without touching the working tree or the stash list**.
  No mutation, no porcelain surprises, a real tree to diff against.
- Record `{snapshotSha, timestamp, changedPaths}` in an append-only log under a
  gitignored sidecar (`.manifold/snapshots/`), and pin each dangling commit with
  a ref under `refs/manifold/snapshots/*` so GC doesn't reap it. Ring-buffer /
  time-bound it so it never grows without bound.
- Bonus identity: this *is* a **legible reflog**. It closes git's worst safety
  hole — uncommitted work is normally unrecoverable — and labels each entry by
  *what structurally changed* instead of a bare SHA.

### 2.4 The lenses it unlocks

- **Live node in the disk.** Project the live diff onto the committed basis → a
  point in the Poincaré disk that **moves as you type**: "here's where your
  current edits sit in the structure," continuously. The purest expression of
  "understand, don't operate."
- **Structural op-diff.** Between two snapshots, show not "12 files changed" but
  the *structural* delta: the live case is a projection delta; a wider range is a
  partition delta — "**module M split off; A↔B coupling dropped 40%**." Nobody
  renders structural deltas between repo *states*; only a structure-measuring
  engine can.
- **The Orrery breathes.** Dense samples mean the scrub moves smoothly instead of
  jumping commit-to-commit, and the FFT breathing-period / `forecast` curves
  finally have the resolution they want.

### 2.5 What already exists vs. what's new

Already: `SpectralBasis` + `project(ρ)`, `SpectralTrajectory`, the co-change graph
(`file_coupling.dart`), the Poincaré map + the Orrery surface. **New infra is
small:** the debounced watcher, the snapshot log + refs, and the wiring that
projects a live diff and drops a node on the disk.

### 2.6 Roadmap

- **P0 — capture + live node.** The watcher → `git stash create` → log/ref, and
  the projection → a moving point on the disk. Smallest visible win; proves the
  decoupling.
- **P1 — op-diff + scrub.** Structural delta between two snapshots; a scrubber
  over the snapshot stream (your own session as a timeline).
- **P2 — breathing + recovery.** Feed dense samples into the trajectory/forecast
  so the Orrery breathes; a restore-a-working-state affordance over the log.

### 2.7 Risks

- **Cost / frequency** — debounce hard; `git stash create` is cheap; projection
  is inner products. Never eigensolve on save.
- **Stale basis** — projecting onto a basis that's many commits old drifts;
  re-anchor the basis on each commit (the trajectory already does).
- **Repo hygiene** — sidecar + dedicated `refs/manifold/*`; never write to the
  user's history or stash list.
- **Storage** — ring-buffer / TTL the log.
- **Privacy** — local-only, gitignored, never leaves the machine (the moat).

---

## 3. While You Were Away

### 3.1 What it is

On launch (or on demand) Manifold shows a **ranked digest of what landed since
your last visit**, scoped to code you own, ranked by **measured structural
importance** — not recency, not commit message. It is the emptiest category in
the comprehension landscape: raw `git log --since` is an unranked wall, changelog
tools categorize by message type, team SaaS ranks *people*, and GitHub *still*
has no "since I last looked" boundary.

### 3.2 Architecture

- **Last-seen.** Persist per-repo `{lastSeenHead, lastOpenedAt}` in the sidecar /
  settings.
- **Delta window.** `git log <lastSeenHead>..HEAD` for what landed; optionally
  `HEAD..@{upstream}` for incoming-but-unpulled.
- **Ownership scope.** Per-file authored-line ratio via `git blame` (blob-keyed
  cache, so it dedupes across history for free). "Your code" = high own-ratio.
  The n=1 reframe makes this matter most when *someone else* — or an **agent** —
  moved things while you were out.
- **Ranking = engine signals, not git metadata.** Order the changed files by
  co-change **centrality** (hub-ness, already computed), **churn**, and
  **coupling to your owned files** — and, the Manifold move, flag any change that
  crossed a **regime boundary**, shifted **archetype**, or triggered a
  **reshuffle / drift** finding. In other words: *run the Orrery's finding engine
  on the delta window.*
- **Render.** A catch-up digest reusing the finding-card design; each item drills
  to the file/commit and its structural story.

### 3.3 Why it isn't just `git log`

The difference is measurement. Not "12 commits landed" but: "**while you were
away — module X split off; your auth files gained a coupling to Y; one commit
looked routine but reshuffled which files are central.**" Ranked, scoped, and
**reusing the exact regime / reshuffle / drift / forecast machinery already built
for the Orrery.** Deterministic; it abstains on *why* (rationale is human) and
narrates only the *what* it measured.

### 3.4 What already exists vs. what's new

Already: the Orrery findings (`regime`, `reshuffle`, `driftOut/In`, `forecast`),
co-change centrality, the trajectory. **New infra:** last-seen tracking, the
ownership/blame scoping, and the digest surface.

### 3.5 Roadmap

- **P0 — the digest.** Last-seen tracking + `last..HEAD` + a ranked list
  (centrality × churn). Pure git + existing centrality, *no new engine work.* The
  smallest build in this dossier — **start here.**
- **P1 — ownership + structural stories.** Blame-ratio scoping; reuse Orrery
  findings on the window so each item carries its structural "what changed."
- **P2 — incoming + agents.** Unpulled-awareness; an agent-activity digest ("the
  agent touched 40 files; structurally it did 3 things") — the comprehension
  surface for machine-speed editing.

### 3.6 Risks

- **Defining "away"** — last-open timestamp vs. last-HEAD-seen; pick HEAD-seen so
  it survives across machines/sessions.
- **Squash / rebase** — `last..HEAD` can be messy under history rewriting; degrade
  gracefully (fall back to time-window), never error.
- **Solo noise** — on a one-author repo ownership scoping is a no-op; degrade to
  "everything is yours" and lean on the structural ranking.
- **Over-notifying** — rank hard and cap; a digest, not a firehose.

---

## 4. Build order

1. **While-You-Were-Away P0** — pure git + existing centrality, zero new engine
   work, and it's the first thing a comprehension-first client should do *on
   launch*. Fastest blood.
2. **Snapshots P0** — the watcher + live node; proves the decompose/project
   decoupling.

They share the trajectory + findings substrate, so each makes the other richer:
dense snapshots give the away-digest a finer "since" boundary, and the away-digest
gives the snapshot stream its committed anchor points.

---

## 5. Project-principle alignment

- **Measure then show, never lie** — the digest is ranked by *measured* structure;
  the live node is a *real* projection; both **abstain on "why."** Faithfulness is
  a hard check against measured truth, not a soft score.
- **Local; your history never leaves the machine** — sidecar `.manifold/`
  (gitignored), dedicated `refs/manifold/*`, no cloud, no telemetry.
- **Braindead-simple** — no config: a point that moves, a digest on launch. The
  eigenmath stays invisible.
- **Physics, not knobs** — projection coefficients and co-change centrality are
  measurements, not tuning sliders.
- **Manifold-universal** — the *time axis* and the *structure measure* are the
  portable parts; the git capture (`stash create`, `log`, `blame`) is just the
  swappable edge source. Keep that seam clean for the eventual non-git corpora.

---

## 6. Sources

**Continuous-snapshot model** — Jujutsu working copy
https://docs.jj-vcs.dev/latest/working-copy/ · operation log
https://docs.jj-vcs.dev/latest/operation-log/ · `jj op diff` (structural state
diff) https://man.archlinux.org/man/extra/jujutsu/jj-operation-diff.1.en ·
git-branchless event log / `git undo`
https://github.com/arxanas/git-branchless/wiki/Command:-git-undo · "Use Jujutsu,
not Git" (agents make dense op-streams)
https://slavakurilyak.com/posts/use-jujutsu-not-git · commits-are-snapshots-not-diffs
https://github.blog/open-source/git/commits-are-snapshots-not-diffs/ · reflog's
limits (can't recover uncommitted work)
https://blog.codeminer42.com/git-reflogs-a-guide-to-rescuing-your-lost-work/

**Catch-up / ownership / coupling** — Krüger et al., *Do You Remember This Source
Code?* (ICSE 2018 — own-code familiarity; ownership rs≈0.55) · code-maat change
coupling (lift / Dice) https://github.com/adamtornhill/code-maat · git-standup
(yesterday, not a gap) https://github.com/kamranahmedse/git-standup · GitHub
Activity has no "since last visit" boundary (long-standing request).
