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
      _PreviewPanel.xray => _SimpleCaption(tokens: t, text: 'repo x-ray'),
      _PreviewPanel.settings =>
        _SimpleCaption(tokens: t, text: 'settings'),
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
          ),
          child: AppIcon(
            name: widget.icon,
            size: 12,
            color: widget.active ? t.textStrong : t.textMuted,
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


class _HistoryPanel extends StatelessWidget {
  final AppTokens tokens;
  const _HistoryPanel({required this.tokens});

  @override
  Widget build(BuildContext context) {
    const commits = [
      ('a3f19', 'teach fox to sniff before swallowing'),
      ('b71e0', 'amber: hold scent overnight'),
      ('cc8d2', 'retire cabbage in favor of amber + thorn'),
      ('d5e4b', 'thorn guards the gate'),
    ];
    return Container(
      color: tokens.bg1,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (sha, msg) in commits)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tokens.chromeBorder.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    sha,
                    style: TextStyle(
                      color: tokens.accentBright,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      msg,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textNormal,
                        fontSize: 10,
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
}

class _BranchesPanel extends StatelessWidget {
  final AppTokens tokens;
  const _BranchesPanel({required this.tokens});

  @override
  Widget build(BuildContext context) {
    const branches = [
      ('main', true),
      ('fox/sniff-protocol', false),
      ('amber/in-triplicate', false),
      ('thorn/gate-rewrite', false),
    ];
    return Container(
      color: tokens.bg1,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, active) in branches)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 5,
              ),
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? tokens.itemActiveBg
                    : tokens.itemActiveBg.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: active
                      ? tokens.itemActiveBorder
                      : tokens.itemActiveBorder.withValues(alpha: 0),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.call_split,
                    size: 10,
                    color: active ? tokens.accentBright : tokens.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      color: active ? tokens.textStrong : tokens.textMuted,
                      fontSize: 10,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SimpleCaption extends StatelessWidget {
  final AppTokens tokens;
  final String text;
  const _SimpleCaption({required this.tokens, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.bg1,
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: tokens.textFaint,
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
