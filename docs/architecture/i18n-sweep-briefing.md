# i18n Sweep Briefing

Instructions for every agent externalizing UI strings into slang keys. Read completely
before touching anything. The companion strategy doc is `docs/architecture/i18n-readiness.md`
(in the main worktree; not required reading — this briefing is self-contained).

## Ground rules

1. **1:1 fidelity.** The rendered English UI must be byte-identical after your change.
   You are moving strings, not editing them. No rewording, no punctuation fixes, no
   "improvements". If a string has a typo, it keeps the typo (note it in your report).
2. **You own exactly your assigned files plus your namespace JSON.** Never edit another
   namespace's JSON, never edit `common.i18n.json`, never edit files outside your
   assignment. If you need a shared term ("Cancel", "{n} files"), check
   `lib/i18n/en/common.i18n.json` — if it's there, use `t.common.*`; if not, put your own
   copy in YOUR namespace. Deduplication happens later; collisions now are worse.
3. **No git commands. No commits.** You are in a worktree managed by the orchestrator.

## Mechanics

- Translation files: `lib/i18n/en/<namespace>.i18n.json` (create yours; nested JSON,
  camelCase keys). Codegen: `dart run slang` from `apps/desktop-flutter/`. Generated
  accessor: `import '<relative path>/i18n/gen/strings.g.dart';`.
- **In widget build methods (anything with a BuildContext): use `context.t`** — e.g.
  `Text(context.t.branches.leaseExpired)`. This rebuilds on locale change. The extension
  comes with the strings.g.dart import.
- **In non-widget code** (helpers, non-widget classes, callbacks without context): use the
  global `t` from the same import. Only when no BuildContext is reachable.
- Interpolation is **braces**: `"deleted": "Deleted {name}"` → `context.t.ns.deleted(name: x)`.
  Param names camelCase and descriptive (`{count}`, `{branch}`, not `{a}`).
- Plurals (whenever English inflects on a count):
  ```json
  "conflictCount": {"one": "{n} conflict", "other": "{n} conflicts"}
  ```
  → `context.t.ns.conflictCount(n: count)`. Use for EVERY `${n == 1 ? '' : 's'}` idiom —
  never carry the ternary idiom through. Two plurals in one sentence: split into two keys
  composed at the call site only if the current code already composes; otherwise use two
  parameters and one plural key on the dominant count with the other count pre-formatted
  via its own plural key.
- Sentences assembled from fragments must become ONE key with placeholders, not fragment
  keys glued together (word order differs across languages). If today's code concatenates,
  restructure into a whole-sentence template whose English render is identical.
- Nested sections within your namespace are encouraged: group by panel/dialog
  (`"leaseCard": { "title": ... }`).
- Key naming: what the string IS, not where it sits (`deleteBranchConfirm`, not
  `dialogText3`). Buttons/labels short names; messages `<thing><Event>` style.

## What to externalize

Everything a user can see, in your files: `Text(...)` literals, interpolated Text strings,
`tooltip:`/`Tooltip(message:)`, `hintText:`/`labelText:`/`helperText:`, SnackBar content,
dialog titles/bodies/actions, `label:` on chips/buttons/menu/palette entries, empty-state
copy, `Semantics(label:)`/hand-built narration strings (a11y IS user-facing), confirm
prompts, progress/status strings.

## What must stay English (DO NOT touch)

- `debugPrint`/log/diagnostic strings, exception messages, `assert` messages.
- `GitResult.err('...')` / `.failure(...)` backend error strings — deliberate decision
  this round (greppable bug reports; also surfaced over the CLI/IPC bridge).
- LLM prompt text (`'You are …'`, wakeFrames, prompt builders) — model-facing, never UI.
- Brand/product names: `'Claude'`, `'VS Code'`, `'Cursor'`, `'Zed'`, `'GitHub'`, model
  names, font family names, shader names, theme ids.
- Git plumbing: command args, ref names, config keys, format strings passed to git.
- Storage/preference keys, JSON field names, file paths, URLs, regexes, MIME types.
- Anything in `test/`, `tool/`, generated files.
- Strings used as VALUES (compared, persisted, parsed) rather than displayed. If a string
  is both displayed AND compared somewhere, do NOT externalize it — flag it in your report.
- `lib/backend/repo_summary/` — out of scope for everyone except its dedicated agent.

## const fallout

`const Text('x')` → `Text(context.t.ns.x)` forces const removal. Remove the MINIMUM const
set: the literal's widget and only the ancestors the analyzer then flags. Do not
blanket-strip const from a file. `const` lists/maps holding labels become getters or
finals. Default parameter values that are string literals can't call `t` — make the
parameter nullable and resolve inside the body (`label ?? context.t.ns.defaultLabel`),
preserving the exact default.

## Workflow

1. Read this doc, then map your files: grep your files for `Text\(|tooltip:|hintText:|labelText:|SnackBar|label:|message:|title:|Semantics` with line numbers.
2. Work file by file, hit by hit, reading enough surrounding context (±40 lines) to
   classify each string (UI vs value vs log vs prompt). Big files: work in segments;
   never assume — read.
3. Add keys to your namespace JSON as you go; keep it alphabetized within sections.
4. `dart run slang` then `dart analyze <your file paths>` — zero NEW issues. If analyze
   shows errors in `lib/i18n/gen/` or another namespace, rerun `dart run slang` once
   (another agent may have raced the codegen) and re-analyze.
5. Report: files done, key count, flagged dual-use strings, typos preserved, anything
   skipped and why. Raw data, not prose.

## Namespace assignments

| Namespace | Files |
|---|---|
| `branches` | features/branches/** |
| `changes` | features/changes/** (changes_page, merge_conflict_editor, conflict_resolution, file_constellation, merge_conflict_flow) |
| `settings` | features/settings/** |
| `xray` | features/xray/** |
| `history` | features/history/** (history_page, commit_seismograph(+layout), commit_tagger, commit_lede, worldline_field) |
| `diff` | features/diff/** (diff_shell, diff_document, media_renderer, binary_diff_view) |
| `app` | app/workspace_shell.dart, app/sidebar_rail.dart, app/desk_drop_payload.dart, app/brand_lockup.dart, ui/undo_pill.dart, ui/context_menu.dart, ui/form_controls.dart, ui/hyperhealth_text.dart, ui/resonance_text.dart, ui/theme.dart, ui/mosaic_shard_bar.dart, ui/dream_hint.dart |
| `palette` | features/palette/** (registry labels/subtitles/keywords are UI; `keywords` stay English AND gain localized variants only if trivially separable — otherwise flag) |
| `sync` | features/sync/** |
| `historySurgery` | features/history_surgery/** |
| `orrery` | features/orrery/** |
| `onboarding` | features/onboarding/** |
| `filament` | features/filament/** |
| `releaseNotes` | features/release_notes/** — UI chrome only; changelog entry prose STAYS ENGLISH (versioned historical record) |
| `backend` | UI-facing strings reaching widgets from lib/backend/ (ai.dart status/UI strings, merge_session outcome messages, external_tools non-brand descriptions) — dedicated careful agent only |
