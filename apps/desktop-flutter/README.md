# Git Desktop - Your Personal Git Client

A Flutter desktop Git client for people who want more than file lists and commit hashes.

Git Desktop combines ordinary Git workflows with local repository analysis: related-file ranking for reviews, semantic context packing, commit-message assistance through optional model providers, repository analytics, and deliberately visual history tooling.

This README documents the Flutter desktop app. It is written in two layers:

- The top half explains what the app feels like to use.
- The bottom half explains how the heavier systems actually work, without flattening the math into marketing.

## What is Git Desktop?

Git Desktop is a desktop Git client that analyzes repository history, file relationships, and current diffs to surface context around your changes.

In plain English:

- You stage and commit like you would in any Git GUI.
- The app can suggest related files that matter to the change you are reviewing.
- It can draft commit messages and reviews through optional external model providers.
- It gives you visual summaries of history, hotspots, coupling, and change patterns that are hard to see in a plain status view.

It is not trying to "understand your code" in a magical sense. Its local systems score, rank, index, and retrieve context from repository structure and history.

## A quick example

You change authentication middleware.

- The Changes view shows the modified files and their diffs.
- Logos ranks nearby files that often move with the auth path, plus semantically related files when historical coupling is weak.
- Engram supplies embedding-derived context so cold or newly added files are not invisible.
- X-Ray can tell you whether this area is historically hot, structurally central, or part of a bursty patch of repo activity.
- If you want, the commit assistant can draft a message using the diff and packed context.

That is the core promise: keep the Git workflow familiar, but make the surrounding context easier to see.

## Who is it for?

- Developers working in medium or large repositories where change context matters.
- Teams that want optional LLM-assisted commit messages or review help without turning the whole app into a chat client.
- People who think visually and want more than a plain history table.
- People who are comfortable with Git and want better observability into repository structure.

## Core concepts

| Term | Meaning in the app |
| --- | --- |
| `Logos` | The graph-based related-files engine. It diffuses relevance from the current change over a weighted file graph. |
| `Engram` | The semantic indexing layer. It turns identifier content into compact complex-valued feature vectors for similarity lookup. |
| `Desk` | A Git worktree, branded as a desk in the UI. |
| `Desk PR` | A local PR-like record stored in Git refs, so review metadata can exist before or alongside a hosted PR. |
| `X-Ray` | Repository analytics: hotspots, cadence, keystone files, strata, pivots, and metabolism-style activity summaries. |
| `Commit Seismograph` | A seismograph-inspired history view built from churn bars and ridgelines, not a literal geophysical model. |

## What you get in the first 10 minutes

1. Open an existing repository or clone one.
2. See staged and unstaged files in Changes.
3. Read the diff and ask Logos for related-file context.
4. Stage a focused subset of files.
5. Draft a commit message manually or through an optional AI provider.
6. Browse history with the seismograph and open commit details.
7. Switch branches or open a desk (worktree) for parallel work.

## Quick start

### Prerequisites

- Flutter SDK 3.22.0 or later
- Dart SDK 3.3.0 or later
- Git installed on your system

Optional but useful:

- `gh` for GitHub PR and issue integration
- One or more configured AI providers if you want commit drafting or AI review

### Run the app

```bash
cd apps/desktop-flutter
flutter pub get
flutter run -d windows
```

### Build from source

```bash
cd apps/desktop-flutter
flutter pub get
flutter build windows
```

You can also run the built executable from:

`build/windows/x64/runner/Debug/git_desktop.exe`

## First launch

A 3-step onboarding flow walks through the initial setup:

1. Name
   - Give the client an identity.
2. Theme + controls
   - Pick one of 13 themes.
   - Choose a keybinding profile: `Porcelain` (chorded) or `Numeric`.
3. Repository
   - Open an existing repo, clone one, create a fresh one, or skip.

Each step has a path that lets you continue quickly.

### First-run behavior on larger repos

The app remains usable while background indexing warms up, but some semantic features become more useful after the first pass finishes.

That means:

- Normal Git operations do not depend on model configuration.
- Logos and Engram benefit from cached statistics and semantic assets.
- Large repositories may take longer on first open while caches are built.

## Basic workflow

- `Changes` -> review file status, stage selectively, compose a commit, optionally use AI assist
- `History` -> browse commits, inspect details, search, open reflog and rebase tooling
- `Branches` -> create or switch branches, manage desks, inspect local PR-like records
- `Sync` -> fetch, pull, push, and inspect remote state
- `X-Ray` -> inspect hotspots, cadence, keystones, and repo-level signals
- `Settings` -> models, diagnostics, themes, and keybindings

## Privacy and trust model

Git Desktop has two very different kinds of intelligence, and the README keeps them separate on purpose.

### Local and deterministic

These run locally and do not require a hosted model:

- Git subprocess operations
- Logos diffusion and coupling analysis
- Engram semantic indexing and nearest-neighbor lookup
- X-Ray analytics
- Diagnostics and JSONL audit logs
- Desk PR and issue metadata stored in Git refs

### External and optional

These only run when you explicitly invoke them and have configured a provider:

- Commit message drafting
- AI review
- Muse brainstorming

Current built-in provider adapters in the Flutter app target:

- `codex`
- `claude`
- `gemini`
- `opencode`

That wording is deliberate: the implementation is provider-adapter based, not a generic "supports every model vendor" claim.

## Key features

### Day-to-day Git

- Repository open, init, clone, recent-list management
- Status, staging, unstaging, file patching, discard paths
- Commit creation, cherry-pick, revert
- Branch list/create/checkout/delete/rename/merge
- Tags, stash, reflog, worktrees, fetch/pull/push
- Interactive rebase UI backed by `git rebase -i`

### Context systems

- Logos related-file ranking for diffs and reviews
- Hunk-level and chunk-level diffusion helpers
- Engram semantic similarity over identifier content
- File-coupling and symbol-frequency analysis

### Visual tooling

- Commit Seismograph per-commit drillable churn map
- Hypercube logo and animated theme system
- Logos diffusion canvas in the Changes experience
- X-Ray analytics views for hotspots, strata, cadence, and pivots

### Optional integrations

- AI-backed commit drafting, review, and Muse workflows
- GitHub integration through `gh`
- Remote issue provider detection from `git remote get-url origin`

## Keyboard shortcuts

Two profiles ship today:

- `Porcelain`: chorded shortcuts such as `G` then `C`, `H`, `B`
- `Numeric`: compact single-key oriented navigation

Common shortcuts:

| Shortcut | Action |
| --- | --- |
| `G` then `C` | Go to Changes |
| `G` then `H` | Go to History |
| `G` then `B` | Go to Branches |
| `/` | Search commits |
| `?` | Show shortcuts |

## Pages

| Page | Purpose |
| --- | --- |
| `Changes` | Staged and unstaged files, commit composer, file constellation, AI actions |
| `History` | Commit browsing, per-commit churn topography, tags, reflog, detail inspection |
| `Branches` | Branch management, desks, local PR-like records, remote workflows |
| `Diff` | Full diff viewer with move detection and staging helpers |
| `Search` | Commit search by message, author, and hash |
| `Sync` | Fetch, pull, push, remote status, conflict cues |
| `X-Ray` | Repository analytics and structural summaries |
| `Settings` | Themes, keybindings, diagnostics, provider setup |
| `Onboarding` | First-run naming, theme, keybinding, and repo setup |

## Architecture at a glance

```text
lib/
|- app/           # Application state, providers, workspace shell, identity
|- backend/       # Git operations, Logos, Engram, analytics, persistence
|- features/      # Screens and feature-specific UI
|- components/    # Reusable visual components
|- ui/            # Theme system, tokens, shaders, material surfaces
`- diagnostics/   # Telemetry state and retention logic
```

The important architectural boundary is this:

- `backend/` computes Git data, graph signals, caches, and persistence.
- `features/` and `components/` make those systems legible in a desktop UI.

## Technology stack

| Area | Technology |
| --- | --- |
| Framework | Flutter 3.22+ |
| State management | `provider` + `ChangeNotifier` |
| Desktop windowing | `window_manager` |
| Git execution | Direct `Process.run` / `Process.start` calls to system Git |
| Preferences | `shared_preferences` |
| SVG and files | `flutter_svg`, `file_picker` |
| Markdown | `flutter_markdown` |
| Semantic assets | Quantized GloVe-300 + Alexandria ENDB bundle |
| Persistence | JSON files, JSONL logs, Git refs, EFIX cache blobs |

## State management

The app currently wires 16 `ChangeNotifier` state classes:

- `RepositoryState`
- `ThemeState`
- `WorktreeState`
- `LogosGitState`
- `DeskPrState`
- `DeskIssueState`
- `AiSettingsState`
- `DiagnosticsState`
- `RepositoryXrayState`
- `FileCouplingState`
- `SymbolFrequencyState`
- `RemoteIssueCacheState`
- `PreferencesState`
- `AppIdentityState`
- `OnboardingState`
- `HyperReactivity`

That list is useful because it shows the app is not "one giant state bag". The major systems are separated and named.

## Git backend

Git operations are executed directly through the system Git binary.

High-level coverage includes:

- Repository: open, init, clone, recent list
- History: log, commit details, ahead/behind, reflog, search
- Diff: file diff, commit diff, blame, move detection support
- Staging: stage, unstage, patch application, file-level staging, discard
- Branches: list, create, checkout, delete, rename, merge
- Tags: list, create, delete
- Commits: create, cherry-pick, revert
- Remote: fetch, pull, push, sync, remote detection
- Stash: list, push, pop, apply, drop, show, touched files
- Worktrees: list, add, remove, prune
- Rebase: interactive todo generation via `git rebase -i`

The README says "direct subprocess execution" because that is what the code does. It is not wrapping libgit2.

## Technical deep dive

## Logos: repository-context diffusion

### What it does

Logos is the related-files engine.

Given a diff, it ranks other files by diffusing a source signal over a weighted file graph. That gives the review flow a way to surface files that are historically coupled, structurally nearby, or semantically similar even when the current diff is narrow.

### What graph it uses

At file level, the resolver builds a sparse candidate graph from recent repository history.

It does not score every possible file pair. Instead, it harvests repo statistics, proposes candidate neighbors from co-change rows, same-directory siblings, and optionally same semantic-well siblings, then keeps the highest-scoring neighbors per node before symmetrizing into the final graph.

The always-on file-level axes are:

| Axis | Meaning |
| --- | --- |
| `F0` | Global frequency: how often the destination file appears in commits |
| `CC` | Co-change affinity from the file-coupling matrix |
| `SP` | Path proximity from shared directory-prefix structure |
| `V` | Volatility compatibility: files with similar churn noise profiles |

When Engram file vectors are available, an optional fifth axis is added:

| Axis | Meaning |
| --- | --- |
| `EN` | Optional Engram cosine similarity over per-file K-vectors |

A few important details:

- `EN` is optional and only participates when per-file Engram vectors are available, so the default resolver-built graph is 4-axis and the semantic-enhanced version is 5-axis.
- Symbol overlap is also used elsewhere in the system as a leading signal, especially for cold-start and current-change routing, but it is not a default sixth axis in the resolver-built file graph.
- The codebase refers to some temporal regularization logic as `Whisper`; in README terms, that is an internal codename for AR(2)-derived temporal shaping, not a standard named method.

### The diffusion math

The file-level diffusion is grounded in the heat operator on the symmetric normalized graph Laplacian:

```text
phi(t) = exp(-t * L_sym) * rho
```

Where:

- `L_sym` is the symmetric normalized graph Laplacian
- `rho` is the source mass built from the current diff
- `t` is a diffusion scale parameter

A few semantic corrections matter here:

- `t` is better read as diffusion time or scale, not as a discrete hop counter.
- Larger `t` widens the neighborhood the score can spread into.
- Smaller `t` keeps the ranking closer to the changed files.

The implementation uses a Chebyshev approximation of the heat kernel:

```text
exp(-t * L) ~= sum_{k=0..K} c_k(t) * T_k(L)
```

internally evaluated on the shifted operator `L_sym - I` so the recurrence lives on the `[-1, 1]` spectral interval. In the shared core:

- Default `K = 20` for file-level diffusion
- Small-graph hunk/chunk engines use `K = 24`
- Adaptive truncation prunes negligible tail terms based on coefficient size
- Runtime truncation uses a concrete threshold of `1e-8 * max|c_k|`

That is important because the README should describe the method as an approximation with numerical safeguards, not as an abstract closed-form solved exactly at runtime.

### How the axis blend works

The file-level edge mix is not a generic average. The code uses a Born-rule-inspired amplitude blend with confidence-gated evidence weights.

The README should be careful here:

- It is reasonable to describe this as a project-specific mixing rule.
- It is not helpful to imply that the engine is implementing some recognized quantum-software formalism.

So the right framing is:

- "Born-inspired" or "Born-rule-style" if you want the flavor
- followed immediately by the concrete point: it is the project-specific rule used to combine bounded affinity signals into one graph weight

After the main axis blend, the edge score is further modulated by a cadence term derived from each file's AR(2) inter-touch-gap fit. In the build path this appears as a geometric attenuation by `sqrt(r_a * r_b)`, where each `r` is the file's clamped spectral radius.

That cadence term is not a separate axis. It is a post-mix edge-weight attenuator.

### Probe, coherence, and stability

Logos does more than a single diffusion pass:

- Probe logic inspects the diff and suggests a diffusion scale.
- Coherence gating can trim the returned set so the induced subgraph stays structurally coherent.
- Stability runs repeated perturbed diffusions and reports how robust the top-K remains under small weight jitter.

That is why the system feels more like a ranking engine than a raw graph walk.

The temperature guidance should also be framed carefully:

- `t = 1.0` is the default file-level setting.
- The probe adapts `t` inside a bounded range based on diff size and coherence.
- Values such as `0.5`, `1.0`, and `2.0` are useful intuition for narrower or wider diffusion, but they are not literal guarantees about hop-count radius.

### Hunk and chunk variants

The codebase also contains:

- `logos_hunks.dart`
- `logos_chunks.dart`

These run heat-kernel diffusion on smaller graphs inside the diff itself. They use a three-temperature blend at `t in {0.5, 1.0, 2.0}` and recombine the results with a geometric mean. That is more specific, and more accurate, than describing the entire system as if one global `t` were always mapped to named hop counts.

## Engram: semantic indexing without a hosted model

### What it does

Engram is the semantic retrieval layer.

It turns identifier-heavy code content into compact complex-valued vectors, then uses those vectors to compare files and hunks by content shape rather than by Git history alone.

### What it is built from

The pipeline is grounded in bundled assets and deterministic transforms:

- `glove300.bin`: a custom `GLV1` bundle with an 18,819-token GloVe-300 vocabulary stored as globally scaled `int16` vectors
- `alexandria.endb`: a bundled brain snapshot with a `300 -> 150` reference pairing and 225 learned wells
- Identifier splitting for camelCase, PascalCase, snake_case, and kebab-case
- Pairing of 300 real dimensions into 150 complex pairs
- Per-pair AR(2) fitting over token trajectories
- Nearest-neighbor lookup against the Alexandria well geometry

### Important terminology correction

The codebase uses internal names such as:

- `Alexandria`
- `brain`
- `semantic wells`
- `K-space`

Those are real project terms, but they are internal vocabulary, not standard field terminology. The README keeps them, but defines them:

- `Alexandria` = the shipped semantic reference bundle
- `semantic wells` = prototype centroids in the learned complex-valued feature space
- `K-space` = the app's compact complex latent space, not MRI k-space or a general physics term

### Pipeline summary

```text
identifier tokens
-> sub-token expansion
-> GloVe lookup
-> pooled / paired complex trajectory
-> AR(2) fit per pair
-> K-vector
-> nearest-well / nearest-row retrieval
```

A few verified details:

- The tokenizer is ASCII-oriented and explicitly handles case, acronym, and punctuation transitions.
- The bundled GloVe file is int16-quantized with one global dequantization scale.
- The Alexandria bundle exposes 225 reference wells.
- File-level semantic results are cached in an `EFIX` binary cache keyed by file path, mtime, and size.
- File indexing is intentionally shallow: it scans a bounded prefix of each file and caps the number of identifier runs so semantic indexing stays cheap.

### What the AR(2) language means here

The README should not casually say "time-series analysis" and leave it at that.

In Engram, the AR(2) fit is used over the token-derived complex trajectory used by the encoder. That is an internal representation choice in the semantic codec, not a hosted embedding service and not a generic claim that the app has solved code semantics in the abstract.

That distinction matters because the codebase also uses AR(2)-flavored ideas elsewhere for repository-health and decay-like metrics. Engram's semantic AR(2) is not operating over commit chronology. It is operating over token-embedding trajectories inside the file/hunk encoder.

## File coupling and symbol frequency

### Historical coupling

The coupling matrix is a CSR sparse matrix over files.

Its historical component is a time-decayed Jaccard-style coefficient:

```text
co / (Na + Nb - co)
```

where the counts are weighted by recency rather than treated as naive raw totals.

### Current identifier overlap

A separate symbol-overlap signal handles the "history is silent but the code is obviously related" case.

That overlap is IDF-weighted Jaccard over identifier sets:

```text
idf(id) = ln(1 + N / (1 + df(id)))
```

with a local fallback when the corpus-wide index is not yet warm.

This distinction matters:

- Historical coupling is lagging but grounded in repo history.
- Symbol overlap is leading and can help with new files or cold-start situations.

## Commit fingerprinting

Commit fingerprinting is one of the places where the original README needed a hard terminology correction.

The implementation is not "25D, not Walsh-Hadamard". It is explicitly Walsh-Hadamard based.

The code describes it as:

- A 25-dimensional Walsh-Hadamard structural fingerprint
- A 256-bit bipolar witness for fast Hamming-distance prefiltering

That gives the app a cheap structural similarity primitive before deeper comparison.

## PR shape

PR Shape is an advanced summary of a change set built from Logos-native signals.

It stores:

- a dense non-negative `phi` vector for the PR
- coherence over the touched files
- stability of the top-K under perturbation
- field alignment as cosine against a rolling repo activity field

Because the stored vectors are non-negative, the README can responsibly say that cosine similarity lives in `[0, 1]` for that representation. The useful interpretation is simple: the similarity measures overlap strength and structural resemblance, not "positive versus negative direction".

## X-Ray: repository analytics

X-Ray is the analytics surface for repository behavior.

It builds snapshot data including:

- hotspots
- strata
- pivot commits
- cadence signals
- keystone files
- signal-integrity summaries
- repository metabolism

A few terms are worth defining precisely:

- `hotspot` = frequently or heavily touched region worthy of attention
- `keystone file` = a file with high structural pull relative to its touch count, not merely a file with a lot of churn
- `metabolism` = repo activity trajectory derived from daily commit-rate series and related decay parameters

The code computes keystone scores explicitly rather than using the word as a vague metaphor.

## Visual systems

## Hypercube logo

The logo is a tesseract-inspired wireframe projected into 2D.

Verified implementation details:

- The engine starts from the actual 16-vertex hypercube graph and composes planar 4D rotations across `XY`, `XZ`, `XW`, `YZ`, `YW`, and `ZW`
- Animation moves across 13 preset six-angle pose vectors rather than a single looping keyframe strip
- Projection is two-stage perspective: a W-shaped 4D-to-3D factor and a Z-shaped 3D-to-2D factor multiplied together
- Motion uses spring-return interaction parameters with `_spring = 800` and damping around `21.4` per second
- Reduced motion freezes passive pose motion, still allows intentional drag, and uses a short singularity-style return instead of continuous passive springing

The README describes those as animation parameters, not as physical constants with real-world units. The physical part is the drag-warp return, not the whole pose cycle.

## Commit Seismograph

The history view is seismograph-inspired rather than literally a seismograph.

What it actually renders:

- a per-selected-commit churn map rather than a history-wide line chart
- vertical tracks for immediate directories and synthetic fold buckets
- horizontal file segments sized by churn share
- stacked additions/deletions within each segment, plus type notches for rename/copy/type-change/conflict cases
- a smoothed ridgeline polyline drawn with `CustomPainter`
- drillable breadcrumbs and a persistent hover inspector
- animated reveal behavior when the viewed slice changes

That keeps the metaphor vivid without pretending the widget is anything other than a carefully structured history chart.

## Logos Diffusion Canvas

The Changes experience includes a diffusion canvas that visualizes score propagation.

The code uses:

- a deterministic starfield backdrop that scales with reported graph size
- source ignition spokes whose lengths reflect weights and whose angles come from stable path hashes
- semantic-well sectors and polar placement for settled neighbors
- a spring-driven tip motion with damping matching the hypercube feel
- a 14-segment Verlet rope chain between the source and tip
- radial `phi`-quantile rings
- animated hunk `phi` bars and a budget meter in the footer

Again, the README frames this correctly as a presentation-layer explanation of the math, not a force-directed graph layout or a physical simulation of repository behavior.

## Theme system

The app ships 13 named themes:

- Halo
- Nightwalker
- Petrichor
- Helix
- Nacre
- Loverboy
- Aether
- Quanta
- Phosphor
- Redshift
- Kirby
- Blackboard
- Crafty

Theme motion profiles come in three timings:

- `snappy` = 80 ms
- `fluid` = 180 ms
- `elastic` = 250 ms

The visual stack includes fragment shaders for:

- `cellshade`
- `iridescent`
- `dark_iridescent`
- `loverboy_bg`
- `glass`

The README keeps the visual flavor, but avoids treating shader copywriting as if it were a systems specification.

## Pull requests, issues, and desks

### Desks

A `Desk` is a Git worktree in the UI.

The backend reads and writes actual worktrees through `git worktree` commands. That means the branding layer maps onto a standard Git concept rather than inventing a parallel storage mechanism.

### Desk PRs

Desk PRs are local PR-like records stored in Git refs:

- ref namespace: `refs/manifold/desks/<branch>`
- payload file: `meta.json`
- shared ID counter: `refs/manifold/_id-counter`

The code stores them as orphan commit histories so the audit trail remains inspectable through Git itself.

### Issues and remote providers

Issue metadata can also live locally in refs:

- `refs/manifold/issues/<id>`

Remote provider detection is based on `git remote get-url origin`.

Today:

- GitHub issue integration is implemented through `gh`
- GitLab detection exists, but `glab` support is still stubbed in the provider layer
- Local/unrecognized remotes fall back to a null provider

## Diagnostics

The app keeps four main telemetry streams:

- command latency
- diff render metrics
- UI timing metrics
- command lifecycle events

Persistence is local JSONL with configurable retention.

Verified defaults:

- retention days: `30`
- retention size budget: `128 MB`

The diagnostics layer explicitly computes values such as:

- `p50`
- `p95`
- frame timing summaries
- janky frame counts and rates

and trims with a policy designed to preserve:

- failures
- heavy outliers
- recent context

AI review audit logs are stored separately in `ai_review_audit.jsonl` with their own retention policy.

## Storage and persistence

| Type | Mechanism | Location |
| --- | --- | --- |
| App settings | JSON | `{appData}/gdpu/settings.json` |
| AI settings | JSON | `{appData}/gdpu/ai/ai_settings.json` |
| Desk PR metadata | Git refs | `refs/manifold/desks/*` |
| Desk issue metadata | Git refs | `refs/manifold/issues/*` |
| Engram file cache | EFIX binary | `{appData}/gdpu/engram_cache/*.efix` |
| Logos calibration | JSON | `{repo}/.git/logos-git/sse.json` |
| Command telemetry | JSONL | `{appData}/gdpu/command_telemetry.jsonl` |
| AI audit | JSONL | `{appData}/gdpu/ai_review_audit.jsonl` |
| Recent repos | SharedPreferences | Flutter preferences |

Cross-platform data-root resolution:

- Windows: `%APPDATA%\\gdpu`
- macOS: `~/Library/Application Support/gdpu`
- Linux: `$XDG_DATA_HOME/gdpu` or `~/.local/share/gdpu`
- Override: `GDPU_DATA_DIR`

## Testing

The test suite covers both backend and UI-heavy areas, including:

- file coupling
- Engram fitting
- Logos systems
- PR storage
- X-Ray
- hypercube projection
- integration tests
- widget rendering and theme tokens

## Window configuration

Verified default desktop window settings:

- default size: `980 x 660`
- minimum size: `620 x 500`
- centered on launch
- background color: `#0A0D12`
- normal title bar with platform window controls

## Troubleshooting

### "No model configured"

Open `Settings -> Models` and choose a provider/model slot.

### Large repo feels slow on first open

That is usually the background analysis and cache warm-up path. Git features remain usable while indexes settle.

### GitHub features are missing

Check that `gh` is installed and authenticated.

### GitLab issue sync is unavailable

The provider layer recognizes GitLab remotes, but `glab` support is still stubbed in this Flutter codebase.

### Semantic features seem weak on tiny or brand-new repos

That is expected. Historical coupling needs enough commit history to become trustworthy, and some signals fall back to neutral priors when evidence is thin.

## Glossary

- `Logos`: graph-based repository-context diffusion engine
- `Engram`: semantic indexing layer built from identifier tokens and bundled vector assets
- `Desk`: Git worktree in the UI
- `Desk PR`: local PR-like metadata stored in Git refs
- `X-Ray`: repository analytics snapshot and UI
- `Coherence`: how tightly a file set or diffusion result hangs together structurally
- `Stability`: how robust a ranking remains under small perturbations
- `K-vector`: Engram's compact complex-valued feature vector for a file or hunk

## Rebranding

Runtime app identity lives in:

`lib/app/app_identity.dart`

Update the short name, full name, description, and tag there if you want to rebrand the product.

## License

See the project root for license information.

## Acknowledgments

- Flutter and the desktop plugin ecosystem
- the original GloVe researchers
- the open-source packages listed in `pubspec.yaml`
