# T3 Code UX Inspiration Audit

## Research Summary
Date: 2026-04-03

Primary sources reviewed:
- https://github.com/pingdotgg/t3code
- https://raw.githubusercontent.com/pingdotgg/t3code/main/LICENSE
- https://raw.githubusercontent.com/pingdotgg/t3code/main/.docs/workspace-layout.md
- https://raw.githubusercontent.com/pingdotgg/t3code/main/apps/web/src/index.css
- https://raw.githubusercontent.com/pingdotgg/t3code/main/apps/web/src/components/AppSidebarLayout.tsx
- https://raw.githubusercontent.com/pingdotgg/t3code/main/KEYBINDINGS.md

## License and Reuse Reality
T3 Code is MIT licensed. That generally allows copying and modification, including commercial use, as long as copyright and license notices are preserved.

Practical guardrails for respectful reuse:
- Keep MIT license notice for copied source files.
- Avoid copying brand assets, logo marks, names, and trademarked identity.
- Do not ship a look that could confuse users into thinking your app is officially T3 Code.

## Tech Stack Reality
T3 Code desktop app is Electron based.
Your app is Tauri based.

This is fine. UX patterns are portable even though the desktop shell differs.

## Core UX Patterns Worth Reusing

### 1. Sidebar-first Information Architecture
Observed pattern:
- Persistent left sidebar as the navigation spine.
- Sidebar supports collapse and resizing.
- Mobile behavior becomes a sheet panel.

Why it works:
- Keeps core context visible.
- Enables fast project and thread switching.
- Scales from laptop to ultrawide layouts.

How to apply to your Git app:
- Left sidebar for repositories, branches, saved filters, and worktree contexts.
- Persist width per user.
- Collapse to icon rail for focus mode.

### 2. Dense but Legible Control Rhythm
Observed pattern:
- Compact control sizes with strong spacing discipline.
- Rounded corners with consistent radius ladder.
- Muted surfaces with clear hover and active states.

Why it works:
- Feels fast and tool-like, not marketing-like.
- High information density without visual chaos.

How to apply:
- Keep command controls compact in commit and diff toolbars.
- Use consistent spacing increments and one radius system.

### 3. Command-centric Interaction Model
Observed pattern:
- Strong command palette and shortcut culture.
- Shortcut hints shown in menus and UI affordances.
- Keyboard handling is first-class, not an afterthought.

Why it works:
- Accelerates expert workflows.
- Reduces pointer travel cost.

How to apply:
- Command palette for Git actions and AI actions.
- Visible shortcut hints in all critical menus.
- Fast open actions: stage, commit, stash, switch branch, open diff, run AI review.

### 4. Contextual Panels and Sheets
Observed pattern:
- Secondary context opens as side sheets and inset panels.
- Diff and settings are treated as focused sub-surfaces.

Why it works:
- Preserves main flow while allowing depth.
- Better than full-page context switching.

How to apply:
- Open file diff as right-side panel when in changes view.
- Keep branch details and commit metadata as inspectable side panels.

### 5. Theme Token System Over Hardcoded Colors
Observed pattern:
- Uses CSS variables for background, foreground, border, accent, semantic statuses.
- Uses color mixing to keep surfaces cohesive.

Why it works:
- Easy theme consistency.
- Easier long-term restyling without refactoring every component.

How to apply:
- Define token sets for Git semantics: modified, added, deleted, conflicted, staged, unstaged.
- Keep Pretext diff rendering colors bound to same token system.

## Specific Layout Ideas to Borrow

### Window skeleton
- Top drag/title region with workspace identity.
- Left sidebar with resize rail.
- Main split area: changes list plus diff panel.
- Optional bottom drawer for logs, AI stream, and Git output.

### Sidebar hierarchy
- Header: repository switch, quick actions.
- Group A: local repositories and recents.
- Group B: current repo sections (Changes, History, Branches, Remotes, Stashes).
- Footer: settings, diagnostics, app version.

### Button placement
- Primary action near commit panel submit area.
- Secondary actions grouped in toolbar rows, icon + label for discoverability.
- Frequent toggles near relevant panel headers, not in global settings.

### State styling
- Strong active row highlight in sidebar.
- Softer selected row style for multi-select contexts.
- Subtle pulse only for live operations (fetch, push, AI stream), never static elements.

## Does It Match Your Vibe?
Yes. Strong match.

Why:
- Tool-first, dense, high-agency UX aligns with your anti-slop objective.
- Modular UI primitives map well to your fast-iteration strategy.
- Keyboard and panel-driven structure fits a Git desktop replacement.
- Their design language can be adapted to your app identity without inheriting Electron constraints.

## What Not to Copy 1:1
- Brand marks, logos, and exact iconography where identity is core.
- Product naming and branded visual motifs tied to T3.
- Any unique copy text that is clearly product-identifying.

## Recommended Adaptation Strategy
1. Copy structural patterns, not brand skin.
2. Build your own token palette and status semantics around Git workflows.
3. Keep T3-like compact ergonomics but define your own visual signature.
4. Add a git-native left rail taxonomy rather than chat-native taxonomy.
5. Keep the same responsiveness principles for desktop-first plus mobile fallback.
