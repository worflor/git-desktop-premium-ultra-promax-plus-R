import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_identity.dart';
import '../../../components/hypercube_logo.dart';
import '../../../components/icons/app_icons.dart';
import '../../../ui/design_primitives.dart';
import '../../../ui/form_controls.dart';
import '../../../ui/motion.dart';
import '../../../ui/tokens.dart';

/// Miniature of the real workspace, built from stateless widgets that
/// consume [AppTokens] — so the preview reskins for free when the theme
/// changes.
/// Lowkey interactive: file checkboxes toggle their staged state, the
/// top-right icon row switches the "active" panel, and rows hover-lift.
/// Nothing is wired to real repo state — it's just playful tactility so
/// the preview rewards people who poke at it.
class WorkspacePreview extends StatefulWidget {
  const WorkspacePreview({super.key});

  @override
  State<WorkspacePreview> createState() => _WorkspacePreviewState();
}

enum _PreviewPanel { changes, history, branches, xray, settings }

class _PreviewFile {
  final String name;
  final String path;
  final String status; // 'Untracked' | 'Edited'
  final int added;
  final int removed;
  const _PreviewFile(
    this.name,
    this.path,
    this.status,
    this.added,
    this.removed,
  );
}

class _WorkspacePreviewState extends State<WorkspacePreview> {
  // The worklines below echo the commit-format preview's canon so anyone
  // who's read both gets the wink. Kept intentionally concise so the mini
  // ui still feels like a real client at a glance.
  static const List<_PreviewFile> _files = [
    _PreviewFile('fox.dart', 'lib/forest', 'Untracked', 18, 0),
    _PreviewFile('amber.dart', 'lib/scent', 'Edited', 12, 3),
    _PreviewFile('thorn.dart', 'lib/gate', 'Edited', 6, 2),
    _PreviewFile('README.md', '', 'Edited', 2, 2),
  ];

  _PreviewPanel _panel = _PreviewPanel.changes;
  late Set<int> _staged;
  int _selectedFile = 0;

  @override
  void initState() {
    super.initState();
    // Start with the first two files pre-staged so the commit composer has
    // a non-zero count; toggling later shows live feedback.
    _staged = {0, 1};
  }

  void _toggle(int index) {
    setState(() {
      if (_staged.contains(index)) {
        _staged.remove(index);
      } else {
        _staged.add(index);
      }
    });
  }

  void _toggleAll(bool stageAll) {
    setState(() {
      _staged = stageAll
          ? Set<int>.from(List.generate(_files.length, (i) => i))
          : <int>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final identity = context.watch<AppIdentityState>().identity;
    return Container(
      decoration: BoxDecoration(
        color: t.bg1,
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewTopBar(
            tokens: t,
            shortName: identity.shortName,
            activePanel: _panel,
            onPanelChanged: (p) => setState(() => _panel = p),
          ),
          Expanded(
            child: Row(
              children: [
                _PreviewSidebar(tokens: t, shortName: identity.shortName),
                Container(width: 1, color: t.chromeBorder),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: context.motion(AppMotion.fade),
                    switchInCurve: AppMotion.fadeCurve,
                    switchOutCurve: AppMotion.fadeCurve,
                    child: KeyedSubtree(
                      key: ValueKey(_panel),
                      child: _panelBody(t),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelBody(AppTokens t) {
    return switch (_panel) {
      _PreviewPanel.changes => _ChangesPanel(
          tokens: t,
          files: _files,
          staged: _staged,
          selectedFile: _selectedFile,
          onToggle: _toggle,
          onToggleAll: _toggleAll,
          onSelectFile: (i) => setState(() => _selectedFile = i),
        ),
      _PreviewPanel.history => _HistoryPanel(tokens: t),
      _PreviewPanel.branches => _BranchesPanel(tokens: t),
      _PreviewPanel.xray =>
        _SimpleCaption(tokens: t, icon: 'xray', text: 'repo x-ray'),
      _PreviewPanel.settings =>
        _SimpleCaption(tokens: t, icon: 'settings', text: 'settings'),
    };
  }
}


class _PreviewTopBar extends StatelessWidget {
  final AppTokens tokens;
  final String shortName;
  final _PreviewPanel activePanel;
  final ValueChanged<_PreviewPanel> onPanelChanged;

  const _PreviewTopBar({
    required this.tokens,
    required this.shortName,
    required this.activePanel,
    required this.onPanelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border(bottom: BorderSide(color: tokens.chromeBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  shortName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                _BranchPill(tokens: tokens),
              ],
            ),
          ),
          _TopIconButton(
            tokens: tokens,
            icon: 'changes',
            active: activePanel == _PreviewPanel.changes,
            onTap: () => onPanelChanged(_PreviewPanel.changes),
          ),
          _TopIconButton(
            tokens: tokens,
            icon: 'history',
            active: activePanel == _PreviewPanel.history,
            onTap: () => onPanelChanged(_PreviewPanel.history),
          ),
          _TopIconButton(
            tokens: tokens,
            icon: 'branches',
            active: activePanel == _PreviewPanel.branches,
            onTap: () => onPanelChanged(_PreviewPanel.branches),
          ),
          _TopIconButton(
            tokens: tokens,
            icon: 'xray',
            active: activePanel == _PreviewPanel.xray,
            onTap: () => onPanelChanged(_PreviewPanel.xray),
          ),
          _TopIconButton(
            tokens: tokens,
            icon: 'settings',
            active: activePanel == _PreviewPanel.settings,
            onTap: () => onPanelChanged(_PreviewPanel.settings),
          ),
        ],
      ),
    );
  }
}

class _BranchPill extends StatelessWidget {
  final AppTokens tokens;
  const _BranchPill({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.panelOverlay.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.chromeBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_split, size: 9, color: tokens.accentBright),
          const SizedBox(width: 4),
          Text(
            'main',
            style: TextStyle(
              color: tokens.textNormal,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 3),
          Icon(Icons.chevron_right, size: 9, color: tokens.textFaint),
          const SizedBox(width: 4),
          Container(width: 1, height: 10, color: tokens.chromeBorder),
          const SizedBox(width: 4),
          Text(
            '↑2',
            style: TextStyle(
              color: tokens.stateAdded,
              fontSize: 8,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '↓0',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 8,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopIconButton extends StatefulWidget {
  final AppTokens tokens;
  final String icon;
  final bool active;
  final VoidCallback onTap;

  const _TopIconButton({
    required this.tokens,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TopIconButton> createState() => _TopIconButtonState();
}

class _TopIconButtonState extends State<_TopIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final bg = widget.active
        ? t.itemActiveBg
        : _hover
            ? t.itemHoverBg
            : t.itemHoverBg.withValues(alpha: 0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.active
                  ? t.itemActiveBorder
                  : t.itemActiveBorder.withValues(alpha: 0),
            ),
            // Same accent halo the real mode buttons wear when selected.
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: t.accentBright.withValues(alpha: 0.25),
                      blurRadius: 1,
                      spreadRadius: 0.5,
                    ),
                  ]
                : const [],
          ),
          child: AppIcon(
            name: widget.icon,
            size: 12,
            color: widget.active ? t.accentBright : t.textMuted,
          ),
        ),
      ),
    );
  }
}


class _PreviewSidebar extends StatelessWidget {
  final AppTokens tokens;
  final String shortName;
  const _PreviewSidebar({required this.tokens, required this.shortName});

  @override
  Widget build(BuildContext context) {
    const projects = [
      'worflor.github.io',
      'git-desktop-premium-ul…',
      'fox-and-amber',
    ];
    return Container(
      width: 108,
      color: tokens.bg0,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const HypercubeLogo(size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shortName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Projects',
                  style: TextStyle(
                    color: tokens.textFaint,
                    fontSize: 8,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.add, size: 10, color: tokens.textFaint),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < projects.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: _SidebarItem(
                tokens: tokens,
                label: projects[i],
                active: i == 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final AppTokens tokens;
  final String label;
  final bool active;
  const _SidebarItem({
    required this.tokens,
    required this.label,
    required this.active,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: context.motion(AppMotion.snap),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: widget.active
              ? t.itemActiveBg
              : _hover
                  ? t.itemHoverBg
                  : t.itemHoverBg.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.active
                ? t.itemActiveBorder
                : t.itemActiveBorder.withValues(alpha: 0),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.active ? t.textStrong : t.textMuted,
                  fontSize: 9.5,
                  fontWeight:
                      widget.active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ChangesPanel extends StatelessWidget {
  final AppTokens tokens;
  final List<_PreviewFile> files;
  final Set<int> staged;
  final int selectedFile;
  final ValueChanged<int> onToggle;
  final ValueChanged<bool> onToggleAll;
  final ValueChanged<int> onSelectFile;

  const _ChangesPanel({
    required this.tokens,
    required this.files,
    required this.staged,
    required this.selectedFile,
    required this.onToggle,
    required this.onToggleAll,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _FileList(
            tokens: tokens,
            files: files,
            staged: staged,
            selected: selectedFile,
            onToggle: onToggle,
            onToggleAll: onToggleAll,
            onSelectFile: onSelectFile,
          ),
        ),
        Container(width: 1, color: tokens.chromeBorder),
        Expanded(
          flex: 6,
          child: Consumer<AppIdentityState>(
            builder: (context, identityState, _) => _DiffPanel(
              tokens: tokens,
              file: files[selectedFile.clamp(0, files.length - 1)],
              shortName: identityState.identity.shortName,
            ),
          ),
        ),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  final AppTokens tokens;
  final List<_PreviewFile> files;
  final Set<int> staged;
  final int selected;
  final ValueChanged<int> onToggle;
  final ValueChanged<bool> onToggleAll;
  final ValueChanged<int> onSelectFile;

  const _FileList({
    required this.tokens,
    required this.files,
    required this.staged,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
    required this.onSelectFile,
  });

  @override
  Widget build(BuildContext context) {
    final allStaged = staged.length == files.length;
    final noneStaged = staged.isEmpty;
    final _ToggleAllState toggleState = allStaged
        ? _ToggleAllState.all
        : noneStaged
            ? _ToggleAllState.none
            : _ToggleAllState.partial;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: tokens.chromeBorder),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${staged.length} of ${files.length} files',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _ToggleAllButton(
                tokens: tokens,
                state: toggleState,
                // Smart toggle: if everything is staged, clear it; if
                // nothing or some, stage everything. Same pattern as the
                // real changes page.
                onTap: () => onToggleAll(!allStaged),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            // PageStorageKey survives the widget-tree restructures
            // caused by `MaterialSurface` flipping between glass and
            // solid shape on theme switch — same fix applied to the
            // theme picker's scroll view.
            key: const PageStorageKey('onboarding.workspacePreview.fileList'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: files.length,
            itemBuilder: (context, index) => _FileRow(
              tokens: tokens,
              file: files[index],
              staged: staged.contains(index),
              selected: selected == index,
              onToggle: () => onToggle(index),
              onSelect: () => onSelectFile(index),
            ),
          ),
        ),
        _CommitComposer(tokens: tokens, stagedCount: staged.length),
      ],
    );
  }
}

enum _ToggleAllState { none, partial, all }

/// Single smart toggle — unchecked when nothing is staged, a dash when
/// partially staged, a check when everything is staged. One tap flips
/// between "all" and "none"; the tri-state is purely visual so the user
/// can see at a glance what they're about to do.
class _ToggleAllButton extends StatefulWidget {
  final AppTokens tokens;
  final _ToggleAllState state;
  final VoidCallback onTap;

  const _ToggleAllButton({
    required this.tokens,
    required this.state,
    required this.onTap,
  });

  @override
  State<_ToggleAllButton> createState() => _ToggleAllButtonState();
}

class _ToggleAllButtonState extends State<_ToggleAllButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final filled = widget.state != _ToggleAllState.none;
    final borderColor = filled ? t.accentBright : t.btnBorder;
    final bg = filled
        ? t.accentBright.withValues(alpha: _hover ? 0.22 : 0.14)
        : _hover
            ? t.itemHoverBg
            : t.btnBg;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
          child: switch (widget.state) {
            _ToggleAllState.all =>
              Icon(Icons.check, size: 11, color: t.accentBright),
            _ToggleAllState.partial =>
              Container(
                width: 8,
                height: 2,
                decoration: BoxDecoration(
                  color: t.accentBright,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            _ToggleAllState.none => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final AppTokens tokens;
  final _PreviewFile file;
  final bool staged;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onSelect;

  const _FileRow({
    required this.tokens,
    required this.file,
    required this.staged,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final statusColor = widget.file.status == 'Untracked'
        ? t.stateAdded
        : t.stateModified;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: widget.selected
                ? t.itemActiveBg
                : _hover
                    ? t.itemHoverBg
                    : widget.staged
                        ? t.stateAdded.withValues(alpha: 0.08)
                        : t.stateAdded.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: widget.selected
                  ? t.itemActiveBorder
                  : widget.staged
                      ? t.stateAdded.withValues(alpha: 0.3)
                      : t.stateAdded.withValues(alpha: 0),
            ),
          ),
          child: Row(
            children: [
              AppCheckbox(
                value: widget.staged,
                onChanged: (_) => widget.onToggle(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.file.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.file.path.isNotEmpty)
                      Text(
                        widget.file.path,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textFaint,
                          fontSize: 8.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  widget.file.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitComposer extends StatelessWidget {
  final AppTokens tokens;
  final int stagedCount;
  const _CommitComposer({required this.tokens, required this.stagedCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: tokens.bg0,
        border: Border(top: BorderSide(color: tokens.chromeBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$stagedCount staged',
            style: TextStyle(
              color: tokens.textFaint,
              fontSize: 8.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.inputBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tokens.inputBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Commit message…',
                    style: TextStyle(
                      color: tokens.textFaint,
                      fontSize: 9,
                    ),
                  ),
                ),
                AppIcon(name: 'search', size: 9, color: tokens.textFaint),
                const SizedBox(width: 6),
                Icon(Icons.auto_awesome_outlined,
                    size: 10, color: tokens.accentBright),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _HoverScale(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: tokens.accentBright.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: tokens.accentBright.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                      name: 'push', size: 10, color: tokens.textStrong),
                  const SizedBox(width: 6),
                  Text(
                    'Commit & push',
                    style: TextStyle(
                      color: tokens.textStrong,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny press/hover scale wrapper — adds a pinch of life to the commit
/// button without wiring it to anything real.
class _HoverScale extends StatefulWidget {
  final Widget child;
  const _HoverScale({required this.child});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _scale = 1.015),
      onExit: (_) => setState(() => _scale = 1.0),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.97),
        onTapCancel: () => setState(() => _scale = 1.015),
        onTapUp: (_) => setState(() => _scale = 1.015),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _scale,
          duration: context.motion(AppMotion.snap),
          curve: AppMotion.snapCurve,
          child: widget.child,
        ),
      ),
    );
  }
}


class _DiffPanel extends StatelessWidget {
  final AppTokens tokens;
  final _PreviewFile file;
  final String shortName;
  const _DiffPanel({
    required this.tokens,
    required this.file,
    required this.shortName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.bg1,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '+${file.added} -${file.removed}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: tokens.bg0,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: tokens.chromeBorder),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _diffLinesFor(file, tokens, shortName),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _diffLinesFor(_PreviewFile f, AppTokens t, String name) {
    // Same canon as the commit-format preview: fox/amber/thorn, one scene.
    // The README branch picks up the user's chosen app name so the preview
    // reflects what they just named the client.
    final List<(String, String)> lines = switch (f.name) {
      'fox.dart' => const [
          ('+', '  fox.sniff(token);'),
          ('+', '  fox.remember(trail);'),
          ('+', '  return trail;'),
        ],
      'amber.dart' => const [
          ('+', '  amber.witness(scent);'),
          ('-', '  amber.log(scent);'),
          (' ', '  return amber.last();'),
        ],
      'thorn.dart' => const [
          ('+', '  thorn.mark(refusal);'),
          ('-', '  gate.reject();'),
          (' ', '  return refusal;'),
        ],
      _ => [
          ('+', '  ## $name'),
          ('+', '  Your personal Git client.'),
          (' ', ''),
        ],
    };

    return [
      for (var i = 0; i < lines.length; i++)
        _DiffLine(
          tokens: t,
          lineNumber: i + 1,
          prefix: lines[i].$1,
          text: lines[i].$2,
        ),
    ];
  }
}

class _DiffLine extends StatelessWidget {
  final AppTokens tokens;
  final int lineNumber;
  final String prefix;
  final String text;
  const _DiffLine({
    required this.tokens,
    required this.lineNumber,
    required this.prefix,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (prefix) {
      '+' => tokens.stateAdded,
      '-' => tokens.stateDeleted,
      _ => tokens.textMuted,
    };
    final rowBg = switch (prefix) {
      '+' => tokens.stateAdded.withValues(alpha: 0.10),
      '-' => tokens.stateDeleted.withValues(alpha: 0.10),
      _ => Colors.transparent,
    };
    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(vertical: 0.6),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: tokens.textFaint,
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 10,
            child: Text(
              prefix,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _MiniCommit {
  final String sha;
  final String msg;
  final String time;
  final String? tag;
  final int added;
  final int removed;
  final bool pushed;
  const _MiniCommit(
    this.sha,
    this.msg,
    this.time,
    this.tag,
    this.added,
    this.removed,
    this.pushed,
  );
}

/// Miniature of the real History page: worldline strip up top (dots on a
/// smoothed trace, unpushed span tinted, HEAD caret), an IN FLIGHT band,
/// then the commit list. Hovering the strip highlights the matching row
/// and vice versa — same shared-hover channel the real page has.
class _HistoryPanel extends StatefulWidget {
  final AppTokens tokens;
  const _HistoryPanel({required this.tokens});

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  // Same fox/amber/thorn canon as the changes panel — the two newest
  // commits are still local-only so the strip gets its stateAdded span.
  static const List<_MiniCommit> _commits = [
    _MiniCommit('a3f19', 'teach fox to sniff before swallowing', '2m ago',
        'forest', 18, 0, false),
    _MiniCommit(
        'b71e0', 'amber: hold scent overnight', '1h ago', 'scent', 12, 3,
        false),
    _MiniCommit('cc8d2', 'retire cabbage in favor of amber + thorn',
        '3h ago', null, 6, 9, true),
    _MiniCommit('d5e4b', 'thorn guards the gate', '1d ago', 'gate', 4, 2,
        true),
  ];

  int _selected = 0;
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Container(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: t.surface1,
              border: Border(
                bottom: BorderSide(
                  color: t.chromeBorder.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'History',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'viewing last 20 commits',
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 7.5,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: _WorldlineStrip(
              tokens: t,
              commitCount: _commits.length,
              selected: _selected,
              hovered: _hovered,
              onHover: (i) => setState(() => _hovered = i),
              onSelect: (i) => setState(() => _selected = i),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: t.accentBright.withValues(alpha: 0.04),
              border: Border(
                top: BorderSide(
                  color: t.chromeBorder.withValues(alpha: 0.4),
                ),
                bottom: BorderSide(
                  color: t.chromeBorder.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'IN FLIGHT',
                  style: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.85),
                    fontSize: 7,
                    height: 1,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: t.chromeBorder.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'fox/sniff',
                        style: TextStyle(
                          color: t.textNormal,
                          fontSize: 8,
                          height: 1.2,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '↑2',
                        style: TextStyle(
                          color: t.stateAdded,
                          fontSize: 8,
                          height: 1.2,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const PageStorageKey(
                'onboarding.workspacePreview.historyList',
              ),
              padding: EdgeInsets.zero,
              itemCount: _commits.length,
              itemBuilder: (context, i) => _MiniCommitRow(
                tokens: t,
                commit: _commits[i],
                selected: _selected == i,
                hovered: _hovered == i,
                onHover: (h) => setState(() => _hovered = h ? i : null),
                onTap: () => setState(() => _selected = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The worldline, in its pulled-out posture: a smoothed trace through
/// commit dots, faded toward the past, unpushed span tinted stateAdded
/// with a frontier tick, HEAD caret over the newest dot. The last
/// [commitCount] dots are hit-targets wired to the commit list.
class _WorldlineStrip extends StatelessWidget {
  final AppTokens tokens;
  final int commitCount;
  final int selected;
  final int? hovered;
  final ValueChanged<int?> onHover;
  final ValueChanged<int> onSelect;

  const _WorldlineStrip({
    required this.tokens,
    required this.commitCount,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onSelect,
  });

  // Node index 0 = oldest (left), last = newest (right / HEAD).
  static const int _nodeCount = 12;
  static const int _unpushed = 2;
  // Deterministic "churn" heights — the little zigzag that makes the
  // pulled-out worldline look alive.
  static const List<double> _ys = [
    0.62, 0.34, 0.55, 0.30, 0.48, 0.66, 0.38, 0.58, 0.30, 0.52, 0.26, 0.44,
  ];

  // 8px inset matches the panel's content grid (header padding, commit
  // row gutter) so the strip doesn't read as floating in its own frame.
  static Offset _node(Size size, int i) {
    final dx = 8 + (size.width - 16) * i / (_nodeCount - 1);
    return Offset(dx, 6 + (size.height - 14) * _ys[i]);
  }

  /// Which commit-list row a node maps to (newest node = row 0), or null.
  int? _rowFor(int node) {
    final row = _nodeCount - 1 - node;
    return row < commitCount ? row : null;
  }

  int? _hitNode(Size size, Offset pos) {
    for (var i = 0; i < _nodeCount; i++) {
      if ((pos - _node(size, i)).distance < 7) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onHover: (e) {
            final n = _hitNode(size, e.localPosition);
            onHover(n == null ? null : _rowFor(n));
          },
          onExit: (_) => onHover(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) {
              final n = _hitNode(size, e.localPosition);
              final row = n == null ? null : _rowFor(n);
              if (row != null) onSelect(row);
            },
            child: CustomPaint(
              size: size,
              painter: _WorldlinePainter(
                tokens: tokens,
                selectedNode: _nodeCount - 1 - selected,
                hoveredNode:
                    hovered == null ? null : _nodeCount - 1 - hovered!,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorldlinePainter extends CustomPainter {
  final AppTokens tokens;
  final int selectedNode;
  final int? hoveredNode;

  _WorldlinePainter({
    required this.tokens,
    required this.selectedNode,
    required this.hoveredNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const n = _WorldlineStrip._nodeCount;
    const unpushed = _WorldlineStrip._unpushed;
    final pts = [for (var i = 0; i < n; i++) _WorldlineStrip._node(size, i)];

    // Faint resting rail behind everything.
    final railY = size.height * 0.5;
    canvas.drawLine(
      Offset(8, railY),
      Offset(size.width - 8, railY),
      Paint()
        ..color = tokens.chromeAccent.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );

    // Trace, oldest→newest, alpha ramping up toward now — Catmull-Rom
    // smoothed like the real worldline so it flows instead of stepping.
    // Pushed segments in chromeAccent; the unpushed tail in stateAdded.
    for (var i = 0; i < n - 1; i++) {
      final tNorm = i / (n - 2);
      final local = i >= n - 1 - unpushed;
      final paint = Paint()
        ..color = local
            ? tokens.stateAdded.withValues(alpha: 0.45)
            : tokens.chromeAccent.withValues(alpha: 0.10 + 0.26 * tNorm)
        ..strokeWidth = local ? 1.4 : 1.1
        ..style = PaintingStyle.stroke;
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 > n - 1 ? n - 1 : i + 2];
      final c1 = p1 + (p2 - p0) * (1 / 6);
      final c2 = p2 - (p3 - p1) * (1 / 6);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }

    // Push-frontier tick where local-only history begins.
    final frontier = pts[n - 1 - unpushed];
    canvas.drawLine(
      Offset(frontier.dx, frontier.dy - 5),
      Offset(frontier.dx, frontier.dy + 5),
      Paint()
        ..color = tokens.stateAdded.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );

    // Dots.
    for (var i = 0; i < n; i++) {
      final local = i >= n - unpushed;
      final selectedHere = i == selectedNode;
      final r = 1.8 + _WorldlineStrip._ys[i] * 1.4;
      final color = selectedHere
          ? tokens.accentBright
          : local
              ? tokens.stateAdded.withValues(alpha: 0.85)
              : tokens.chromeBorder.withValues(alpha: 0.7);
      canvas.drawCircle(pts[i], r, Paint()..color = color);
      if (selectedHere) {
        canvas.drawCircle(
          pts[i],
          r + 1.5,
          Paint()
            ..color = tokens.accentBright.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (i == hoveredNode && !selectedHere) {
        canvas.drawCircle(
          pts[i],
          r + 2.4,
          Paint()
            ..color = tokens.chromeAccent.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // HEAD caret above the newest dot.
    final head = pts[n - 1];
    final caret = Path()
      ..moveTo(head.dx - 3, head.dy - 9)
      ..lineTo(head.dx + 3, head.dy - 9)
      ..lineTo(head.dx, head.dy - 5)
      ..close();
    canvas.drawPath(
      caret,
      Paint()..color = tokens.accentBright.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_WorldlinePainter old) =>
      old.selectedNode != selectedNode ||
      old.hoveredNode != hoveredNode ||
      old.tokens != tokens;
}

class _MiniCommitRow extends StatelessWidget {
  final AppTokens tokens;
  final _MiniCommit commit;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _MiniCommitRow({
    required this.tokens,
    required this.commit,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
          decoration: BoxDecoration(
            color: selected
                ? t.itemActiveBg
                : hovered
                    ? t.itemHoverBg
                    : t.itemHoverBg.withValues(alpha: 0),
            border: Border(
              left: BorderSide(
                width: 2,
                color: selected
                    ? t.itemActiveBorder
                    : t.itemActiveBorder.withValues(alpha: 0),
              ),
              bottom: BorderSide(
                color: t.chromeBorder.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    commit.sha,
                    style: TextStyle(
                      color: selected ? t.textStrong : t.textMuted,
                      fontSize: 8,
                      height: 1.2,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!commit.pushed)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text(
                        '↑',
                        style: TextStyle(
                          color: t.stateAdded.withValues(alpha: 0.9),
                          fontSize: 7.5,
                          height: 1.2,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    commit.time,
                    style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.8),
                      fontSize: 7.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1.5),
              Text(
                commit.msg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? t.textStrong : t.textNormal,
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'you',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 8,
                      height: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (commit.tag != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: t.accentBright.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        commit.tag!,
                        style: TextStyle(
                          color: t.accentBright,
                          fontSize: 7,
                          height: 1,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _MiniImpact(
                    tokens: t,
                    added: commit.added,
                    removed: commit.removed,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `+N / -N` counts plus the five proportional churn segments — a faithful
/// shrink of the real `_CommitImpact`.
class _MiniImpact extends StatelessWidget {
  final AppTokens tokens;
  final int added;
  final int removed;
  const _MiniImpact({
    required this.tokens,
    required this.added,
    required this.removed,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final total = added + removed;
    final greenSegs =
        total == 0 ? 0 : (added / total * 5).round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '+$added',
          style: TextStyle(
            color: t.stateAdded.withValues(alpha: 0.9),
            fontSize: 7.5,
            height: 1.2,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '/',
          style: TextStyle(
            color: t.textMuted.withValues(alpha: 0.3),
            fontSize: 7.5,
            height: 1.2,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          '-$removed',
          style: TextStyle(
            color: t.stateDeleted.withValues(alpha: 0.9),
            fontSize: 7.5,
            height: 1.2,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++)
              Container(
                width: 4.5,
                height: 2.5,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 1),
                decoration: BoxDecoration(
                  color: (i < greenSegs ? t.stateAdded : t.stateDeleted)
                      .withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(0.5),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

enum _MiniStratum { head, live, idle, corpse }

class _MiniBranch {
  final String name;
  final _MiniStratum stratum;
  final int ahead;
  final String? age; // idle rows
  final List<double>? spark; // head/live rows
  const _MiniBranch(
    this.name,
    this.stratum, {
    this.ahead = 0,
    this.age,
    this.spark,
  });
}

/// Miniature of the real Branches page: BRANCHES/PRs lens tabs, then
/// strata — the HEAD card with its tracking line and desk chip, a live
/// branch with a churn sparkline, an idle row with its age, and an
/// absorbed corpse that only wakes up when hovered.
class _BranchesPanel extends StatelessWidget {
  final AppTokens tokens;
  const _BranchesPanel({required this.tokens});

  static const List<_MiniBranch> _branches = [
    _MiniBranch('main', _MiniStratum.head, ahead: 2,
        spark: [2, 4, 1, 6, 3, 5, 2, 7, 3, 8, 5, 9, 4, 6]),
    _MiniBranch('fox/sniff-protocol', _MiniStratum.live, ahead: 2,
        spark: [0, 1, 0, 2, 1, 0, 3, 1, 4, 2, 6, 3, 7, 5]),
    _MiniBranch('amber/in-triplicate', _MiniStratum.idle, age: '12d'),
    _MiniBranch('thorn/gate-rewrite', _MiniStratum.corpse),
  ];

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: t.surface1,
              border: Border(
                bottom: BorderSide(
                  color: t.chromeBorder.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                _MiniLensTab(tokens: t, label: 'BRANCHES', count: '4',
                    active: true),
                const SizedBox(width: 12),
                _MiniLensTab(tokens: t, label: 'PRs', count: '1',
                    active: false),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const PageStorageKey(
                'onboarding.workspacePreview.branchList',
              ),
              padding: const EdgeInsets.all(6),
              children: [
                for (final b in _branches)
                  _MiniBranchCard(tokens: t, branch: b),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLensTab extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final String count;
  final bool active;
  const _MiniLensTab({
    required this.tokens,
    required this.label,
    required this.count,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final color = active ? t.accentBright : t.textNormal;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 8,
                letterSpacing: 1.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              count,
              style: TextStyle(
                color: active
                    ? t.accentBright.withValues(alpha: 0.85)
                    : t.textMuted.withValues(alpha: 0.75),
                fontSize: 7.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          height: 1.5,
          width: active ? 20 : 0,
          color: t.accentBright,
        ),
      ],
    );
  }
}

class _MiniBranchCard extends StatefulWidget {
  final AppTokens tokens;
  final _MiniBranch branch;
  const _MiniBranchCard({required this.tokens, required this.branch});

  @override
  State<_MiniBranchCard> createState() => _MiniBranchCardState();
}

class _MiniBranchCardState extends State<_MiniBranchCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final b = widget.branch;
    final isHead = b.stratum == _MiniStratum.head;
    final isCorpse = b.stratum == _MiniStratum.corpse;
    final vPad = switch (b.stratum) {
      _MiniStratum.head || _MiniStratum.live => 6.0,
      _MiniStratum.idle => 4.0,
      _MiniStratum.corpse => 3.0,
    };
    final nameColor = switch (b.stratum) {
      _MiniStratum.head => t.textStrong,
      _MiniStratum.live => _hover ? t.textStrong : t.textNormal,
      _MiniStratum.idle => t.textMuted,
      _MiniStratum.corpse => t.textFaint,
    };

    final card = AnimatedContainer(
      duration: context.motion(AppMotion.snap),
      margin: const EdgeInsets.only(bottom: 3),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
      decoration: BoxDecoration(
        color: isHead
            ? t.accentBright.withValues(alpha: 0.10)
            : _hover
                ? t.itemHoverBg
                : t.itemHoverBg.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isHead
              ? t.accentBright.withValues(alpha: 0.30)
              : t.accentBright.withValues(alpha: 0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                isHead ? Icons.check : Icons.call_split,
                size: 9,
                color: isHead ? t.accentBright : t.textMuted,
              ),
              const SizedBox(width: 5),
              // Expanded (not Flexible + Spacer): all free space lives
              // here, so every row's trailing data zone shares one flush
              // right edge regardless of name length.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        b.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: isCorpse ? 8.5 : 9.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isHead) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: t.accentBright,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'HEAD',
                          style: TextStyle(
                            color: t.surface0,
                            fontSize: 6.5,
                            height: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (b.ahead > 0)
                Padding(
                  padding: EdgeInsets.only(
                    right: b.spark != null ? 5 : 0,
                  ),
                  child: Text(
                    '↑${b.ahead}',
                    style: TextStyle(
                      color: t.stateAdded,
                      fontSize: 8,
                      height: 1.2,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (b.age != null)
                Text(
                  b.age!,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 8,
                    height: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              if (isCorpse)
                Text(
                  'absorbed',
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 8,
                    height: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              if (b.spark != null)
                _MiniSpark(tokens: t, buckets: b.spark!),
            ],
          ),
          if (isHead) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: t.accentBright.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: t.accentBright.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'desk',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 6.5,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(
                '→ tracking: origin/main',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 7.5,
                  height: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      // Corpses rest at 0.45 and stir to 0.72 on hover — same law as the
      // real strata list.
      child: isCorpse
          ? AnimatedOpacity(
              duration: context.motion(AppMotion.snap),
              opacity: _hover ? 0.72 : 0.45,
              child: card,
            )
          : card,
    );
  }
}

/// 14-bucket churn sparkline over a baseline "silent string".
class _MiniSpark extends StatelessWidget {
  final AppTokens tokens;
  final List<double> buckets;
  const _MiniSpark({required this.tokens, required this.buckets});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 10,
      child: CustomPaint(
        painter: _MiniSparkPainter(
          color: tokens.textNormal.withValues(alpha: 0.5),
          buckets: buckets,
        ),
      ),
    );
  }
}

class _MiniSparkPainter extends CustomPainter {
  final Color color;
  final List<double> buckets;
  _MiniSparkPainter({required this.color, required this.buckets});

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = buckets.fold<double>(1, (m, v) => v > m ? v : m);
    final n = buckets.length;
    const gap = 1.0;
    final barW = ((size.width - gap * (n - 1)) / n).clamp(0.5, 10.0);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      Paint()..color = color.withValues(alpha: color.a * 0.35),
    );
    for (var i = 0; i < n; i++) {
      if (buckets[i] <= 0) continue;
      final h = (buckets[i] / maxV * size.height).clamp(1.5, size.height);
      canvas.drawRect(
        Rect.fromLTWH(
          i * (barW + gap),
          size.height - h,
          barW,
          h,
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniSparkPainter old) =>
      old.color != color || old.buckets != buckets;
}

class _SimpleCaption extends StatelessWidget {
  final AppTokens tokens;
  final String icon;
  final String text;
  const _SimpleCaption({
    required this.tokens,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.bg1,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            name: icon,
            size: 16,
            color: tokens.textFaint.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: tokens.textFaint,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
