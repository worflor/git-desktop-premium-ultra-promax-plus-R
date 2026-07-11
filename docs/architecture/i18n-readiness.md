# i18n Readiness Dossier

Research synthesis (2026-07-11) for making Manifold multilingual by default. Five research
passes: slang package deep-dive, Flutter desktop locale plumbing, OSS translation
infrastructure + AI-disclosure precedents, migration tooling + git terminology, and a
read-only survey of this codebase's actual string surface. No code has been written; this
document is the full prep.

---

## 1. Decision: slang

**Package:** `slang` v4.18.0 (pub.dev). Actively maintained — canonical repo moved to
**Codeberg** (`codeberg.org/Tienisto/slang`); the GitHub repo `slang-i18n/slang` is a lagging
mirror, so never judge maintenance health by GitHub activity. Last commit July 5 2026.
Used in production by LocalSend, ReVanced, Saber.

Why slang over the official ARB/gen-l10n path:

- Missing/extra keys per locale are **compile-time errors** — the bug class "key exists in
  English but not Spanish" is unrepresentable. `slang analyze --exit-if-changed` exits 1 in CI.
- Nested JSON with per-feature namespace files maps 1:1 onto `lib/features/*`.
- `t.$wip('literal')` + `dart run slang wip apply` is a purpose-built literal→key migration
  mechanism — exactly the sweep tool for our ~1,200+ call sites.
- `slang normalize` output is deliberately formatted to match **Weblate**'s serializer
  (stable diffs on platform round-trips).
- `slang_mcp` package + `@@notes` fields in translation files exist specifically to give
  LLM translators context — aligned with the AI-draft strategy.
- Rich text (`(rich)` → TextSpan), linked translations (`@:key`), context/gender enums,
  ICU-style plurals with `pluralization.auto: cardinal`.

What slang does NOT replace: `flutter_localizations` delegates
(`GlobalMaterialLocalizations` etc.) still handle framework widget chrome (date pickers,
"OK"/"Cancel", tooltips of stock widgets) — 101 locale entries built in, enumerable via
`kMaterialSupportedLanguages`. slang drives `MaterialApp.locale` via
`TranslationProvider.of(context).flutterLocale`; the delegates consume it.

Key config decisions (`slang.yaml`):

- `input_file_pattern: .i18n.json`, `namespaces: true` (file per feature, nested namespaces
  supported since 4.14).
- `fallback_strategy: base_locale` — missing secondary-locale keys fall back to English at
  runtime (belt) while `slang analyze` gates them in CI (suspenders).
- `pluralization.auto: cardinal`. Built-in plural resolvers cover major languages (Arabic
  added natively in 4.15.0); unsupported locales throw at runtime unless
  `LocaleSettings.setPluralResolver` is provided — treat "does this locale have a native
  resolver" as a launch-checklist item per locale. (Authoritative resolver list: read
  slang's plural resolver source on Codeberg — not verified this pass.)
- Codegen via `dart run slang` / `dart run slang watch`. **Avoid the build_runner
  integration** — it has a documented history of asset-collision bugs (issue #90; v4.18.0
  shipped a "legacy build_runner mode" as a fix). The standalone CLI has none of that.
- Runtime switching: `LocaleSettings.setLocale(...)` / `LocaleSettings.useDeviceLocale()`
  (call before `runApp`), `TranslationProvider` at root, `Translations.of(context)` in
  widgets for locale-reactive rebuilds. Since 4.16 the device-locale preference respects
  the full OS locale list, not just the first entry.

Version gotcha: locale-tag parsing for plain `en-US`-style tags was fixed in 4.18.0 —
pin ≥4.18.0.

## 2. What the codebase actually looks like (survey)

- **Zero i18n today.** No `intl` dependency, no `DateFormat`/`NumberFormat` anywhere, no
  strings files. Every date, duration, byte size, and plural is hand-rolled English.
- **Estimate: ~1,200–1,800 distinct translatable strings** across ~900 `Text(` sites,
  ~180 hint/label form fields, ~70 tooltips, ~50 SnackBars, ~70 palette entries,
  ~380 backend `GitResult.err(...)` strings.
- Heaviest surfaces: `branches_page.dart` (240 Text, 14.5k lines),
  `settings_page.dart` (170), `changes_page.dart` (161), `backend/git.dart` (98 raw
  `.err()` strings), `repo_xray_panel.dart` (densest per-line, ~9 plural hazards).
- **Backend error strings flow raw into the UI** — `GitResult.err('Not a git repository')`
  etc. (383 sites, 18 files). Some interpolate raw stdout or exception text into the user
  string (`git.dart:2390`, `git.dart:4866`). These need an error-shape decision before
  translation (see §6, phase 4).
- **Plural hazards everywhere**: the `${n == 1 ? '' : 's'}` idiom appears dozens of times,
  including a shared helper `pluralize()` in `sync_actions.dart:9` and a duplicated
  `n == 1 ?` helper in `repo_summary/assembler.dart` + `prose.dart`. Worst case:
  triple-nested conditional sentence assembly in `repo_xray_panel.dart:2907`. Two
  independent plural clauses in one sentence at `changes_page.dart:15914`.
- **Relative time is hand-rolled and duplicated 10+ times** (`_compactAge()` in
  `sidebar_rail.dart:1521`, four independent sites in `branches_page.dart`, more in
  changes/history/diff/palette). Pre-migration refactor: one central formatter.
- **`repo_summary/` (prose.dart, naming.dart, …) is a mini NLG engine** — generative
  sentence assembly, not static strings. Structurally the hardest migration; either gets
  custom ICU composition per locale or explicitly ships English-first with the locale
  manifest saying so.
- **Do-not-translate inventory** (must be excluded from any sweep):
  - LLM prompt/persona strings in `backend/ai.dart` (~23 `'You are …'` builders, wakeFrames,
    commit-review personas). `ai.dart` is mixed-purpose — it also has real UI strings —
    so it can never be wildcard-migrated.
  - Brand names in `external_tools.dart:126-357` (`'Claude'`, `'VS Code'`, `'Cursor'`, …)
    and AI provider `displayName`s.
  - Storage/cache/preference key constants (settings stores, `storage_paths.dart`) —
    grep false positives, not display text.
  - Log/diagnostic output and anything a user would paste into a bug report verbatim.

## 3. Provenance: AI drafts, human override, honest disclosure

Design (precedent: LibreTranslate ships machine-translated locales managed via Weblate
with a per-locale `meta.json` carrying a reviewed flag; beyond that, no established OSS
convention for in-app AI-translation badges exists — we get to set the norm).

- Per-locale manifest **in-repo**, e.g. `i18n/es/provenance.json`:
  source per namespace or per key-range (`ai:claude-…` / `human`), generation date,
  reviewer list with self-claimed credential (native speaker / formally taught / …),
  and a **computed** human-review coverage %. Git history is the per-string audit trail;
  the manifest is the summary the app reads.
- **In-app disclosure generated from the manifest, never hand-written**: language picker
  shows e.g. "Español — machine translated (model name), 12% human reviewed". Manifest
  data drives it, so the claim can't rot.
- Policy doc (`TRANSLATIONS.md`, linked from CONTRIBUTING.md per the github/docs pattern):
  human translations always override AI; AI exists for accessibility coverage; PRs from
  reviewers flip keys ai→human; translator credit in an AUTHORS-style list.
- Review-without-speaking-the-language toolkit: Weblate's automated checks (placeholder
  integrity, ICU syntax), back-translation spot checks (different model translates
  target→source, diff meaning), glossary-term enforcement, screenshots for context.
- MT quality is tiered by language resources: LLM translation now beats specialized NMT
  for high-resource pairs but degrades sharply for low-resource languages
  (aclanthology.org/2026.loresmt-1.4). Low-resource locales therefore require human
  review **before shipping**, not just disclosure.

## 4. Launch locales

Anchor: JetBrains' 2025/2026 Developer Ecosystem Survey runs in exactly 10 languages —
English, Chinese, French, German, Japanese, Korean, Brazilian Portuguese, Russian,
Spanish, Turkish. Cross-referenced with MT-quality tiers:

- **Wave 1 (AI-draft at launch, all high-resource):** zh-CN (`zh-Hans`, use explicit
  scriptCode subtags), ja, ko, fr, de, es, pt-BR, ru.
- **Hold for human-reviewed-first:** tr, hi, and anything low-resource.
- **Defer RTL locales (ar, he, fa) deliberately** — this codebase is unusually
  RTL-hostile: custom painters everywhere (timeline spine, mosaic seam, growth rings,
  seismograph, worldline field) get zero automatic RTL support; every one needs
  hand-written direction-aware painting. Document the deferral in TRANSLATIONS.md rather
  than shipping a broken mirror. When RTL does happen: `EdgeInsetsDirectional`,
  `TextAlign.start`, per-icon mirror audit, test with real Arabic strings.

Terminology per locale — **align with git's own `.po` files** (highest-precedent corpus;
deviating creates "two dialects of git" between CLI and GUI). Extracted conventions:

| Term | de | fr | es | zh-CN | ru |
|---|---|---|---|---|---|
| commit | Commit (kept) | commit (kept) | commit (kept) | 提交 | коммит |
| stage/index | Staging-Area/Index | indexer (translated) | stage (loan) | 暂存(区) | индекс |
| rebase | rebase (kept) | rebaser (coined) | rebasar (coined) | 变基 | перемещение |
| merge | mergen (verbed loan) | fusionner | hacer merge | 合并 | слияние |
| push/pull | pushen/pullen | pousser/tirer | push/pull (kept) | 推送/拉取 | отправить/получить |
| stash | stashen | remiser | hacer stash | 储藏 | спрятать |
| branch | Branch (kept) | branche | rama | 分支 | ветка |
| cherry-pick | Cherry-Picken | picorer | cherry-picking | 拣选 | descriptive phrase |
| HEAD | **kept untranslated in every locale checked** | | | | |
| working tree | Arbeitsverzeichnis | arbre de travail | árbol de trabajo | 工作区 | рабочий каталог |

Pattern: zh-CN translates nearly everything into native compounds; de/es keep English
nouns and verb them; fr translates most aggressively; HEAD is a universal proper noun.
Caveats: table extracted via LLM read of live .po files — spot-check before shipping any
string verbatim. **git core has no `ja` or `pt_BR` locale at all** — for those, mine
GitHub Desktop's Crowdin / VS Code language packs (`vscode-loc` per-language repos)
instead. Ship the glossary as `@@notes` in the base files so AI translators inherit it.

## 5. Platform + community infrastructure

- **Weblate, Hosted, Libre plan** (free for public libre projects; apply at weblate.org).
  Format slug: **"JSON nested structure file"** (plain "JSON file" can misplace new nested
  keys). Configure the component in **PR mode** (opens GitHub PRs) rather than
  direct-push, so translation changes flow through normal review. Built-in checks:
  `placeholders`, `icu_message_format`, consistency. Suggestion→approve workflow fits
  "AI drafts, human approves".
  - **Open question (critical):** whether Weblate labels/flags round-trip into the JSON
    file vs. staying DB-side. Our provenance lives in-repo, so the manifest must be
    updated by the translation PRs themselves (CI can diff which keys changed per PR and
    update provenance mechanically — that works regardless of Weblate's answer).
- Alternatives assessed: Crowdin (good OSS tier, ships its own AI pipeline, but
  no-commercial-product restriction), Tolgee (self-host, Flutter integration is Alpha),
  Transifex (OSS tier forbids any monetization — disqualifying if Manifold ever charges).
  Weblate is the fit.

## 6. Migration plan (phases, for when the tree is clean)

Lint-gate first, then sweep — stop the bleeding before draining the pool.

1. **Scaffold.** Add `slang` ≥4.18.0 + `flutter_localizations` + `intl`. `slang.yaml` with
   namespaces mirroring `lib/features/` + `app` (workspace shell) + `errors` + `common`.
   `TranslationProvider` at root, delegates wired, `LocaleSettings.useDeviceLocale()`
   before `runApp`, language picker in settings (persisted choice = a display law, so it
   IS persisted). English base files only.
2. **Lint gate.** `hardcoded_strings_lint` v2.1+ (rule
   `avoid_hardcoded_strings_in_widgets`, official `analysis_server_plugin` system, needs
   Dart 3.10+/Flutter 3.38+ — verify our pin). Configure via top-level `plugins:` key.
   Check whether `tooltip:` is on its default allowlist and un-allowlist it (tooltips are
   user-facing). Plus `dart run slang analyze --exit-if-changed` in CI. New hardcoded
   strings become impossible before old ones are gone.
3. **Centralize formatting.** One relative-time formatter (replacing `_compactAge` + the
   ~10 duplicated `DateTime.now().difference` phrasings), one byte-size formatter, replace
   `pluralize()` and the duplicated repo_summary helpers with slang plurals. This shrinks
   the sweep and fixes the worst ICU hazards at their choke points.
4. **Decide the error shape.** `GitResult.err()` strings (383 sites) either become typed
   error values rendered through slang at the UI boundary (right fix — matches the sealed
   types + exhaustive switch house rule) or stay English (defensible: greppable bug
   reports). Likely split: high-frequency user-flow errors typed and translated;
   plumbing/edge errors stay English verbatim. Decide before the sweep, not during.
5. **The sweep**, feature-batched (one namespace = one PR-sized unit), heaviest first:
   branches → settings → changes → workspace shell → xray → history → diff → palette →
   the rest. Mechanism: `t.$wip()` markers + `slang wip apply`, or direct keying —
   fan-out-friendly since namespaces don't collide. Key convention: camelCase,
   `feature.screen.element`, shared terms in `common` via linked translations (`@:`).
   `release_notes_panel.dart` changelog prose: append-only versioned namespace or
   explicitly English — don't retranslate history.
6. **Pseudo-locale before real locales.** Generate a pseudo-locale (vowel-stretched,
   ~40% expanded — `flutter_pseudolocalizor` is ARB-oriented, so a small script over our
   JSON is fine) to surface missed strings and layout overflow. German/Finnish compounds
   defeat word-wrap, so test single-long-word cases too. Fix overflow with
   Flexible/Wrap/ellipsis-as-last-resort.
7. **AI draft pass** (wave-1 locales), glossary-anchored via `@@notes`, provenance
   manifests written, in-app disclosure wired, Weblate connected in PR mode.

## 7. Desktop plumbing gotchas (verify empirically, per house rule)

- **Windows OS-locale detection**: Flutter returns the *first* entry of the Windows
  language-preference list, not the display language (flutter#119811 — closed as
  by-design), and Swiss-German-style region tags mis-resolve (flutter#143373, open).
  Mitigation: our own settings override is the primary path; OS detection is just the
  default. Read locale from `WidgetsBinding.instance.platformDispatcher.locales` (full
  list), not `Platform.localeName`.
- **`didChangeLocales` on desktop is unverified** — known not to fire on Android
  (flutter#106001); no first-party evidence for Windows/Linux/macOS. Test on all three;
  if flaky, re-check locale on window focus as fallback.
- Locale resolution: Flutter's `basicLocaleListResolution` (perfect → lang+script →
  lang+country → lang → country → first supported). Declare `zh` with explicit
  `scriptCode` subtags (`zh-Hans`/`zh-Hant`) — and slang 4.15+ region-extension fallback
  (`de-CH`→`de`) covers the rest.
- **intl**: `initializeDateFormatting(locale)` must be awaited per locale before any
  `DateFormat` use (throws otherwise). Pass locale explicitly to every
  DateFormat/NumberFormat call rather than mutating the global `Intl.defaultLocale`.
- **CJK fonts**: default system-fallback is fine on Windows/x64 Linux; known tofu bug on
  ARM64 Linux (`libflutter_linux_gtk.so` not linked against Fontconfig, flutter#139293).
  CJK glyph-variant steering (avoid zh-CN glyphs rendering for ja) may need
  locale-tagged TextStyle (flutter#16870). CJK generally wants slightly more line-height —
  visual-QA item, no citable constant. Prefer system fonts over bundling Noto CJK
  (many MB per weight).
- Material widget chrome (pickers, semantics) localizes itself once delegates + locale
  are wired — all wave-1 locales are within the 101 built-ins.

## 8. CI laws (armed at scaffold time)

1. `dart run slang analyze --exit-if-changed` — no missing/unused keys in any locale.
2. `hardcoded_strings_lint` at error tier — no new hardcoded UI strings.
3. Provenance manifests are computed/validated in CI (coverage % matches file state;
   translation PRs mechanically flip ai→human on touched keys).
4. Placeholder-integrity check on translation PRs (Weblate does it platform-side; a small
   test can re-verify in-repo: same placeholder set per key across locales).
5. Pseudo-locale build stays green (proves the pipeline itself never regresses).

## 9. Open questions / unverified

- Weblate label/flag round-trip into JSON files (provenance automation shape depends on
  it; the CI-diff approach works either way). — check against Weblate's JSON serializer.
- slang's authoritative native plural-resolver language list — read
  Codeberg source before each locale launch.
- slang 4.18.0 exact SDK floor — check pubspec on pub.dev when scaffolding.
- `hardcoded_strings_lint` requires Dart 3.10+/Flutter 3.38+ — verify against our pin.
- ja / pt-BR git terminology (absent from git core) — mine vscode-loc language packs or
  GitHub Desktop's Crowdin.
- `didChangeLocales` behavior on Windows/macOS/Linux — empirical test at scaffold time.
- git .po terminology table — spot-check against raw .po before shipping strings.
