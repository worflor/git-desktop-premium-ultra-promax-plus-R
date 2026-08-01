# Agentic skills

The Manifold desktop app ships a CLI: `manifold`, a bridge into its own running
window. It connects over a loopback socket and prints what that window's engine
returns. The window has already paid for the git derivation, the Logos
diffusion, and the spectral basis, so the CLI answers warm.

That makes Manifold something a coding agent can *wield*. Point an agent at a
repo the user has open and it can ask the same engine the UI asks: what does
this change couple to, what did the reviewer see, where are the bugs nobody has
touched in years. Answers come back as JSON, so the agent consumes structure
instead of scraping a screen.

These skills package that capability. Each teaches an agent to drive one
surface: the command, its scopes, its output, and how it fails.

## The premise

Manifold is already reading the user's repository: the coupling graph built,
signal diffused, the spectral basis warm. The CLI is your seat at that running
engine. Two things before you start:

- **You are not fenced into the repo you are standing in.** Point `--repo
  <path>` at any git checkout and the engine resolves it by path; it need not be
  registered, open, or current. From inside a repo the user has open, bare
  commands just work.
- **The engine lives in an open window.** There is no daemon yet, so a running
  Manifold window is where the warm graph is. `manifold ping` tells you it is
  awake; if it answers `manifold is not running.`, ask the user to open one. If
  Manifold is not installed, there is nothing to drive: use ordinary git and say
  so. It lives at
  <https://github.com/worflor/git-desktop-premium-ultra-promax-plus-R>.

## The shared invocation model

Every skill inherits the same contract.

```
manifold <command> [--json] [--repo <path>] [command options]
```

- **`--json` is the seam for agents.** Without it you get a pretty terminal
  view; with it, the raw JSON-RPC envelope, result under `.result`. Pipe it
  through `jq`.
- **Repo resolution** goes `--repo`, then `git rev-parse --show-toplevel` of the
  current directory, then the workspace of the connected window (it reaches the
  window whose workspace best matches your directory). `manifold index`
  registers a repo as a project; every other command works on a checkout that
  was never added.
- **Calls are synchronous.** The command blocks until the result arrives; there
  is no queue to poll. An intel command returns in a round-trip; an AI command
  (`review`, `muse`, `shake`) can take seconds to minutes.
- **Progress goes to stderr, result to stdout**, so piping stdout stays clean.
  In a terminal, progress is a live status line; captured (no terminal), each
  phase arrives as its own line.
- **Everything is read-only.** No command mutates the repo, index, or history.
  They read, diffuse, and (for the AI ones) call a model the user configured.
  Safe on a dirty tree.

A command that hits a real problem *throws*, so a non-zero exit is a real
failure. The AI skills treat a field-less result as failure and exit non-zero
rather than report a false clean bill.

## The warmth, in numbers

"Warm" has real edges; plan around them. Measured against the current build:

- **Warmth ends on a switch, not a timer.** The active repo's engine stays hot.
  The moment the user makes a *different* repo active in the app, every other
  repo's engine is evicted at once. There is no expiry clock.
- **A repo you reach with `--repo` warms on first touch and stays warm.** The
  first engine-backed call builds its graph (the CLI waits up to **15s**;
  `index` and `shake` up to **60s**), then answers warm on repeated calls,
  alongside the active repo, until the next active-repo switch evicts it. The
  cost is the first call; the rest are fast.
- **Freshness is automatic.** Every engine-backed call probes HEAD first: it
  reuses the warm graph if history has not moved, and rebuilds only after a
  commit, merge, or reset. You never request a refresh and never get a stale
  answer.

## Choosing the model

Every AI skill (`review`, `muse`, `shake`) calls a model the **user** configured
in the app. Two categories exist, **Quality** and **Fast**, each routed to a
detected model in settings.

- **Defaults:** `review` and `shake` use Quality; `muse` uses Fast to brainstorm
  and Quality to synthesize.
- **From the CLI:** `--model <id>` overrides the specific model, but only within
  the category that feature already uses. An id outside that category silently
  falls back to the category default. You cannot switch Fast and Quality from
  the CLI.
- **GUI only:** which category a feature uses, which model each category points
  at, and the review's "double-check" pass. If a run uses a different model than
  you expected, that is the user's config in Settings, not something to force
  from the command line.
- **You never have to guess what that config is.** `manifold state` reports the
  model, effort, and prompt behind every AI command, the muse's strand loadout,
  and the commit-message format. Every AI command also echoes the same block
  under `settings` in `--json`, so the answer arrives with the result that came
  from it.
- **The escape hatch:** if the configured model is out of quota or down,
  `review-evidence` hands you the exact prompt `review` would have sent, to run
  on a model you control (see the code-review skill).

## The fleet

Five skills. The first four spend a model call the user configured; the fifth
is free.

| Skill | Command(s) | Question it answers |
| --- | --- | --- |
| [Code review](agentic-skills/manifold-code-review.md) | `manifold review` | Is this change right? |
| [Muse](agentic-skills/manifold-muse.md) | `manifold muse` | What could this change become? |
| [Bug shaker](agentic-skills/manifold-bug-shaker.md) | `manifold shake` | What is wrong with code nobody has touched in years? |
| [Commit message](agentic-skills/manifold-commit-message.md) | `manifold commit-message` | What did this change do, in the user's words? |
| [Repo intel](agentic-skills/manifold-repo-intel.md) | `blast-radius`, `context`, `suggest`, … | What does this file connect to, and what should I read or touch? (no model call) |

Repo intel makes an agent's *own* edits structure-aware: `blast-radius`,
`suggest`, `context`, `coherence`, `impact`, `architecture`, `who-knows`,
`recent`, `test-map`, `profile` / `explain`, `search`, `deadcode`. `index`
(validate + warm + register) sits alongside. Run `manifold help` for the schema
or `manifold --help` for the list.

`manifold state` needs no skill of its own: it answers what the app is
configured to do, and every AI command echoes the same block, so read it
whenever a result surprises you.

## Why pipe a command instead of reading files yourself

You can always open files and reason about them. What you cannot cheaply
reconstruct is what Manifold already computed:

- **A warm engine.** The coupling graph and spectral basis come from the full
  commit history. Rebuilding that per question is the cost the running app
  already ate.
- **Grounded context.** The reviewer's evidence is diffused across the repo's
  geometry, not grepped. `review-evidence` shows it with no model spend.
- **Structured output.** `--json` returns findings, verdicts, and coupling
  scores as data.

Reach for a skill when the question is how the *repo* relates to a change
(coupling, ripple, grounded review, whole-codebase sweep). Stay with ordinary
reading for a single file's contents in isolation.

## Versioning and drift

These skills are **designed for Manifold 0.2.0-beta.** Commands, flags, and
fields can shift. The binary is the source of truth: if a skill disagrees with
`manifold --help` or `manifold help`, trust the binary and tell the user the
skill looks stale. `review-evidence` and `shake --plan` show real behaviour
without spending a model call.
