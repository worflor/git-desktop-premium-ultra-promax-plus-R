# Labels

Three tiers, hard-capped. Exactly one Tier-1 label and exactly one Tier-2 label
per issue; Tier-3 labels are zero or more. A script can validate this; an agent
should.

## Tier 1 — type (exactly one)

| label | meaning |
|---|---|
| `bug` | Existing behavior is broken. |
| `enhancement` | New behavior. |
| `rework` | Existing behavior rebuilt or rebalanced — same spec, better implementation. Includes refactor, rebalance, and re-derivation after new understanding. Not a catch-all for "I feel like rewriting it." |
| `documentation` | Docs only. |

## Tier 2 — area (exactly one)

| label | meaning |
|---|---|
| `area:ui` | Desktop app surfaces (`apps/desktop-flutter`): panes, diff rendering, interaction, i18n, feel. |
| `area:cli` | `manifold` command-line surface (`bin`, `tool`, `tools`): output, flags, ergonomics. |
| `area:core` | VCS backends and shared plumbing: git integration, GitHub/GitLab/Gitea/local PRs, auth, settings, platform shells (windows/linux/macos). |
| `area:engine` | The coupling graph: spectral analysis, conflict prediction, X-ray, review grounding. |

## Tier 3 — execution flags (zero or more)

| label | meaning |
|---|---|
| `polish` | Small, batchable refinements. Group into one PR when convenient. |
| `straightforward` | Expected to be clear-cut: low ambiguity, bounded surface, independently verifiable. Routes to lighter model tiers in the agentic framework. Replaces GitHub's "good first issue" framing — the signal is task shape, not newcomer-friendliness. |
| `delicate` | Fine-grained work where the details carry the whole result: visual proportion, copy tone, interaction feel. Correctness alone is not success; needs taste and iteration. Routes to stronger tiers. The opposite of `straightforward`. |
| `freetime capable` | Opt-in for bounded Free Time proposals. Never authorizes merge. |
| `risky` | Touches auth or credential handling, or the coupling-graph semantics AI review is grounded in. An agent must stop and ask the owner before implementing; never picked up autonomously. |
| `autonomously-derived` | The issue originated in an autonomous session (Free Time, heartbeat, unattended run), not from the owner's direct request or interactive work. Provenance of *creation*, not evidence quality. |
| `quality-of-life` | Low priority but nice: tightens an existing loop without changing guarantees. |

Provenance of evidence is not a label (see the note below), but provenance of *session origin* is: it tells the owner which issues were born while nobody was watching, which changes how much to trust the framing before reading.

Provenance of evidence is not a label. Real-usage evidence belongs in the issue
body — the agent-ready template already mandates it — and a label that should be
on every well-formed issue distinguishes nothing. (The one provenance exception
is `autonomously-derived` above: it marks *session origin*, not evidence.)
Priority, if it ever matters, becomes
its own explicit tier when the need is real, not a smuggled axis with one value.

### Emergent routing, not explicit routing

Model tiers are never labeled on an issue. The framework derives them from the
label combination: `straightforward` + `area:cli` suggests the lightest tier;
`straightforward` + `area:ui` suggests a mid tier (UI verification needs a
desktop loop, not just correctness); no `straightforward`, or `risky` present,
suggests the strongest tier or a human. The labels carry the shape of the work;
the delegation policy maps shape to model. Keeping those separate means
rebalancing model assignments never requires re-tagging issues.

## Lifecycle plumbing (not taxonomy)

`duplicate`, `invalid`, `question`, `wontfix`, `help wanted` — GitHub mechanics,
not part of the system above.

## Rules

1. Every issue carries exactly one Tier-1 and exactly one Tier-2 label.
2. Tier-3 flags are optional and stack.
3. `risky` overrides `freetime capable`: if both apply, the agent stops and asks.
   4. `straightforward` and `delicate` are mutually exclusive: they are opposite
   ends of one axis. An issue carries at most one.
5. New labels are added only when an existing label cannot express the
   distinction without stretching. Tier counts stay capped (4 / 4 / 7).
6. Agents creating issues validate tiers before creating; agents picking work
   filter on Tier 2 + Tier 3 (`freetime capable` and not `risky`) before
   proposing.
