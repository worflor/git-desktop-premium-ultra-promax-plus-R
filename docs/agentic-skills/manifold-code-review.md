---
name: manifold-code-review
description: >-
  Use when an agent should get an AI code review of changes in a git repo where
  Manifold is installed and running: uncommitted work, a specific commit, or a
  revision range. Drives `manifold review` for a review grounded in the repo's
  coupling graph, and `manifold review-evidence` to inspect the exact context
  with no model spend. Covers scoping to the whole dirty tree, a set of files, or
  a single file.
---

# Manifold code review

`manifold review` runs the desktop app's AI code reviewer from the terminal and
returns a verdict, score, findings, and observations. It is grounded in the
repo's coupling graph (what co-changes with the files under review), not grep,
so it catches ripple the diff alone does not show.

The question it answers is "is this change right?" For "what could it become?"
use [muse](manifold-muse.md); for "what is wrong with code nobody has touched in
years?" use [bug shaker](manifold-bug-shaker.md).

**Designed for Manifold 0.2.0-beta.** If anything here disagrees with `manifold
--help`, trust the binary and flag the skill.

## Before you start

- **Any repo on disk:** pass `--repo <path>`, or run from inside a checkout.
- **Needs an open Manifold window** (no daemon yet). `manifold ping` confirms
  it; if it answers `manifold is not running.`, ask the user to open one.
- **A model must be configured** in the app. If none is, the command says so;
  relay it.

Read-only: never stages, commits, or edits. Safe on a dirty tree.

## What you review: the subject

By default `review` looks at the **working tree** (staged and unstaged
together). To review history instead:

| Subject | Command |
| --- | --- |
| Uncommitted work (default) | `manifold review` |
| The commit just made | `manifold review --last` |
| A single commit | `manifold review --commit <rev>` |
| A range, endpoints compared | `manifold review --range <A..B>` |
| What a branch adds (from the merge base) | `manifold review --range <A...B>` |

`<rev>` is anything git understands (`HEAD~3`, a tag, a branch, an abbreviated
OID). Two-dot vs three-dot is git's own: `A..B` compares endpoints, `A...B`
compares from the merge base. A bare `--range <rev>` reviews that one commit.
`--last`, `--commit`, and `--range` are mutually exclusive; passing more than
one is refused.

A merge commit is reviewed against its first parent, and the scope label says
so. A shallow clone whose boundary commit has no parent cannot be reviewed; the
error points to `git fetch --unshallow`.

## How much of it: scope

Independently of the subject, narrow *which files* get reviewed. File arguments
accept `--files`, `--file`, `--path`, `--paths`, `--seeds`, `--changed`
(comma-separated); omit them for everything.

| Breadth | Working tree | History target |
| --- | --- | --- |
| Whole subject | `manifold review` | `manifold review --commit <rev>` |
| A set of files | `manifold review --files a.dart,b.dart` | `manifold review --commit <rev> --files a.dart,b.dart` |
| One file | `manifold review --file lib/backend/git.dart` | `manifold review --range <A..B> --file lib/backend/git.dart` |

On the working tree the file list *selects* dirty files. With a history target
it *scopes the revision diff* to those paths. Scope to a set or one file when a
change is large and you want the reviewer (and the user's budget) on one part.

## The model and the double-check

`review` uses the **Quality** category by default (see the umbrella's "Choosing
the model"). `--model <id>` swaps the specific model within that category; it
cannot move the review to Fast. The user can enable a **double-check** pass in
review settings, which runs a second verification call: better findings, roughly
double the time and cost. You cannot toggle it from the CLI; the result's
`doubleCheck` field reports whether it ran.

`manifold state` shows the model, effort, and double-check setting before you
spend, and every review echoes the same block under `settings`.

## Reading the result

Add `--json` and read `.result`:

```
manifold review --json | jq '.result | {verdict, score, summary}'
manifold review --json | jq '.result.findings[] | {title, severity, file, hunk, evidence, why}'
manifold review --json | jq '.result.observations[] | {title, detail, file}'
```

- **`verdict`**, **`score`**: the top-line judgement.
- **`findings[]`**: actionable items, each with `title`, `severity` (`warn` /
  `critical` are the ones that matter), `file`, `hunk`, `evidence`, `why`.
- **`observations[]`**: lower-stakes notes with `title`, `detail`, `file`.
- **`scope`**: what was actually reviewed, resolved (`commit a1b2c3d - subject`,
  `main...feature (12 commits)`). Check it against what you asked for.
- **`files`**, **`model`**, **`enrichment.coupling`**, **`inputTokens`** /
  **`outputTokens`**, **`timing`**: cost and coverage.

**A field-less result is a failure, not a clean bill.** A result missing `score`
/ `summary` exits code 2 (app-side failure or a hung provider). Surface the
error and retry; restart Manifold if it persists. Never report "no findings"
off an empty result.

## See what the model is fed, or run it yourself

`manifold review-evidence` runs the identical gather and prompt assembly, but
stops before the model. No token cost. It returns the full assembled prompt
under `.result.prompt` and per-phase telemetry under `.result.diagnostics`.

- **Debug a review:** read the exact diff, coupling context, and phase telemetry
  the model saw.
- **Preview cost:** `promptChars` / `diffChars` size the call before you spend.
- **Bring your own model.** The review's model is the user's GUI choice and you
  cannot change it from the CLI, so when it is out of quota or its provider is
  down, you are not stuck:

  ```
  manifold review-evidence --json | jq -r '.result.prompt'
  ```

  That is the entire grounded prompt: diff, coupling context, scene. Run it on a
  model you can reach and you get the same review. Prefer plain `review` when the
  configured model works; reach for the prompt when the model is what blocks you.

`review-evidence` takes the same subject/scope flags as `review`, plus `--diff
<path>` to replay a frozen patch as the whole subject.

## Reading the human (non-JSON) output

The terminal view leads with `<score>  <verdict> · <n>/<total> files · <model> ·
<time>`, then scope, summary, each finding (`▲` = warn/critical, `△` = the rest)
with location, evidence, and a dim `→ why`, then observations. Prefer `--json`
when you will act on the result.

## Latency

- The first review of a **cold** repo waits up to ~15s while the engine warms;
  later reviews are fast unless history moved.
- The model call is the long pole. A hung provider is backstopped at **22
  minutes per call** (a double-checked review budgets two, ~44) before the
  command fails. Do not kill a review that is still thinking.

## Not this skill

- Whole-codebase audit of settled code: [bug shaker](manifold-bug-shaker.md).
- Where a change could go: [muse](manifold-muse.md).
- Write the message once it passes: [commit message](manifold-commit-message.md).
- Ripple only, no model: `manifold blast-radius --files <paths>` or `manifold impact --diff <text>`.
