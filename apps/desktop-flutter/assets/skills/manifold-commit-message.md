---
name: manifold-commit-message
description: >-
  Use when writing the commit message for uncommitted work in a git repo where
  Manifold is installed and running. Drives `manifold commit-message`, which
  reads the staged and unstaged diff through the warm coupling graph and returns
  a message in the structure, voice, and coverage the user configured. Prints the
  message alone on stdout so it pipes into git.
---

# Manifold commit message

`manifold commit-message` writes the message for the change you are sitting on.
It reads the same diff the app's commit composer reads, grounded in the coupling
graph, and returns prose in the **user's own** configured format — not a generic
house style you would have to rewrite.

The question it answers is "what did this change do, in their words?"

**Designed for Manifold 0.2.0-beta.** If anything here disagrees with `manifold
--help`, trust the binary and flag the skill.

## Before you start

- **Working tree only.** A commit that exists already had its message written
  when it was made; the command refuses `--commit` / `--range` and points you at
  `git log`. Target a repo with `--repo <path>`, or run from inside one.
- **Needs an open Manifold window** (no daemon yet). `manifold ping` confirms it.
- **One model call**, on the category the user assigned to commit messages (see
  the umbrella's "Choosing the model"). `--model <id>` overrides the specific
  model within that category.

Read-only: it never stages, commits, or edits. It writes text and hands it to
you.

## The format is the user's

Three settings shape the output, and they are theirs, not yours:

| Setting | What it decides |
| --- | --- |
| `structure` | the shape — subject only, subject + body, bullets |
| `voice` | the register — imperative, verb-led, descriptive |
| `coverage` | how much of the diff the body accounts for |

`manifold state` reports all three before you spend a call, and the result
echoes them under `settings.commitMessage`. If a message comes back in a shape
you did not expect, that is the user's configuration — read it, do not fight it.

`--why` is **subject matter, not styling**. It reaches the model as the
author's own notes, and its content cannot escape that section — it can never
write into the format block or the user's standing prompt.

That is a structural boundary, not a mind-control one: a sentence in there that
reads like an order may still sway the model, because nothing can stop prose
from being persuasive. So the rule is a convention you keep, not a wall the
tool enforces. Tell it *what happened*; the shape is already the user's.

A note longer than the prompt's own scaffolding is refused rather than
truncated — an oversized one would push the diff out of the prompt and the
message would describe a change the model never saw.

## Run it

```
manifold commit-message                             # the whole dirty tree
manifold commit-message --files lib/backend/git.dart   # scope to files
manifold commit-message | git commit -F -           # the whole point
manifold commit-message --existing "wip: half done" # improve a draft
manifold commit-message --why "closes #412"         # what the diff can't show
```

- **`--files` / `--file`** narrow which dirty files the message describes.
- **`--existing <msg>`** hands over a draft to improve rather than replace, for
  when the user has already started writing.
- **`--why <text>`** carries what you know and the diff does not: the intent,
  the issue it closes, the review finding it answers, that it is step two of
  three.

**stdout carries the message and nothing else**, which is what makes the pipe
safe. Provenance — files covered, model, format — goes to stderr, where it
cannot end up in the commit.

## Reading the result

Add `--json` and read `.result`:

```
manifold commit-message --json | jq -r '.result.message'
manifold commit-message --json | jq '.result | {model, scope, files}'
manifold commit-message --json | jq '.result.settings.commitMessage'
```

- **`message`**: the text. The whole payload.
- **`files`** `{reviewed, total}`: how much of the dirty tree it described.
- **`model`**, **`promptChars`**, **`diffChars`**, **`inputTokens`** /
  **`outputTokens`**: what it cost and what it read.
- **`settings`**: the configuration that produced it.
- **A field-less result is a failure**, not an empty message: the command exits
  non-zero on a hung or empty run. Surface it rather than committing nothing.

## Not this skill

- Judge whether the change is correct before committing:
  [code review](manifold-code-review.md).
- Decide where the change should go next: [muse](manifold-muse.md).
- Read an existing commit's message: that is `git log`, not Manifold.
