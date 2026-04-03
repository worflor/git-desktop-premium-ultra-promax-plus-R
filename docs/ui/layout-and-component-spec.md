# UI Layout and Component Spec (Pre-Code)

## Intent
Define a compact, keyboard-first UI foundation with strong structure and low ambiguity for AI-generated implementation.

## Global Layout
1. Titlebar strip (drag region + workspace identity + status indicators).
2. Left sidebar (resizable, collapsible): repositories and navigation sections.
3. Main content split:
   - left/middle pane: changes or history list
   - right pane: diff panel or detail panel
4. Bottom utility drawer (collapsed by default): logs, diagnostics, AI stream.

## Density Policy
- Single compact mode only.
- No comfortable mode.
- Theme switching, panel resizing, and panel rearranging allowed.

## Route Skeleton
- /changes
- /history
- /branches
- /sync
- /settings

## Feature-Level Component Map

### Repositories
- RepositorySwitcher
- RecentRepositoriesPanel
- RepositoryHealthBadge

### Changes
- ChangesToolbar
- FileStatusList
- FileStatusRow
- CommitComposer
- CommitValidationHint

### Diff
- DiffShell
- DiffHeader
- DiffModeToggle
- DiffViewportDOM
- DiffViewportCanvas
- DiffSearchBar
- HunkNavigator

### History
- CommitTimeline
- CommitDetailPanel

### Sync
- SyncToolbar
- RemoteStatusCard
- AuthDiagnosticsCard

### AI
- AiProviderStatus
- AiActionBar
- AiStreamPanel
- AiAuditTrailPanel

### Settings
- GuardrailSliderCard
- ThemeCard
- LayoutControlsCard
- KeybindingsCard

## Class and Styling Conventions
1. Use token-driven classes from CSS variables only.
2. Keep semantic color classes for git states:
   - state-added
   - state-modified
   - state-deleted
   - state-conflicted
   - state-staged
   - state-unstaged
3. Keep interactive states explicit:
   - is-active
   - is-selected
   - is-pending
   - is-disabled
4. Prefer composition classes over deeply nested one-off selectors.

## Placeholder Components Required Before Feature Build
- AppShellFrame
- SidebarRail
- PanelResizer
- KeyboardShortcutHint
- StatusPill
- EmptyStateCard
- ErrorStateCard
- LoadingStateSkeleton

## Accessibility and Input Requirements
1. Full keyboard navigation for sidebar, list, diff, and command palette.
2. Focus ring visible for all interactive controls.
3. Icon-only controls require labels and tooltips.
4. Motion should respect reduced-motion preferences.

## Performance Constraints in UI Layer
1. No large list rendering without virtualization.
2. Diff surfaces must never rely on full-file DOM rendering.
3. Recompute Pretext layout only on width or font profile changes.
4. Keep expensive operations in workers where possible.
