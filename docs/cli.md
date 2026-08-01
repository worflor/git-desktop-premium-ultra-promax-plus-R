# The `manifold` CLI

A thin command-line bridge into the *running* desktop app. It connects to an open
Manifold window over a loopback socket and prints whatever that window's engine
hands back. The app has already paid for the git derivation, the Logos diffusion
and the spectral basis, so the CLI answers warm.

Source: `apps/desktop-flutter/bin/manifold_cli.dart`. Handlers live in
`apps/desktop-flutter/lib/backend/ipc/pipe_commands.dart`.

## Running it

The app has to be open for any command to work. If it isn't, you get
`manifold is not running.` and exit code 1.

```
dart run bin/manifold_cli.dart <command> [options]
```

Most people compile it once and drop it on `PATH` so it's just `manifold`:

```
dart compile exe bin/manifold_cli.dart -o manifold
manifold status
manifold review
manifold blast-radius --files lib/backend/git.dart
```

Which repo a command targets is resolved in this order:

1. `--repo <path>` if you pass one.
2. `git rev-parse --show-toplevel` of the current directory.
3. The workspace of the app window the CLI connected to.

So from inside a repo that a Manifold window has open, bare `manifold status`
just works.

## Commands

Run `manifold help` for the machine-readable schema, or `manifold --help` for
this list. `manifold --version` (`-v`) prints the build version and a one-line
license summary. Anything that calls a model or diffuses the graph streams a progress
line to stderr while it works (`review`, `review-evidence`, `muse`, `impact`,
`dream`, `deadcode`, `index`, `shake`, `commit-message`).

| Command | What it returns |
| --- | --- |
| `status` | Branch, ahead/behind, dirty files |
| `state` | What Manifold is configured to do: model per command, muse strands, prompts, commit format |
| `commit-message` | Writes the commit message for the current change. The message alone on stdout |
| `index [--check]` | Validate a repo, warm its engine, and register it as a project (`--check` skips registering) |
| `review [--files <paths>]` | AI code review. Working tree by default; `--last`, `--commit <rev>`, or `--range <A..B>`/`<A...B>` review history |
| `review-evidence [--files <paths>]` | The gathered review context + phase telemetry, no model call. `--diff <path>` replays a frozen patch |
| `shake [--plan] [--regions <n>]` | Audit the codebase region by region, resuming where the last run stopped (`--plan`: no model call) |
| `deadcode` | Files no live surface imports — fully dead plus test-zombies, plus load-bearing joints |
| `muse [--files <paths>]` | AI brainstorm over the diff |
| `muse --strands <list>` | Brainstorm carrying exactly these strands instead of the configured loadout |
| `blast-radius --files <paths>` | Co-change neighbors of the given files |
| `context --files <paths>` | Coupling-ranked reading list under a `--budget` char cap |
| `suggest --files <paths>` | Coupled files you probably meant to touch too |
| `coherence --files <paths>` | How cohesive a file set is, 0–1 |
| `profile --file <path>` | Volatility, integrity, centrality, touch count |
| `explain --file <path>` | One-line natural-language characterization of a file |
| `test-map --files <paths>` | Tests coupled to the given sources |
| `who-knows --file <path>` | Expert authors for a file, by commit share |
| `recent --files <paths>` | Recent commits near a file and its coupling neighbors |
| `search --query <text>` | Path-token code search (TF-IDF over path segments) |
| `architecture` | Spectral subsystem map |
| `dream` | A Logos phrase for the current diff |
| `impact --diff <text>` | Predicted ripple of a raw diff |
| `diff [--file <path>]` | Raw diff text |
| `repos` | Repos the app currently knows about |
| `ping` | Health check |

The two you'll reach for most from an agent are `blast-radius` (what else moves
when I touch this) and `review` / `review-evidence` (what the app's reviewer
sees). `review-evidence` is the honest one for debugging: it's exactly the
context the model would get, minus the model, so you can see gaps and phase
timings without spending tokens.

### Knowing what you're about to get

An agent can't see the settings window, so it doesn't have to guess: `state`
reports the model, effort, prompt and format configured for every AI command,
and every AI command echoes the same block under `settings` in `--json`
output. If a review came back from a different model than you expected, the
answer is in the same response as the review.

`commit-message` puts the message — and nothing else — on stdout, so it pipes:

```sh
manifold commit-message | git commit -F -
```

Provenance (files, model, format) goes to stderr, where it can't end up in the
commit.

`--why <text>` adds what the diff can't show — intent, an issue reference, the
finding it answers. Its content cannot escape into the format block or the
user's standing prompt, so it can't rewrite their configuration; it is still
prose a model reads, so putting instructions there is a convention you break at
your own cost, not something the tool prevents. Oversized notes are refused
rather than truncated.

### Choosing muse strands

The muse carries a *quiver* of strands, each a different walker: `ghost`
(what came before), `spark` (the next step), `echo` (analogues), `current`
(present-tense extension), `vertigo` (adjacent risks), `horizon` (reaching
forward), `mirror` (inversions), `fever` (the full dream). `muse` uses the
loadout configured in the app unless you name strands yourself:

```sh
manifold muse --strands vertigo,ghost     # what could break, and what came before
manifold muse --strands spark:3,fever     # three sparks and a fever
```

A name that isn't a strand is refused rather than dropped — a typo that
quietly produced a smaller muse would look exactly like success.

## Options

| Flag | Effect |
| --- | --- |
| `--json` | Emit the raw JSON-RPC envelope instead of the pretty view |
| `--repo <path>` | Target a specific repo |
| `--commit <rev>` | `review`: review one commit instead of the working tree |
| `--range <spec>` | `review`: `A..B` compares endpoints, `A...B` compares from the merge base |
| `--last` | `review`: shorthand for `--commit HEAD` |
| `--plan` | `shake`: show the order and coverage, spend no model call |
| `--regions <n>` | `shake`: how many regions to audit this run (default 1) |
| `--reset` | `shake`: forget what has been examined and sweep afresh |
| `--check` | `index`: validate and warm without registering the repo |
| `--limit <n>` | Cap result count |
| `--model <id>` | Override model selection for AI commands |
| `--budget <chars>` | Context token budget |
| `--version`, `-v` | Print version and license summary, then exit |

File arguments are accepted under any of `--files`, `--file`, `--path`,
`--seeds`, `--changed` — pass whichever reads best for the command. A single
bare positional argument is treated as `--query`. With `--commit` / `--range`,
file arguments scope the revision diff rather than select dirty files.
`--last`, `--commit`, and `--range` name different revisions; pass at most one
(together they are refused, not ranked).

## Piping into agents

`--json` is the seam for scripting. Everything comes back as a JSON-RPC result
envelope, so an agent can consume the structure directly rather than scraping the
formatted output:

```
manifold blast-radius --files lib/backend/git.dart --json | jq '.result.results'
manifold review --json | jq '.result.findings[] | {title, severity, file}'
```

Errors surface as a top-level JSON-RPC `error` and a non-zero exit. (Handlers
that hit a real problem *throw* — a handler that returns an error map instead
would bury it under `result`, where the CLI reads it as success. Keep failures
throwing.)

## How the bridge finds the app

On startup each window binds a loopback TCP port and writes a lock file to the
app's data directory under `ipc/`:

- Windows: `%APPDATA%\gdpu\ipc\`
- macOS: `~/Library/Application Support/gdpu/ipc/`
- Linux: `$XDG_DATA_HOME/gdpu/ipc/` (or `~/.local/share/gdpu/ipc/`)
- Override everything with `GDPU_DATA_DIR` — then it's `$GDPU_DATA_DIR/ipc/`.

Each lock is `manifold-<pid>.lock` holding `{pid, port, workspace, startedAt}`.
The CLI reads every lock, drops ones whose process is dead, and picks the window
whose `workspace` is the longest prefix of your current directory. That's what
makes it multi-window-aware: run the CLI inside repo A and it reaches the window
that has A open, even if three other windows are running.

Wire format is length-prefixed JSON-RPC 2.0 over the socket: a 4-byte big-endian
length, then a UTF-8 body. Notifications with no `id` are progress frames and get
rendered on stderr as they arrive; the frame carrying the matching `id` is the
result. Progress renders as a live, in-place status line in a terminal, and as
one plain newline-terminated line per phase when stderr is not a terminal (a
piped or agent-captured run), so a long command is never silent. Protocol
constants live in `apps/desktop-flutter/lib/backend/ipc/pipe_protocol.dart`.

## When it doesn't connect

- `manifold is not running.` — no live window, or its lock got cleaned. Open the
  app and retry.
- Connects to the wrong repo — pass `--repo` explicitly, or `cd` into the repo so
  the workspace-prefix match resolves.
- Hangs on first call after opening a repo — the engine loads lazily; the first
  engine-backed command waits up to ~15s for the Logos engine to warm, then
  answers. Later calls are warm.
