# Translations

Manifold ships multilingual by default. This document is the policy for how those
translations are produced, disclosed, and improved — it is a promise to users, so changes
to this policy should be as deliberate as changes to code.

## The honest-by-default model

1. **AI drafts, humans override.** Machine translation gives every supported language a
   complete UI on day one. Human corrections always win over AI output, permanently: once
   a human has reviewed a string, later AI passes must not overwrite it.
2. **Provenance is data, not prose.** `apps/desktop-flutter/assets/i18n/provenance.json`
   records, per locale: whether it is machine translated (`ai`, with the exact model
   named), human-maintained (`human`), or the authored source (`source`); when it was
   generated; who has reviewed it and how much. The in-app language picker renders these
   facts verbatim — e.g. *"Machine translated by Claude Opus 4.8 — not yet human
   reviewed."* Nobody hand-writes that sentence; it can't drift from the truth.
3. **Git history is the audit trail.** Every string's origin is one `git blame` away.

## What is and isn't translated

Translated: all UI chrome, dialogs, tooltips, accessibility narration, onboarding, the
About/FAQ prose, generated repo-summary and insight-card sentences.

Deliberately English, everywhere:
- Git plumbing output and backend error strings (`GitResult.err`) — so bug reports stay
  greppable and CLI/IPC consumers see stable text.
- LLM prompt scaffolding (model-facing, not user-facing).
- Brand and product names, model ids, keycap notation, technical notation (p50, ms, SHA).
- The versioned changelog (a historical record; new entries may be localized someday, but
  history is not retranslated).
- Git terms follow each language's established conventions from git's own `.po` files
  (e.g. German keeps "Commit", Chinese uses 提交, HEAD is never translated anywhere).

## Contributing a translation

You don't need to speak to the maintainer's language to help — you need to speak yours.

- Translation files live at `apps/desktop-flutter/lib/i18n/<locale>/<namespace>.i18n.json`
  (nested JSON, [slang](https://pub.dev/packages/slang) format). The English files under
  `lib/i18n/en/` are the source of truth for keys.
- Fix any string by PR. Keep `{placeholders}` exactly as-is, keep plural categories
  correct for your language, and don't translate the do-not-translate categories above.
- Punctuation follows YOUR language's conventions, not English style. The English source
  avoids em dashes as a stylistic choice; that does not override native grammar — Russian
  keeps its тире, French keeps its espaces insécables, CJK keeps full-width punctuation.
- In the same PR, update `provenance.json` for your locale: add yourself to `reviewers`
  (name + optional credential: native speaker, professionally trained, etc.) and bump
  `humanReviewedPercent` honestly (reviewed keys ÷ total keys).
- A locale flips from "machine translated" to "human translation" in the picker when its
  reviewers have covered substantially all strings (`source: "human"`).
- Translation PRs are contributions like any other: the PR template's one
  checkbox covers them (see [CONTRIBUTING.md](CONTRIBUTING.md)). You keep
  ownership of your work.
- New locale? Open an issue first. High-resource languages can launch AI-drafted;
  low-resource languages wait for a human reviewer before shipping — machine translation
  quality drops sharply where training data is thin, and shipping a bad translation with
  a disclaimer is still shipping a bad translation.

## For maintainers

- `dart run slang analyze --exit-if-changed` gates missing/unused keys in CI.
- New UI strings go in the feature's namespace file; never hardcode display literals.
- Regenerate after key changes: `dart run slang` (never edit `lib/i18n/gen/`).
- AI translation passes must name the actual model used in `provenance.json`, must not
  touch human-reviewed strings, and must update `generated`.
