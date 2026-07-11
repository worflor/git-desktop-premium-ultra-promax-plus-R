# i18n Terminology Policy

The rule for translating (or not translating) git and product terms in Manifold's locales.
Every translation PR and every fix pass follows this. It exists because the first
translation round anchored to git's own `.po` files, which **over-translate** relative to
how working developers actually speak (git's official French says *picorer* for
cherry-pick, *valider* for commit — technically "correct," practically wrong). Research
confirmed the developer-community norm across 13 languages; this codifies it.

## 1. Keep English everywhere — the git command DNT set

These are not just labels, they are the CLI commands the user types. Translating them
"breaks the mental connection." Keep the English root in **every** locale; inflect it
naturally where the language does (German adds `-en` → *committen*, *pushen*, *mergen*;
Polish/Russian take native prefixes/endings → *commitować*, *закоммитить*; Italian
*committare*; Turkish *commit'lemek*):

- **Verbs:** commit, push, pull, fetch, merge, rebase, cherry-pick, checkout, stash, revert
- **Nouns:** diff, blame, HEAD, staging

`HEAD` and `diff` stay literally English (no inflection, no transliteration) in all
scripts, including CJK.

## 2. Translate — native forms genuinely won

Developers in most languages use the native term for these, so translate them using each
language's established cognate/native word (keep them consistent within a locale):

- repository (→ dépôt, repositorio, repozytorium, 仓库, 저장소, depo…) — "repo" also fine
- branch (→ rama, ramo, gałąź, ветка, dal, 分支, cabang…)
- tag, working tree, remote, index

## 3. Never translate — product & proper nouns

Treat exactly like "Spotlight" or "Finder." English in every locale:

- **App / engine / tool names:** Manifold, Logos, Filament, Muse, Wick, Codex, and every
  external tool or AI model id (Claude, VS Code, Cursor, GitHub, Gitea, …).
- **Feature names (confirmed product nouns):** Desk, X-Ray, Orrery.
- **Porcelain** (keybinding profile) — a git-culture pun (git's "porcelain" = high-level
  commands). Keep English; translating it to the dishware word ("Porzellan"/"Porselein")
  destroys the reference.

`Desk` in particular must be consistent: the first round translated it haphazardly
(Tisch/стол/bureau/banco/masa) — it is now always the English word "Desk."

## 4. Per-language reality

- **German** is loanword-friendly and its git.po actually matches real usage
  (committen/pushen/mergen) — its verb choices are already correct, leave them.
- **French** is the purist outlier; its git.po is the *anti-model*. Reject
  picorage/valider/Extraire/Poussée/tirer/Annuler — use the English command instead.
- **CJK is its own regime.** Chinese's native 提交 (commit) / 合并 (merge) / 分支 (branch)
  / 仓库 (repo) and Japanese's katakana コミット/プッシュ/マージ are the *correct, standard*
  developer forms — do **not** force English onto them. cherry-pick and rebase are often
  kept English even in Chinese. Korean keeps loanword 커밋/푸시 and leans dev-preferred
  머지/체리픽 over the stiff official 병합/빼오기.

## 5. What this pass must NOT touch

The creative/literary writing was praised by every auditor and is correct: the fox/cookie
`commitPreview` parable, the `editorTitles` (the "for-git me" pun and Monty Python
insult), easter eggs, personality strings. **Preserve them.** This is a terminology,
register, and bug pass — not a re-translation.

## 6. Register

Pick ONE politeness/formality register per language and hold it across the whole app
(e.g. Korean: consistent 합니다체 for sentences + noun-form for chrome — no 해요체 mixing).
Consistency reads as professional; mixing reads as sloppy.
