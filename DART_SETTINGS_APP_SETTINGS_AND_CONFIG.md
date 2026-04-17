# Dart Settings App Settings And Config

This file explains the Flutter settings app in `apps/desktop-flutter` and the related config that it reads and writes.

The short version:
- `settings.json` holds the main app settings.
- `ai_settings.json` holds AI routing and slot preferences.
- prompt text lives in separate markdown files under `ai/prompts/`.
- diagnostics retention lives in the same main settings file, but the actual samples are stored separately.
- a few layout values are shared with the React desktop shell and are not exposed in this Flutter settings page.

The code is defensive:
- missing files are recreated with defaults
- invalid values are normalized on load
- out-of-range numbers are clamped
- malformed JSON falls back to defaults and is rewritten

## Where The Settings Come From

The settings page itself is only the UI. The actual state is split across a few objects:
- `PreferencesState` for app behavior and AI guardrail/update/crash toggles
- `ThemeState` for theme and keybinding profile
- `DiagnosticsState` for telemetry retention
- `AiSettingsState` for model slots, model aliases, and AI prompt text
- `OnboardingState` for the first-run gate
- `AppIdentityState` for the app short name

The settings page in `lib/features/settings/settings_page.dart` is mostly a dashboard over those states. Some values are directly editable there, and some are persisted but not currently surfaced in the Flutter UI.

## Files On Disk

### Main app settings

`settings.json` stores the main shared settings snapshot. It includes:
- guardrail value
- AI read-only default
- logo animation preference
- telemetry retention settings
- update channel
- crash reporting toggle
- theme id
- keybinding profile
- sidebar geometry
- utility drawer geometry
- motion rate
- reduce-motion phase
- stash cabinet expansion
- instant blame hover
- file sort guide
- file sort inversion
- Logos pad coordinates
- app short name
- onboarding completion flag
- bond experiment flags

### AI settings

`ai_settings.json` stores AI routing and slot metadata. The prompt bodies are not stored in that JSON file. They live here instead:
- `ai/prompts/commit-message.md`
- `ai/prompts/review-commit.md`
- `ai/prompts/muse.md`

If one of those prompt files is emptied, the code deletes the file instead of keeping a blank file around.

### Local telemetry

The diagnostics system stores local samples separately, then uses the retention values from `settings.json` to trim them. The main sample files are:
- `command_latency.samples.v1.json`
- `diff_render_metrics.v1.json`
- `ui_timing.samples.v1.json`

## Global Settings

### Guardrails

`guardrailValue` is the underlying numeric AI caution setting.

The settings page shows it as a 4-step slider, but the stored value is a float. The current stages are:
- `0` = `Loose` = stored as `0.125`
- `1` = `Balanced` = stored as `0.375`
- `2` = `Strict` = stored as `0.625`
- `3` = `Paranoid` = stored as `0.875`

The value is normalized to the `0.0..1.0` range on load.

What it changes:
- it feeds AI prompt building
- it changes the review guide hint text
- it changes the muse hint text
- it changes the idea-count hint in the muse stage
- it changes the visible label in the settings page

Default: `0.5`, which resolves to the `Balanced` stage in the current UI.

### Appearance

`themeId` selects the visual theme.

The available themes are:
- `Halo` - airy, bright glass with a soft serif feel
- `Nightwalker` - dark, sharp, mono-heavy, and rainy
- `Petrichor` - restrained, daylight-like, and minimal
- `Helix` - warm grain with an emerald / honey tone
- `Nacre` - mother-of-pearl shimmer and iridescence
- `Loverboy` - dark rose and pink-violet glow
- `Aether` - the default, cold-clear glass theme
- `Quanta` - glass with sparkly quantum energy
- `Phosphor` - CRT / terminal green and scanline energy
- `Redshift` - red-tinted glass with an afterimage feel
- `Kirby` - comic-book ink and hard outlines
- `Blackboard` - chalk dust and classroom chalk
- `Crafty` - pixel-art / 16-color retro styling

What the theme setting actually controls:
- palette
- typography
- corner radius
- texture and shader style
- motion feel
- particle accents
- text transition effects

Default: `aether`.

### Keybindings

`keybindingProfile` chooses one of two shortcut layouts:
- `classic` = labeled `Porcelain` in the UI
- `compact` = labeled `Numeric` in the UI

The actual shortcut map is:
- Porcelain / classic: `G C` changes, `G H` history, `G B` branches, `G S` repo x-ray
- Numeric / compact: `1` changes, `2` history, `3` branches, `4` repo x-ray
- both profiles keep `/` for search, `Esc` for close panel, and `Shift+Click` for range selection

Default: `classic`.

### Sidebar And Drawer Layout

These values are in the shared settings schema, but they are not edited in the Flutter settings page.

`sidebarWidthPx`:
- controls the sidebar width in pixels
- clamped to the app's allowed range
- used by the shell layout and resizer logic
- default: `188`

`sidebarPosition`:
- `left` or `right`
- determines which side the sidebar sits on
- affects how drag-resizing behaves
- default: `left`

`utilityDrawerDefaultExpanded`:
- whether the utility drawer opens by default
- default: `false`

`utilityDrawerHeightPx`:
- the preferred utility drawer height in pixels
- used when the drawer is expanded
- default: `180`

These values are shared with the React desktop shell as well, so the schema has to stay compatible across both implementations.

### Motion

`motionRate` is the current motion system setting.

It replaced the old binary reduce-motion toggle with a continuous scalar:
- `0.0` = no motion
- `1.0` = authored speed
- `2.0` = double speed

The UI uses a scrubber-like control that can be dragged horizontally. Tapping toggles between motion off and the last non-zero value. Arrow keys nudge the value by `0.1`.

Important implementation details:
- the code still persists the legacy `reduceMotion` boolean for downgrade compatibility
- `reduceMotion` is treated as true when `motionRate` is at or near zero
- animation helpers scale durations as `authored / motionRate`
- when motion is off, most ornamental transitions are skipped entirely

Default: `1.0`.

`reduceMotionPhase` is hidden support state for the motion toggle. It stores where the pulse-wave animation was frozen, so the next session resumes from the same point instead of snapping back to the start.

This is not really a user-facing preference. It is bookkeeping.

### Guarded Behavior Toggles

`aiReadOnlyDefault`:
- controls whether AI actions default to read-only behavior
- prevents the AI flows from automatically writing or staging changes
- the settings page currently renders this as a disabled, locked-on checkbox
- even though it is not editable there, the value still matters to the AI flows
- default: `true`

`logoAnimatesWhenUnfocused`:
- controls whether the hypercube logo keeps animating when the window is not focused
- used by the logo component as a performance / motion preference
- default: `true`

`stashCabinetDefaultExpanded`:
- controls whether the stash cabinet opens expanded by default
- used in the changes view
- default: `false`

`instantBlameHover`:
- removes the delay before blame information appears on a diff line
- default: `false`

`fileSortGuide`:
- chooses the sort strategy for changed files
- allowed values: `related`, `alphabetical`, `impact`
- default: `related`

`fileSortInverted`:
- reverses the active sort guide
- for related sorting, this means the opposite coupling order
- for alphabetical sorting, this means `Z -> A`
- for impact sorting, this means light changes first instead of heavy changes first
- default: `false`

### Logos Relevance Pad

`logosPadX` and `logosPadY` are a 2D relevance control.

The pad maps to these axes:
- X axis: `folder` on the left, `history` on the right
- Y axis: `far` at the top, `near` at the bottom

The current quadrants are summarized in the UI as:
- `module map`
- `repo centers`
- `neighbors`
- `what to touch next`

The default is centered:
- `logosPadX = 0.5`
- `logosPadY = 0.5`

This is not decorative only. It is the visual tuning surface for the Logos relevance engine.

### Update And Crash Controls

`updateChannel`:
- persisted values are effectively `stable` or `beta`
- the UI shows `STABLE`, `BETA`, and `DEV` tabs in dev builds
- the current persistence code normalizes anything other than `beta` back to `stable`
- that means `dev` is displayed in the UI, but it is not a real persisted channel in this Flutter branch
- default: `stable`

`crashReportingEnabled`:
- turns crash diagnostics collection on or off
- the settings page labels this as anonymized crash snapshots
- default: `false`

The update buttons in the settings page are currently stubs. They show the intended deployment actions, but they do not actually trigger an updater flow in this Flutter build yet.

### Hidden Identity And Flow Flags

`appShortName`:
- the short app name used by the identity layer
- changes the window title and other identity-driven UI
- edited during onboarding rather than in the settings page
- blank values normalize back to `Manifold`
- the value is trimmed and capped at 24 characters
- default: `Manifold`

`onboardingComplete`:
- gates whether the first-run onboarding flow should appear
- `true` means the user has finished or dismissed onboarding
- `false` means the app should still show onboarding
- default: `false`

`bondExperimentEnabled`:
- experimental feature gate for the bond surface
- hidden in the current UI
- default: `false`

`bondDockOpenedOnce`:
- one-shot discovery flag for the bond dock
- once it has been opened, discovery UI should stay quiet
- hidden in the current UI
- default: `false`

## Diagnostics And Retention

The settings page has a local data retention card with two inputs:
- retention days
- retention megabytes

Those values affect how much local telemetry is kept:
- command latency samples
- diff render metrics
- UI timing samples
- AI audit metadata

The valid ranges are:
- days: `1..365`
- size: `16..4096` MB

What the card actually does:
- it updates the shared retention policy
- it trims local telemetry immediately
- it can clear diagnostics only
- it can clear AI audit metadata only
- it can clear both together

The diagnostics area below that is not itself a setting. It is a live observability surface:
- command latency
- diff rendering
- UI timing
- offender ranking
- trace copy to clipboard

## AI Settings

The AI settings live in `ai_settings.json` plus the prompt markdown files. This part is more dynamic than the rest of the settings app, because it depends on which local AI CLIs are currently detected.

### Model Slots

`modelSelections` stores the chosen model for each detected AI category.

Each entry maps:
- category id -> selected model value

The values are usually provider/model identifiers, but the UI also supports custom entries in the form `providerId:modelId` for known providers.

How it behaves when providers change:
- valid selections are preserved
- invalid selections fall back to the first available model in that category
- missing categories are rehomed to the first available category
- the model list is refreshed from local provider detection

### Editable Category Labels

`modelCategoryLabels` stores user-facing aliases for AI categories.

The built-in defaults are:
- `quality` -> `Quality model`
- `fast` -> `Fast model`

The user can rename categories in the settings page. Empty labels are normalized away, and the defaults remain in place.

### Commit Message Routing

`commitMessageModelCategoryId` chooses which AI category should generate commit messages.

Default: `quality`

The commit message section also has a prompt file:
- `ai/prompts/commit-message.md`

That prompt file is an optional style guide. It is separate from the structure/voice/coverage format controls. If the file is empty, it is deleted.

### Review Routing

`reviewCommitModelCategoryId` chooses which AI category should review commits.

Default: `quality`

`reviewCommitDoubleCheckEnabled` adds a second verification pass before the final review report is shown.

Default: `false`

The review prompt lives here:
- `ai/prompts/review-commit.md`

The review editor also reacts to the guardrail stage. The guardrail level changes the hint text and the review tone, so the macro caution setting still matters here.

### Muse Routing

The muse flow has two category slots:
- `museBrainstormModelCategoryId`
- `museSynthesisModelCategoryId`

Defaults:
- brainstorm -> `fast`
- synthesis -> `quality`

That is deliberate:
- brainstorm should be cheap and divergent
- synthesis should be more grounded and thorough

The muse prompt lives here:
- `ai/prompts/muse.md`

Again, empty content is deleted rather than preserved as a blank file.

### Commit Message Format

The commit message controls are not just freeform text. They are a three-axis format system:

- `commitStructure`
- `commitVoice`
- `commitCoverage`

Allowed values:
- structure: `title_body`, `title_only`, `freeform`
- voice: `verb_led`, `descriptive`, `narrative`
- coverage: `essentials`, `balanced`, `everything`

Defaults:
- structure: `title_body`
- voice: `verb_led`
- coverage: `balanced`

How to read them:
- structure is the skeleton
- voice is the tone
- coverage is how much of the diff the message tries to mention

The settings page preview uses those three values together, and the manual commit composer uses the same defaults.

## Settings Page Sections

This is the visible layout in `lib/features/settings/settings_page.dart`.

### Guardrails

This card exposes the guardrail slider and a short phrase that summarizes the current caution level.

### Appearance

This card exposes the theme picker and a short description of the active theme.

### Local Data Retention

This card exposes the retention day and size inputs, plus the clear-data actions.

### Navigation And Dynamics

This card contains:
- keybinding profile
- motion rate
- file sort guide and inversion
- the read-only AI checkbox
- logo animation when unfocused
- stash cabinet expansion
- instant blame hover
- Logos pad tuning

### CLI Piggybacking

This section does provider detection and model-category management.

It is a real routing layer, not just a cosmetic list:
- providers are detected from local binaries
- categories are detected from the provider capabilities
- each category can be renamed
- each category can be pointed at a specific model option
- the settings page can refresh detection manually

### Commit Messages

This section lets you choose:
- the category slot used for commit messages
- the commit format triple
- an optional style guide prompt

### Review Commit

This section lets you choose:
- the category slot used for review
- an optional review guide prompt
- whether to run a double-check pass

### Muse

This section lets you choose:
- the brainstorm slot
- the synthesis slot
- an optional muse prompt

### Performance Diagnostics

This section is for observing and clearing telemetry, not for changing behavior.

### Release Deployment

This section includes:
- update channel
- crash diagnostics toggle
- onboarding replay button
- update action buttons

The action buttons are presentational stubs in this build.

## Normalization Rules And Caveats

These are the important ones:

- invalid JSON is not fatal; defaults are restored
- strings are trimmed before persistence
- empty prompts are deleted from disk
- motion values are clamped into `0.0..2.0`
- guardrail values are clamped into `0.0..1.0`
- retention values are clamped to their allowed ranges
- unknown theme ids fall back to `aether`
- unknown keybinding profiles fall back to `classic`
- the `updateChannel` UI currently shows `dev`, but the stored value is still normalized back to `stable` unless the value is `beta`
- `aiReadOnlyDefault` is present in settings, but the Flutter settings page locks it on instead of letting the user edit it there

## What Is Shared, What Is Flutter-Only

Shared across the repo:
- theme id
- keybinding profile
- sidebar width
- sidebar position
- utility drawer geometry
- app short name
- onboarding completion

Flutter-focused in this settings page:
- guardrails
- motion rate
- file sort guide
- stash cabinet behavior
- instant blame hover
- Logos pad
- AI prompt and slot routing
- local diagnostics retention
- release deployment posture

React desktop shell only or mostly shared layout:
- sidebar position
- utility drawer expansion and size
- sidebar resizing

Experimental or hidden:
- bond experiment flags

## Practical Reading Guide

If you want the mental model without the implementation detail, this is the shortest useful version:

- `themeId` controls how the app looks
- `keybindingProfile` controls how the shell feels to navigate
- `motionRate` controls how much motion the app is allowed to use
- `guardrailValue` controls how cautious the AI flows should be
- `fileSortGuide` controls how changed files are ordered
- `logosPadX/Y` controls how the relevance engine thinks about "related"
- `modelSelections` decides which local model actually handles each AI slot
- `commitStructure` / `commitVoice` / `commitCoverage` decide the shape of generated commit messages
- `reviewCommitDoubleCheckEnabled` adds an extra verification pass
- `telemetryRetentionDays` and `telemetryRetentionMb` decide how much local observability is kept
- `onboardingComplete` decides whether the app still needs to show first-run onboarding
- `appShortName` decides what the app calls itself in titles and identity-driven UI

If you want, the next useful step would be a generated settings reference table with one row per field and its code path.
