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
this list. Anything that calls a model or diffuses the graph streams a progress
line to stderr while it works (`review`, `review-evidence`, `muse`, `impact`,
`dream`, `deadcode`).

| Command | What it returns |
| --- | --- |
| `status` | Branch, ahead/behind, dirty files |
| `review [--files <paths>]` | AI code review of the diff (defaults to dirty files) |
| `review-evidence [--files <paths>]` | The gathered review context + phase telemetry, no model call |
| `deadcode` | Files no live surface imports — fully dead plus test-zombies |
| `muse [--files <paths>]` | AI brainstorm over the diff |
| `blast-radius --files <paths>` | Co-change neighbors of the given files |
| `suggest --files <paths>` | Coupled files you probably meant to touch too |
| `coherence --files <paths>` | How cohesive a file set is, 0–1 |
| `profile --file <path>` | Volatility, integrity, centrality, touch count |
| `test-map --files <paths>` | Tests coupled to the given sources |
| `who-knows --file <path>` | Expert authors for a file, by commit share |
| `search --query <text>` | Semantic code search |
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

## Options

| Flag | Effect |
| --- | --- |
| `--json` | Emit the raw JSON-RPC envelope instead of the pretty view |
| `--repo <path>` | Target a specific repo |
| `--limit <n>` | Cap result count |
| `--model <id>` | Override model selection for AI commands |
| `--budget <chars>` | Context token budget |

File arguments are accepted under any of `--files`, `--file`, `--path`,
`--seeds`, `--changed` — pass whichever reads best for the command. A single
bare positional argument is treated as `--query`.

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
result. Protocol constants live in
`apps/desktop-flutter/lib/backend/ipc/pipe_protocol.dart`.

## When it doesn't connect

- `manifold is not running.` — no live window, or its lock got cleaned. Open the
  app and retry.
- Connects to the wrong repo — pass `--repo` explicitly, or `cd` into the repo so
  the workspace-prefix match resolves.
- Hangs on first call after opening a repo — the engine loads lazily; the first
  engine-backed command waits up to ~15s for the Logos engine to warm, then
  answers. Later calls are warm.
