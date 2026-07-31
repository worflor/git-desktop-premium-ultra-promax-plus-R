# Manifold

A cross-platform desktop Git client for Windows and Linux. Built in Flutter, Dart, and a lot of spectral hypercomplex math.

[![woflo.dev](https://img.shields.io/badge/woflo.dev-2b2d42)](https://woflo.dev)
[![license](https://img.shields.io/badge/license-GPL--3.0%20%2B%20community--source-4a5568)](LICENSE.md)
[![platform](https://img.shields.io/badge/platform-windows%20%7C%20linux-4a5568)](#status)

<p align="center">
  <img src="pics/code-review-hero.webp" alt="Manifold reviewing a diff: files and evidence orbiting a central node while Logos diffuses signal across the repo" width="760">
</p>

> Manifold is a free Git client for Windows and Linux with a spectral engine (Logos) that reads your commit history as a graph of how files couple, then uses it for merge conflict prediction, grounded AI code review, and codebase maps. Works with GitHub, GitLab, and self-hosted Gitea, or fully offline with local-first pull requests and issues that need no remote.

## It's a Git client :]

Stage, commit, push, pull, diff, branch, merge, rebase, stash, cherry-pick,
reflog. The usual. If you've used GitHub Desktop, Sourcetree, Fork,
Tower or GitKraken; you already know the shape, and Manifold does that shape, a free alternative to them all. The
day-to-day stuff works how you'd expect it to.

Works with GitHub, GitLab (including self-hosted), and Gitea, syncing PRs and issues both ways. Or go local-first: with no remote at all, PRs and issues still live inside the repo, fully offline.

## Why you might care anyway

Manifold [literally](https://en.wikipedia.org/wiki/Literally) builds a *manifold* from your repository.
A weighted graph with spectral structure, continuously rebuilt as you work,
sitting under the client like scaffolding. Files are coordinates in a space
the engine knows how to navigate.

Driving this is **Logos for Git**, a relevance engine that diffuses
signal across the repo's spectral geometry. No grep. No
stitching heuristics together and praying. It asks the geometry where the signal
lands and tells you what it finds. Git-Logos is built on top of the
**Whisper Logos Attention Codec** (WLAC), a 0d entropy codec, and the **Whisper Engram Embedding Codec** (WEEC), a 256d semantic trajectory codec. 
> *turns out giving semantic meaning to arbitrary entropy is useful.*

What that looks like in practice:

- Manifold can map your diff to external file context automatically using repo history, the spectral graph, and an experimental execution flow engine; Filament.
  - It feeds LLM-powered Code Review, Muse Brainstorming, and Generate Message, all with *logos-backed* context. The one-shot gather stays cheap and fast, and a new optional read-only agentic harness explores outward from what Logos surfaces. It piggybacks Codex, so Codex and API models can go agentic (Claude Code can't host the harness, so it stays one-shot there).
  - There's a long-running debate in AI about whether the model matters more than the harness around it. Manifold takes the harness side literally: Logos and the evidence gather are the harness, the model is a guest. Not my first one either; my [college capstone](https://woflo.dev/blog/wdym/) put an LLM inside a live Minecraft JVM with real-time bytecode patching. This is that idea, pointed at git.
- Open any file. The client already knows what it connects to, how tightly, and through which channels.
- View changes by *geometric Atlas* (preview) rather than by file.
- PRs, worktrees, and branches get **Orbits**, orbital shapes drawn from the coupling graph, so related branches surface as merge risk even when they aren't touching the same files.
- See through a repo with X-Ray. Trace a feature across the tree. Find a file's
  structural siblings. Surface hotspots or keystone files.
- Bring your own model. Route the AI features through Cursor, Copilot, Codex, OpenRouter, or opencode.
- Plus the stuff a mature client needs: a scrubbable history timeline (Orrery, preview), image, video, and binary diffs, and a command palette tying it together.
- Speaks 14 languages. AI-drafted so every locale is complete from day one, human-corrected wherever a native speaker has stepped in, and the language picker tells you honestly which is which.

Oh yeah, and it's *free* ♥

### ...in monke terms..?

*monke add repo. repo get analyzed. monke see where banana generater was added vs banna VIEWER (monke doesnt add descriptions. too busy making banana generators in different languages). friend send monke spaghetti repo when monke prefer banana repo. Manifold show monke around the new repo as if monke's own repo. spaghetti turned lasagna. all with manifold*

Translation for the humans and the robots: Manifold hands you the lay of the land in a repo you didn't write, before you open a single file.

## Pics or it didn't happen

Every shot below is in a different theme. And that's only a fraction of them.

### The engine, made visible

<table>
<tr>
<td align="center" width="50%">
<img src="pics/manifold-view-nacre.webp" alt="Repo rendered as 3D geometric shapes with co-change links" width="400"><br>
<sub><b>Your repo as geometry.</b> files are shapes, co-change is distance · Nacre</sub>
</td>
<td align="center" width="50%">
<img src="pics/xray-lady-entropy.webp" alt="Repo X-Ray structural treemap with clusters" width="400"><br>
<sub><b>X-Ray the whole repo.</b> clusters, hotspots, keystone files, external coupling · Lady Entropy</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
<img src="pics/orbits-phosphor.webp" alt="Pull requests shown as orbital shapes with conflict prediction" width="400"><br>
<sub><b>PRs as orbits.</b> Manifold knows which branches will fight before you merge · Phosphor</sub>
</td>
<td align="center" width="50%">
<img src="pics/review-result-blackboard.webp" alt="Code review result with grounded findings and a score" width="400"><br>
<sub><b>The verdict, with receipts.</b> findings that point at the exact signal that found them · Blackboard</sub>
</td>
</tr>
</table>

<p align="center">
<img src="pics/xray-signals-redshift.webp" alt="X-Ray Signals tab listing hidden refs, machine-heavy commits, migrations, single-owner files, bursty work, and live engine metrics" width="520"><br>
<sub><b>Signals: the repo's character, made legible.</b> commit rhythm, machine noise, hidden refs, the quirks that make it itself · Redshift</sub>
</p>

### The everyday client

<table>
<tr>
<td align="center" width="50%">
<img src="pics/changes-kirby.webp" alt="Changes page with file list, commit box, and diff" width="400"><br>
<sub><b>The everyday loop.</b> stage, write, commit, with the engine mapping your diff underneath · Kirby</sub>
</td>
<td align="center" width="50%">
<img src="pics/history-petrichor.webp" alt="History view with a per-commit seismograph and treemap" width="400"><br>
<sub><b>History as a seismograph and worldline.</b> importance, churn, and branches woven into one thread. · Petrichor</sub>
</td>
</tr>
<tr>
<td colspan="2" align="center">
<img src="pics/worldline-kirby.webp" alt="A full repository's history drawn as a single worldline strand across 500 commits, from quiet stretches to bursts of activity" width="820"><br>
<sub><b>Zoom all the way out.</b> a repo's entire history as one strand, from calm stretches to storms · Kirby</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
<img src="pics/merge-bibble.webp" alt="Fullscreen three-way merge resolver" width="400"><br>
<sub><b>Three-way merges, fullscreen and per-file.</b> built for The Manual Way™ · Bibble</sub>
</td>
<td align="center" width="50%">
<img src="pics/line-staging-aether.webp" alt="Line-level diff staging" width="400"><br>
<sub><b>Line-level staging.</b> split a hunk down to just the lines that belong · Aether</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
<img src="pics/branches-helix.webp" alt="Branches page detecting absorbed, squashed, and merged branches with commit-activity sparklines" width="400"><br>
<sub><b>Branches, understood.</b> it tells absorbed from squashed from merged · Helix</sub>
</td>
<td align="center" width="50%">
<img src="pics/palette-redshift.webp" alt="Command palette searching repos, files, and actions" width="400"><br>
<sub><b>One palette for everything.</b> repos, files, actions. Right there · Redshift</sub>
</td>
</tr>
</table>

<p align="center">
<img src="pics/review-multilingual.webp" alt="One code review shown as diagonal panels: the same threads rendered in English, Japanese, Russian, and Korean, each in a different theme" width="560"><br>
<sub><b>Speaks your language.</b> one review, four themes, four of fourteen locales. the interface localizes; the code and your teammates' words stay exactly as written · Aether · Kirby · Petrichor · Nightwalker</sub>
</p>

## Mine, and yours

Enjoy a variety of unique themes from dark and mysterious Loverboy to a Claude inspired "Halo". Show off that you earned your fairy wings with Bibble or forget the world like a Nightwalker.

Cellshaded comic book page, cosmic glass in three unique perspectives... you get the point.

## Reach for it when you're...

- **onboarding into an unfamiliar codebase.** X-Ray builds a map from the history: which files cluster, which are hotspots, which one file everything secretly leans on.
- **tired of merge conflicts ambushing you.** Orbits is merge conflict prediction: it calls which branches will collide before you press merge.
- **after AI code review that actually knows your repo.** Reviews are grounded in the coupling graph, not grep, with an optional read-only agentic mode.
- **on self-hosted GitLab or Gitea.** Two-way PR and issue sync, same as GitHub. No remote at all? They still work, stored right in the repo.
- **living in a large, fast-moving repo.** Line-level staging, parallel worktrees, full undo on destructive operations, and a commit graph you can zoom until 500 commits read like weather.

## Questions you might have

**Is it free?** Yes, completely. No charge, no account required, and the code is public.

**Is it open source?** Community source available, open development. The GPL portions are open source in the strict sense; the research core carries community-source terms instead, so if you're anal about definitions, the repo as a whole technically isn't. [LICENSE.md](LICENSE.md) draws the exact line.

**Does it work offline, without a remote?** Yes. PRs and issues live inside the repo as orphan refs, so it is fully local-first. Push whenever you feel like it.

**What does it add to my repo?** Nothing you can see. The local-first PRs and issues live as orphan refs inside `.git`, so they never touch your worktree, your branches, or your history. Other clients can't even tell they're there, and deleting the refs removes every trace. Your repo stays a plain git repo the whole time.

**Do I need AI set up to use it?** No. The AI features piggyback on tools you already have, like Cursor, Copilot, Codex, or opencode. Got none? Then there's nothing to set up and everything else just works. Install one someday and Manifold picks it up on its own. And if you'd rather not install anything at all, drop in an API key and dip your feet in at your own pace, or never.

**Which AI models can it use?** Yours. Cursor, Copilot, Codex, OpenRouter, or anything through opencode. The agentic review mode is read-only: it looks everywhere and changes nothing.

**Does my code leave my machine?** Only when you press an AI button, and only to the provider you picked in settings. The exhaustive list of features that send anything: Generate Message, Code Review, Muse, and Debug (which might get yeeted). That's it. The engine, the maps, the predictions, all local math. No telemetry, no account, no background anything. Local model support will keep getting better, and long term I keep moving intelligence out of the AI layer and into raw math, so the list shrinks over time.

**Is it in my language?** Probably. Manifold ships in English, German, Spanish, French, Indonesian, Italian, Japanese, Korean, Dutch, Polish, Brazilian Portuguese, Russian, Turkish, and Simplified Chinese, with right-to-left languages in the works. Machine translation gets every locale complete on day one, human corrections win permanently once they land, and the language picker states plainly how your locale was made. If a string reads awkward in yours, [TRANSLATIONS.md](TRANSLATIONS.md) shows how to fix it.

**Will it handle my giant monorepo?** It should. I make no performance claims while it's in beta, only because I'm still chasing snappy, but absurd monorepos are what the analysis budget was built for: it degrades gracefully instead of dying. If yours makes Manifold struggle, complain once and I'll do everything in my power to fix it. The one caveat is single multi-gigabyte files. Those work since the diff viewer's memory rework, but not yet to my standard, and they're due proper investment soon.

**How is it different from GitKraken or GitHub Desktop?** They show you your repo. Manifold has done the math on it: it predicts merge conflicts, grounds AI review in your real coupling structure, and can map a codebase you have never seen.

**What about macOS?** I don't own a Mac. If you do, this is the one place I officially endorse vibe coding: point your model at the repo, say "get it working on macOS, make no mistakes", and let it cook. Worst case, nothing happens. Best case, you're the reason there's a macOS build. I'd love to see it.

## Status

Public Beta mk2. Windows is my primary machine but the target builds i'd like stability on are Windows and Linux. Portable exe and AppImage.

## Quick start

```bash
cd apps/desktop-flutter
flutter pub get
flutter run -d windows
```

Needs Flutter 3.35+, Dart 3.9+, and Git on your PATH.

## On the code, openly

The code is all here, in the open. yippee!!! Use it as your daily driver if it clicks for you.
Read it, audit it, fork it, lift pieces for your own projects under the terms
they carry. If it ends up being the Git client someone actually reaches for,
that's great.

Issues are welcome. Bug reports, questions, "this broke", "this is
confusing", "X seems wrong" - all of that is useful, and I'll get to it
when I can.

Clone it, or ask an LLM to explain and understand the core. I support self learning. But...

Pull requests touching the engine *aren't* preferred, and this isn't a community thing. The math underneath Manifold is specific, layered, and easy to break in ways that don't look broken. 
The engine mixes:

- hypercomplex algebra
- spectral graph theory: Laplacian, heat kernel, & Ricci flow - because signal travels through a repo the way heat diffuses through a structure
- chemistry-flavoured structural analogies. coupling, diffusion, phase
  transitions on the repo graph
- **kizuna math**, a term I coined for a particular flavor of
  higher-dimensional hypercomplex algebra I use
  [across my projects](https://woflo.dev/blog/kizuna-codecs/).
  Manifold leans on parts of it, alongside everything else above.

PRs that touch the engine may violate invariants that look fine in
code review but quietly wreck properties the rest of the system depends
on. Unwinding that eats the time I'd rather spend *not*. So read it,
fork it, yoink from it, file issues, fix issues I haven't experienced yet. App-side
fixes and improvements are welcome, and so are translation fixes when a string
reads clumsy in your language; see [CONTRIBUTING.md](CONTRIBUTING.md). Just not vibe-understood PRs or I'll vibe-respond.


## Known Things

- Runs hot 👉👈 (hot math ayo)
- Multi-gb single files work, but not to the standard I want yet. Proper investment is on the list.
- The bundled semantic engram is a general-purpose research artifact, not something trained on code. It works, but a code-native one is the plan.

## License

Manifold is mixed. Most of it is GPL-3.0-or-later with the Manifold-Woflo
exception, and the reusable Woflo research components listed in the root license
keep their Woflo Labs community-source terms. [LICENSE.md](LICENSE.md) draws the
exact path boundary between them. If you'd like to contribute, [CONTRIBUTING.md](CONTRIBUTING.md)
covers how that works.

## Acknowledgments

Flutter. Dart. The math nerds. The GloVe authors. Everyone whose work I
stood on.
