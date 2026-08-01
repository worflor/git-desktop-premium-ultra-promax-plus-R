---
name: manifold-muse
description: >-
  Use when brainstorming forward directions for uncommitted work in a git repo
  where Manifold is installed and running: where a change could go, not whether
  it is correct. Drives `manifold muse`, a two-model ideation pass grounded in
  the repo's coupling graph that returns proposals across the strands the user
  configured, or the ones you name. Works on the working tree only, not on
  commits.
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

Each proposal comes from a **strand** — a walker with its own character. The
default loadout is the four ambition tiers, low to wild:

| Strand | Reaches for |
| --- | --- |
| `spark` | the immediate next step |
| `current` | a present-tense extension |
| `horizon` | grand but reachable |
| `fever` | absurd, maybe impossible |

Four more are lenses rather than tiers, and the user can carry them instead:

| Strand | Walks for |
| --- | --- |
| `ghost` | what this replaces, and why it was there |
| `echo` | analogues — where else this pattern lives |
| `vertigo` | adjacent risks — what this jeopardizes |
| `mirror` | the inversion — the question you are not asking |

`muse` carries whatever loadout the user configured (`manifold state` shows it)
unless you name strands yourself.

**In the JSON, the field is called `tier`** and carries the strand name — so a
proposal from `vertigo` arrives as `"tier": "vertigo"` even though vertigo is a
lens, not a tier. The name predates the lenses and is kept so existing readers
keep working; read it as "which strand".

Raw phase-one ideas are kept in `brainstormIdeas[]` for breadth over polish.

## Run it

```
manifold muse                                   # the whole dirty tree
manifold muse --files lib/backend/git.dart      # scope to files (comma list ok)
manifold muse --strands vertigo,ghost           # these strands INSTEAD of the loadout
manifold muse --strands spark:3,fever           # `name:count` asks for several
manifold muse --json | jq '.result.proposals[] | {tier, title, vision, foothold, citations}'
```

`--files` / `--file` narrow which dirty files seed the ideation.

`--strands` replaces the configured loadout for that run; the result reports
`strandsUsed` and `strandsOverridden` so you can tell which you got. A name that
is not a strand is refused rather than dropped — a typo that quietly produced a
smaller muse would look exactly like success.

## Reading the result

- **`proposals[]`** grouped by `tier` (the strand name, see above) are the
  payload: `vision` for the idea, `foothold` for whether it is grounded.
- **`brainstormIdeas[]`** is the raw pass.
- **`tokens`** splits brainstorm vs synthesis cost; **`warnings`** flags a
  synthesis that did not parse cleanly (some proposals may be missing).
- **A field-less result is a failure**, not "no ideas": the command exits
  non-zero on an empty or hung run. Surface it.

## Not this skill

- Judge whether a change is correct: [code review](manifold-code-review.md).
- Audit settled code for bugs: [bug shaker](manifold-bug-shaker.md).
- Write the message for the change: [commit message](manifold-commit-message.md).
