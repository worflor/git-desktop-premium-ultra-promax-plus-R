---
name: manifold-bug-shaker
description: >-
  Use when auditing an entire codebase for latent bugs, including code that
  history-based review never looks at, in a git repo where Manifold is installed
  and running. Drives `manifold shake`, a resumable region-by-region AI audit of
  files as they EXIST (not as they changed), with a plan mode that spends no
  model call.
---

# Manifold bug shaker

`manifold shake` audits the codebase itself, region by region. It is the
whole-codebase counterpart to [code review](manifold-code-review.md): review
asks "is this *change* right?", shake asks "what is *wrong* with the code already
here?", including files nothing has edited in years, where unexamined bugs
survive.

The difference is structural. A history sweep only covers code that *changed*.
Shake's domain is `git ls-tree`: the files that **exist** at HEAD, so code
written once and never touched again is in scope rather than invisible.

The question it answers is "what is hiding in code no one has looked at?"

**Designed for Manifold 0.2.0-beta.** If anything here disagrees with `manifold
--help`, trust the binary and flag the skill.

## Before you start

- **Any repo:** `--repo <path>`, or run from inside one.
- **Needs an open Manifold window** (no daemon yet). `manifold ping` confirms it.
- **`--plan` first, always.** It shows the order and honest coverage for no model
  call. Look before you spend.
- **Model:** shake uses the same **Quality** category and double-check setting as
  `review` (see the umbrella's "Choosing the model"). `--model <id>` overrides
  the specific model within that category. `manifold state` reports what is
  configured, and every sweep echoes it under `settings`.

Read-only: it reads blobs from the object store and calls a model. It audits
HEAD's content regardless of what is currently uncommitted.

## The primitives

- **Region.** The unit of work: a few files audited together, sized to what one
  model call can read. Grouped by spectral community where the engine has one, by
  directory otherwise. Named after the deepest directory its files share.
- **Ledger.** A per-repo record of what has been examined at its *current*
  content. It makes the sweep a **fixpoint across runs**: what a run does not
  reach stays pending with its place in the order, so repeated runs converge on
  everything. It prunes records for deleted or renamed paths.
- **Audit result.** Per region, the same shape as a review: `score`, `verdict`,
  `summary`, `findings[]`, `observations[]`.

## Capabilities

```
manifold shake --plan                 # order + coverage, no model call
manifold shake                        # audit the next 1 region
manifold shake --regions 5            # audit the next 5 regions
manifold shake --reset                # forget the ledger and start over
manifold shake --json | jq '.result.audited[] | {region, score, verdict, findings}'
```

Run `shake` repeatedly to walk the whole tree; the ledger remembers between runs.
`--regions` trades cost for coverage (default 1).

## Inner workings

- **The order is reproducible**, not a weighted score: unexamined regions first,
  then by churn since last examined, then by how much was never human-reviewed,
  then by path. Two `--plan` runs agree.
- **Coverage is stated, never silent.** Excluded files are named and counted by
  reason: `generated` (machine-written), `notSource` (docs, data, assets),
  `tooLarge` (bigger than one audit admits). A region a run does not reach is
  reported pending, not dropped.
- **A cold engine still covers everything.** If the engine has not warmed (shake
  waits up to **60s**), it groups by directory and orders by path instead of by
  community and churn: less smart grouping, same coverage. `--plan`'s
  `engineReady` tells you which you got.
- **Cost scales with regions.** Each region is one model call (two with
  double-check on), synchronous, and can take a while. Start small, read the
  findings, continue.

## Reading the result

- **Progress:** `examinedFiles` / `domainFiles`, `pendingFiles`,
  `pendingRegions`, `complete` show how far the sweep has gotten.
- **`excluded`:** what was skipped and why.
- **`audited[]`:** this run's findings per region. A region with an `error` is
  *not* marked examined; it stays pending, so a failed region never retires
  unread.
- **`--plan`** lists upcoming `regions[]` with `files`, `unexamined`, and
  `neverHumanReviewed` counts, to judge where to spend first.

## Not this skill

- Review a specific change or commit: [code review](manifold-code-review.md).
- Brainstorm where a change could go: [muse](manifold-muse.md).
- Write the message for a change: [commit message](manifold-commit-message.md).
