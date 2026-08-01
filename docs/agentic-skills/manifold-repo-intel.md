---
name: manifold-repo-intel
description: >-
  Use to make your own edits structure-aware in a git repo where Manifold is
  installed and running: what a file couples to, what else you should touch,
  which files to read under a budget, who knows the code, how the repo is shaped.
  Drives Manifold's read-only intel commands, which spend no model call and
  answer from the warm coupling graph.
---

# Manifold repo intel

Before you touch a file, ask the graph what it connects to. These are Manifold's
read-only questions to the warm engine: coupling, volatility, centrality,
spectral subsystems, diffusion. They **cost no model call** and answer in a
round-trip once the engine is warm. Where `review` / `muse` / `shake` run
Manifold's AI *for* the user, this cluster makes an agent's *own* edits smarter.

**Designed for Manifold 0.2.0-beta.** If anything here disagrees with `manifold
--help`, trust the binary and flag the skill.

## The primitives

- **Coupling:** how often two files change together, as a score. The spine of
  most of these commands.
- **Volatility:** how much a file churns; z-scores say whether that is unusual
  for the repo.
- **Integrity:** how authored vs generated a file reads (low = likely
  generated).
- **Centrality:** total coupling mass; hub vs leaf.
- **Diffusion:** signal spread across the graph, used to predict a diff's
  *ripple*.

## Before you start

- **Any repo,** via `--repo <path>` or from inside a checkout. Read-only.
- **Engine-backed commands wait up to ~15s** on the first call while the graph
  warms (see the umbrella's "The warmth, in numbers"). None spend a model call.
- File arguments take `--files` / `--file` / `--paths` / `--seeds` / `--changed`
  (comma-separated); a lone bare word is treated as `--query`.

## What connects to what

| Command | Answers | Key output |
| --- | --- | --- |
| `blast-radius --files <paths> [--limit n]` | What else moves when I touch these? | `results[]` `{path, coupling, volatility, integrity}` |
| `suggest --files <paths>` | What did I forget to change with these? | `suggestions[]` `{path, score, anchor}` |
| `context --files <paths> [--budget chars]` | What should I read first, under a budget? | `admitted[]` `{path, coupling, estimatedChars}` (default budget 50000) |
| `coherence --files <paths>` | Do these files belong together? | `coherence` 0 to 1 + `assessment` (tight/moderate/mixed) |
| `impact --diff <text> [--limit n]` | Predicted ripple of this diff? | `sources[]`, `ripple[]` `{path, phi, coupling}` |

```
manifold blast-radius --files lib/backend/git.dart --json | jq '.result.results'
manifold suggest --files lib/backend/git.dart --json | jq '.result.suggestions[].path'
manifold context --files lib/features/diff/diff_shell.dart --budget 30000 --json | jq '.result.admitted'
```

## What is this file

| Command | Answers | Key output |
| --- | --- | --- |
| `profile --file <path>` | Numbers on one file | `volatility`, `integrity`, `centrality`, `touchCount` |
| `explain --file <path>` | One-line characterization | `summary` (e.g. "high-centrality hub, above-average churn") |
| `who-knows --file <path>` | Who to ask | `experts[]` `{email, commits, share}` |
| `recent --files <paths> [--limit n]` | Recent commits near it and its neighbors | `commits[]` `{hash, author, subject, date}` |
| `test-map --files <paths>` | Which tests cover this | `tests[]` `{path, coupling, anchor}` |

`who-knows` and `recent` read git history directly, so they answer before the
engine is warm.

## Shape of the whole repo

| Command | Answers | Key output |
| --- | --- | --- |
| `architecture` | Subsystem map | `subsystems[]` `{label, fileCount, density, avgVolatility, sample}` |
| `search --query <text> [--limit n]` | Find files by name | `results[]` `{path, relevance}` |
| `deadcode` | Files nothing live imports | `fullyDead[]`, `testZombies[]`, `joints[]` |

Two limits to plan around:

- **`search` matches path tokens, not content.** It is a filename finder (TF-IDF
  over path segments), not semantic or full-text search.
- **`deadcode` is reachability over Dart packages** (it reads each `pubspec.yaml`
  and walks the import closure); a non-Dart repo reports no packages. `joints[]`
  are load-bearing files: delete one and N others are orphaned.

## How to wield it

- **Before editing a file:** `blast-radius` for the ripple, `suggest` for the
  peers you would miss, `context` to load the right neighbors under a token
  budget.
- **In an unfamiliar repo:** `architecture` for the map, `search` to locate by
  name, `profile` / `explain` on what you land on.
- **Sizing a change set:** `coherence` says whether a file set is one change or
  several.

## Not this skill

- Model-backed review of a change: [code review](manifold-code-review.md).
- Model-backed brainstorm: [muse](manifold-muse.md).
- Model-backed audit of settled code: [bug shaker](manifold-bug-shaker.md).
