---
name: manifold-muse
description: >-
  Use when brainstorming forward directions for uncommitted work in a git repo
  where Manifold is installed and running: where a change could go, not whether
  it is correct. Drives `manifold muse`, a two-model ideation pass grounded in
  the repo's coupling graph that returns proposals across ambition tiers. Works
  on the working tree only, not on commits.
---

# Manifold muse

`manifold muse` is an ideation pass over your **current** change. It does not
judge the diff (that is [code review](manifold-code-review.md)); it proposes what
the change could *become*. Two models run in sequence: a brainstorm pass spews
raw ideas, a synthesis pass shapes them into proposals anchored to real points
in the code. Both are grounded in the coupling graph.

The question it answers is "where does this go from here?"

**Designed for Manifold 0.2.0-beta.** If anything here disagrees with `manifold
--help`, trust the binary and flag the skill.

## Before you start

- **Working tree only.** Muse works on work in progress; it refuses `--commit` /
  `--range` (use `review` for history). Target a repo with `--repo <path>`, or
  run from inside one.
- **Needs an open Manifold window** (no daemon yet). `manifold ping` confirms it.
- **Two model calls, always**, so it costs more than a single review. By default
  the brainstorm runs on **Fast** and the synthesis on **Quality** (see the
  umbrella's "Choosing the model"). `--model <id>` overrides the specific model
  within each.

Read-only: never stages, commits, or edits.

## The primitives

Output is a set of **proposals**, each carrying:

- `title`: a short, feature-shaped name.
- `vision`: one or two sentences of what it would be.
- `foothold`: the thing already in the code that makes it reachable.
- `citations`: the paths (or `path:line`) it hangs on.

Proposals span four **ambition tiers**, low to wild:

| Tier | Reaches for |
| --- | --- |
| `spark` | the immediate next step |
| `current` | a present-tense extension |
| `horizon` | grand but reachable |
| `fever` | absurd, maybe impossible |

Raw phase-one ideas are kept in `brainstormIdeas[]` for breadth over polish.

## Run it

```
manifold muse                                   # the whole dirty tree
manifold muse --files lib/backend/git.dart      # scope to files (comma list ok)
manifold muse --json | jq '.result.proposals[] | {tier, title, vision, foothold, citations}'
```

`--files` / `--file` narrow which dirty files seed the ideation.

## Reading the result

- **`proposals[]`** grouped by `tier` are the payload: `vision` for the idea,
  `foothold` for whether it is grounded.
- **`brainstormIdeas[]`** is the raw pass.
- **`tokens`** splits brainstorm vs synthesis cost; **`warnings`** flags a
  synthesis that did not parse cleanly (some proposals may be missing).
- **A field-less result is a failure**, not "no ideas": the command exits
  non-zero on an empty or hung run. Surface it.

## Not this skill

- Judge whether a change is correct: [code review](manifold-code-review.md).
- Audit settled code for bugs: [bug shaker](manifold-bug-shaker.md).
