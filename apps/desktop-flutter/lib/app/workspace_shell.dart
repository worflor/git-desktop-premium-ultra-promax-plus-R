import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../backend/dtos.dart';
import '../backend/git.dart';
import '../components/icons/app_icons.dart';
import '../features/branches/branches_page.dart';
import '../features/changes/changes_page.dart';
import '../features/history/history_page.dart';
import '../features/search/search_panel.dart';
import '../features/settings/settings_page.dart';
import '../features/xray/repo_xray_panel.dart';
import '../ui/control_chrome.dart';
import '../ui/material_surface.dart';
import '../ui/tokens.dart';
import '../diagnostics/diagnostics_state.dart';
import 'hyper_reactivity.dart';
import 'repository_state.dart';
import 'repository_xray_state.dart';
import 'theme_state.dart';
import 'worktree_state.dart';

enum _WorkspaceMode { changes, history, branches }

enum _Panel { none, xray, settings, search }

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({super.key});

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  _WorkspaceMode _mode = _WorkspaceMode.changes;
  _Panel _panel = _Panel.none;
  bool _awaitingGPrefix = false;
  String? _selectedCommitHash;
  Stopwatch? _panelOpenStopwatch;
  String? _lastRepoPathForXray;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'workspace.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final syncMaxHeight = size.height > 64 ? size.height - 64 : size.height;
    final activeRepoPath = context.watch<RepositoryState>().activePath;
    if (_lastRepoPathForXray != activeRepoPath) {
      _lastRepoPathForXray = activeRepoPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.read<RepositoryXrayState>().invalidateAllExcept(activeRepoPath);
      });
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleKey(event),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              _Topbar(
                mode: _mode,
                panel: _panel,
                onModeChanged: (m) => setState(() {
                  _mode = m;
                  _panel = _Panel.none;
                  _awaitingGPrefix = false;
                }),
                onTogglePanel: (p) => setState(() {
                  _panel = _panel == p ? _Panel.none : p;
                  _awaitingGPrefix = false;
                }),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _KeepAlivePages(
                      mode: _mode,
                      selectedCommitHash: _selectedCommitHash,
                      onOpenXray: () => setState(() => _panel = _Panel.xray),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_panel == _Panel.xray)
            Positioned(
              top: 48,
              right: 12,
              left: size.width < 760 ? 8 : null,
              width: size.width < 760 ? null : 680,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: syncMaxHeight,
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * -10),
                      child: Transform.scale(
                        alignment: Alignment.topRight,
                        scale: 0.98 + value * 0.02,
                        child: child,
                      ),
                    ),
                  ),
                  child: RepoXrayPanel(
                    onClose: () => setState(() => _panel = _Panel.none),
                    onCommitSelected: (hash) {
                      setState(() {
                        _selectedCommitHash = hash;
                        _mode = _WorkspaceMode.history;
                        _panel = _Panel.none;
                      });
                    },
                  ),
                ),
              ),
            ),
          if (_panel == _Panel.settings)
            _SlidePanel(
              title: 'Settings',
              onClose: () => setState(() => _panel = _Panel.none),
              child: const SettingsPage(),
            ),
          if (_panel == _Panel.search)
            _SlidePanel(
              onClose: () => setState(() => _panel = _Panel.none),
              child: SearchPanel(
                onClose: () => setState(() => _panel = _Panel.none),
                onCommitSelected: (hash) {
                  setState(() {
                    _selectedCommitHash = hash;
                    _mode = _WorkspaceMode.history;
                    _panel = _Panel.none;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isEditableTargetFocused()) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (_panel != _Panel.none || _awaitingGPrefix) {
        setState(() {
          _panel = _Panel.none;
          _awaitingGPrefix = false;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.slash) {
      setState(() {
        _panel = _panel == _Panel.search ? _Panel.none : _Panel.search;
        _awaitingGPrefix = false;
      });
      return KeyEventResult.handled;
    }

    final profile = context.read<ThemeState>().keybindingProfile;
    if (profile == KeybindingProfile.compact) {
      if (key == LogicalKeyboardKey.digit1) {
        _selectMode(_WorkspaceMode.changes);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2) {
        _selectMode(_WorkspaceMode.history);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit3) {
        _selectMode(_WorkspaceMode.branches);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit4) {
        _togglePanel(_Panel.xray);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit5) {
        _togglePanel(_Panel.settings);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_awaitingGPrefix) {
      setState(() => _awaitingGPrefix = false);
      if (key == LogicalKeyboardKey.keyC) {
        _selectMode(_WorkspaceMode.changes);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyH) {
        _selectMode(_WorkspaceMode.history);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyB) {
        _selectMode(_WorkspaceMode.branches);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        _togglePanel(_Panel.xray);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.comma) {
        _togglePanel(_Panel.settings);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyG) {
        setState(() => _awaitingGPrefix = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.keyG) {
      setState(() => _awaitingGPrefix = true);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isEditableTargetFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText ||
        focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _selectMode(_WorkspaceMode mode) {
    setState(() {
      _mode = mode;
      _panel = _Panel.none;
      _awaitingGPrefix = false;
      _panelOpenStopwatch = null;
    });
  }

  void _togglePanel(_Panel panel) {
    final isOpening = _panel != panel;
    if (isOpening) {
      _panelOpenStopwatch = Stopwatch()..start();
    }
    setState(() {
      _panel = _panel == panel ? _Panel.none : panel;
      _awaitingGPrefix = false;
      if (_panel == _Panel.none) {
        _panelOpenStopwatch = null;
      }
    });
    if (isOpening) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final stopwatch = _panelOpenStopwatch;
        if (!mounted || stopwatch == null || _panel == _Panel.none) {
          return;
        }
        DiagnosticsState.instance.recordUiTiming(
          event: '${_panel.name}.panel.open',
          phase: 'interaction',
          durationMs: stopwatch.elapsedMicroseconds / 1000,
        );
        _panelOpenStopwatch = null;
      });
    }
  }
}

class _Topbar extends StatelessWidget {
  final _WorkspaceMode mode;
  final _Panel panel;
  final ValueChanged<_WorkspaceMode> onModeChanged;
  final ValueChanged<_Panel> onTogglePanel;

  const _Topbar({
    required this.mode,
    required this.panel,
    required this.onModeChanged,
    required this.onTogglePanel,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final topbarTone = t.id == AppThemeId.redshift
        ? AppMaterialTone.surface1
        : AppMaterialTone.surface0;
    final repo = context.watch<RepositoryState>();
    final repoName = repo.activeRepoName;
    final status = repo.status;
    final xrayState = context.watch<RepositoryXrayState>();
    final syncSummary = status != null &&
            (status.ahead > 0 || status.behind > 0)
        ? '${status.ahead > 0 ? '${status.ahead}↑' : ''}${status.behind > 0 ? '${status.behind}↓' : ''}'
        : null;
    final xraySnapshot =
        repo.activePath == null ? null : xrayState.snapshotFor(repo.activePath!);
    final xraySummary =
        xraySnapshot == null ? syncSummary : '${xraySnapshot.cards.length}';

    return MaterialSurface(
      tone: topbarTone,
      radius: 0,
      border: Border(
        bottom: BorderSide(
          color: t.chromeBorder.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(2, 8, 12, 8),
      // crossAxisAlignment.start keeps the mode buttons top-aligned even
      // when the left column expands to two rows (repo + branch/desks row).
      // Without this, the default center alignment drifts the buttons
      // vertically as the left column grows.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RepoNameLabel(
                    name: repoName ?? 'No repository open',
                    hasRepo: repoName != null,
                    repoPath: repo.activePath,
                    onRefresh: () => repo.refreshStatus(),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 4),
                    // Desk row: active branch pill + other open worktrees.
                    _DeskRow(
                      activeBranch: status.branch,
                      activeRepoPath: repo.activePath,
                      onNavigateBranches: () =>
                          onModeChanged(_WorkspaceMode.branches),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeBtn(
                icon: 'changes',
                active: mode == _WorkspaceMode.changes,
                onTap: () => onModeChanged(_WorkspaceMode.changes),
              ),
              _ModeBtn(
                icon: 'history',
                active: mode == _WorkspaceMode.history,
                onTap: () => onModeChanged(_WorkspaceMode.history),
              ),
              _ModeBtn(
                icon: 'branches',
                active: mode == _WorkspaceMode.branches,
                onTap: () => onModeChanged(_WorkspaceMode.branches),
              ),
              const SizedBox(width: 4),
              _XrayModeBtn(
                active: panel == _Panel.xray,
                summary: xraySummary,
                onTap: () => onTogglePanel(_Panel.xray),
              ),
              const SizedBox(width: 8),
              _ModeBtn(
                icon: 'settings',
                active: panel == _Panel.settings,
                onTap: () => onTogglePanel(_Panel.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeBtn extends StatefulWidget {
  final String icon;
  final bool active;
  final double width;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.icon,
    required this.active,
    this.width = 30,
    required this.onTap,
  });

  @override
  State<_ModeBtn> createState() => _ModeBtnState();
}

class _ModeBtnState extends State<_ModeBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = modeButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      active: widget.active,
    );
    final iconColor = widget.active
        ? t.accentBright
        : (_hovered ? t.textNormal : t.textMuted);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: HyperReactive(
          selected: widget.active,
          borderRadius: 6,
          child: AnimatedScale(
            scale: chrome.scale,
            duration:
                Duration(milliseconds: t.id == AppThemeId.aether ? 400 : 80),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration:
                  Duration(milliseconds: t.id == AppThemeId.aether ? 400 : 80),
              curve: Curves.easeOut,
              width: widget.width,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: chrome.background,
                gradient: chrome.gradient,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: chrome.borderColor, width: 1),
                boxShadow: chrome.shadows,
              ),
              child: Transform.translate(
                offset: chrome.offset,
                child: Center(
                  child: AppIcon(name: widget.icon, size: 16, color: iconColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoNameLabel extends StatefulWidget {
  final String name;
  final bool hasRepo;
  final String? repoPath;
  final VoidCallback onRefresh;

  const _RepoNameLabel({
    required this.name,
    required this.hasRepo,
    this.repoPath,
    required this.onRefresh,
  });

  @override
  State<_RepoNameLabel> createState() => _RepoNameLabelState();
}

class _RepoNameLabelState extends State<_RepoNameLabel> {
  bool _hovered = false;
  bool _fetching = false;

  Future<void> _fetch() async {
    if (_fetching || widget.repoPath == null) return;
    setState(() => _fetching = true);
    try {
      await fetchRemote(widget.repoPath!, prune: true);
      widget.onRefresh();
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final baseColor = widget.hasRepo
        ? t.textStrong
        : t.textMuted.withValues(alpha: 0.5);
    final color = widget.hasRepo && _hovered ? t.accentBright : baseColor;

    return MouseRegion(
      cursor: widget.hasRepo ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.hasRepo ? _fetch : null,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 100),
          style: TextStyle(
            color: _fetching ? t.accentBright.withValues(alpha: 0.6) : color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          child: Text(
            widget.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _XrayModeBtn extends StatelessWidget {
  final bool active;
  final String? summary;
  final VoidCallback onTap;

  const _XrayModeBtn({
    required this.active,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _ModeBtn(icon: 'search', active: active, width: 34, onTap: onTap),
        if (summary != null)
          Positioned(
            left: 39,
            child: IgnorePointer(
              child: Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: t.accentBright.withValues(alpha: active ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: t.accentBright.withValues(alpha: active ? 0.28 : 0.18),
                  ),
                ),
                child: Center(
                  child: Text(
                    summary!,
                    style: TextStyle(
                      color: t.accentBright,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Desk row: active branch pill + other open worktrees ─────────────────────

/// The desk row lives in the second line of the topbar. The first position
/// is the active desk (rendered as `_BranchPill` — keeps the dropdown
/// affordance). Subsequent positions are other open worktrees as smaller
/// tabs. Single-desk state looks identical to pre-worktree chrome.
class _DeskRow extends StatelessWidget {
  final String activeBranch;
  final String? activeRepoPath;
  final VoidCallback onNavigateBranches;

  const _DeskRow({
    required this.activeBranch,
    required this.activeRepoPath,
    required this.onNavigateBranches,
  });

  @override
  Widget build(BuildContext context) {
    final worktreeState = context.watch<WorktreeState>();
    final repoState = context.watch<RepositoryState>();
    final activeNormalized =
        activeRepoPath?.replaceAll('\\', '/').toLowerCase();
    // Other desks = every known worktree except the one currently active.
    final otherDesks = worktreeState.desks.where((d) {
      return d.path.replaceAll('\\', '/').toLowerCase() != activeNormalized;
    }).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BranchPill(
          branch: activeBranch,
          repoPath: activeRepoPath,
          onNavigate: onNavigateBranches,
        ),
        for (final desk in otherDesks) ...[
          const SizedBox(width: 6),
          _DeskTab(
            desk: desk,
            onTap: () {
              if (desk.path != repoState.activePath) {
                repoState.setActivePath(desk.path, addToRecents: false);
              }
            },
            onClose: desk.isMain
                ? null
                : () => _closeDeskFlow(context, desk, worktreeState),
          ),
        ],
      ],
    );
  }

  Future<void> _closeDeskFlow(
    BuildContext context,
    WorktreeData desk,
    WorktreeState worktreeState,
  ) async {
    if (desk.dirtyFileCount == 0) {
      // Clean desk → silent close.
      await worktreeState.closeDesk(desk.path);
      return;
    }
    // Dirty desk → confirm with shelve option.
    final choice = await showDialog<_CloseDeskChoice>(
      context: context,
      builder: (ctx) => _CloseDeskDialog(desk: desk),
    );
    if (choice == null || choice == _CloseDeskChoice.cancel) return;
    await worktreeState.closeDesk(
      desk.path,
      shelveFirst: choice == _CloseDeskChoice.shelve,
      force: choice == _CloseDeskChoice.discard,
    );
  }
}

class _DeskTab extends StatefulWidget {
  final WorktreeData desk;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _DeskTab({
    required this.desk,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_DeskTab> createState() => _DeskTabState();
}

class _DeskTabState extends State<_DeskTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = widget.desk;
    final label = d.branch ?? (d.isDetached ? d.head.substring(0, 7) : 'desk');
    final canClose = widget.onClose != null;
    final showCloseOverDot = canClose && _hovered;
    final dotColor = d.dirtyFileCount > 0
        ? t.accentBright.withValues(alpha: 0.85)
        : t.chromeBorder.withValues(alpha: 0.5);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? t.secondaryBtnHoverBg
                : t.bg0.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: t.chromeBorder.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Indicator position: dot by default, × overlay on hover.
              // Same footprint so the tab never reflows.
              SizedBox(
                width: 12,
                height: 12,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: showCloseOverDot ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor,
                        ),
                      ),
                    ),
                    if (canClose)
                      AnimatedOpacity(
                        opacity: showCloseOverDot ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 100),
                        child: GestureDetector(
                          onTap: widget.onClose,
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            '×',
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CloseDeskChoice { shelve, discard, cancel }

class _CloseDeskDialog extends StatelessWidget {
  final WorktreeData desk;
  const _CloseDeskDialog({required this.desk});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface1,
      title: Text(
        'Close desk?',
        style: TextStyle(color: t.textStrong, fontSize: 14),
      ),
      content: Text(
        'This desk has ${desk.dirtyFileCount} uncommitted file${desk.dirtyFileCount == 1 ? '' : 's'}. '
        'Shelve them so you can pick them back up later, or close anyway and discard the changes?',
        style: TextStyle(color: t.textNormal, fontSize: 12),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_CloseDeskChoice.cancel),
          child: Text('Cancel', style: TextStyle(color: t.textMuted)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_CloseDeskChoice.discard),
          child: Text('Discard & close',
              style: TextStyle(color: t.stateDeleted)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_CloseDeskChoice.shelve),
          child: Text('Shelve & close',
              style: TextStyle(color: t.accentBright)),
        ),
      ],
    );
  }
}

// ── Branch pill + emerging panel ─────────────────────────────────────────────

class _BranchPill extends StatefulWidget {
  final String branch;
  final String? repoPath;
  final VoidCallback onNavigate;

  const _BranchPill({
    required this.branch,
    required this.repoPath,
    required this.onNavigate,
  });

  @override
  State<_BranchPill> createState() => _BranchPillState();
}

class _BranchPillState extends State<_BranchPill> {
  bool _hovered = false;
  bool _open = false;
  bool _loading = false;
  bool _switching = false;
  List<BranchInfo> _branches = const [];
  OverlayEntry? _overlay;
  final _pillKey = GlobalKey();

  static const _openRadius = 7.0;

  Future<void> _toggle() async {
    if (_open) {
      _close();
      return;
    }
    if (widget.repoPath == null) {
      widget.onNavigate();
      return;
    }
    setState(() {
      _open = true;
      _loading = true;
      _branches = const [];
    });
    _insertOverlay();

    final result = await listBranches(widget.repoPath!);
    if (!mounted) return;
    setState(() {
      _branches = result.data ?? [];
      _loading = false;
    });
    _overlay?.markNeedsBuild();
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() => _open = false);
  }

  void _insertOverlay() {
    final box = _pillKey.currentContext!.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final pillSize = box.size;
    // Snapshot the worktree state at overlay-open time so the "+ desk" /
    // "→ open" affordances know which branches are already open elsewhere.
    final worktreeState = context.read<WorktreeState>();
    final repoState = context.read<RepositoryState>();
    final branchesOpenAsDesks = worktreeState.desks
        .where((d) => d.branch != null)
        .map((d) => d.branch!)
        .toSet();

    _overlay = OverlayEntry(builder: (_) {
      return _BranchPanelOverlay(
        // Panel starts at pill's top — pill fades out, panel morphs in
        top: origin.dy,
        left: origin.dx,
        pillHeight: pillSize.height,
        minWidth: 240.0,
        branches: _branches,
        loading: _loading,
        switching: _switching,
        currentBranch: widget.branch,
        onDismiss: _close,
        onCheckout: _checkout,
        onOpenAsDesk: (branchName) async {
          // If this branch already has a desk, jump to it. Otherwise
          // create a new worktree for it and switch to it.
          final existing = worktreeState.desks.firstWhere(
            (d) => d.branch == branchName,
            orElse: () => const WorktreeData(
              path: '', head: '', isMain: false,
              isDetached: false, isLocked: false,
            ),
          );
          _close();
          if (existing.path.isNotEmpty) {
            await repoState.setActivePath(existing.path, addToRecents: false);
          } else {
            await worktreeState.addDesk(branchName);
          }
        },
        onCreateDeskFromHead: (newBranchName) async {
          _close();
          await worktreeState.addDesk(
            newBranchName,
            createNewBranch: true,
          );
        },
        branchesOpenAsDesks: branchesOpenAsDesks,
        onNavigate: () {
          _close();
          widget.onNavigate();
        },
      );
    });

    Overlay.of(context).insert(_overlay!);
  }

  Future<void> _checkout(String name) async {
    if (widget.repoPath == null) return;
    setState(() => _switching = true);
    _overlay?.markNeedsBuild();
    await checkoutBranch(widget.repoPath!, name);
    if (!mounted) return;
    _close();
  }

  @override
  void dispose() {
    _overlay?.remove();
    _overlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final borderColor = _open
        ? t.inputFocusBorder.withValues(alpha: 0.45)
        : t.secondaryBtnBorder;

    // Fade out when open — panel takes over, morphing from this exact position
    return AnimatedOpacity(
      opacity: _open ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            key: _pillKey,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _hovered ? t.itemHoverBg : t.surface0,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(name: 'git-branch', size: 11, color: t.accentBright),
                const SizedBox(width: 5),
                Text(
                  widget.branch,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                AppIcon(name: 'chevron-right', size: 10, color: t.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Panel overlay ─────────────────────────────────────────────────────────────

class _BranchPanelOverlay extends StatefulWidget {
  final double top;
  final double left;
  final double pillHeight;
  final double minWidth;
  final List<BranchInfo> branches;
  final bool loading;
  final bool switching;
  final String currentBranch;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCheckout;
  final ValueChanged<String>? onOpenAsDesk;
  final ValueChanged<String>? onCreateDeskFromHead;
  final Set<String> branchesOpenAsDesks;
  final VoidCallback onNavigate;

  const _BranchPanelOverlay({
    required this.top,
    required this.left,
    required this.pillHeight,
    required this.minWidth,
    required this.branches,
    required this.loading,
    required this.switching,
    required this.currentBranch,
    required this.onDismiss,
    required this.onCheckout,
    this.onOpenAsDesk,
    this.onCreateDeskFromHead,
    this.branchesOpenAsDesks = const {},
    required this.onNavigate,
  });

  @override
  State<_BranchPanelOverlay> createState() => _BranchPanelOverlayState();
}

class _BranchPanelOverlayState extends State<_BranchPanelOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _reveal;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _reveal = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final borderColor = t.inputFocusBorder.withValues(alpha: 0.45);

    return Stack(
      children: [
        // Dismiss tap-catcher
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        // Panel
        Positioned(
          top: widget.top,
          left: widget.left,
          child: FadeTransition(
            opacity: _fade,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _reveal,
                builder: (_, child) => Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _reveal.value,
                  child: child,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: widget.minWidth,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(t.inputBg, t.bg0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                      // offset.dy > blurRadius → shadow only goes downward
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: t.isDark ? 0.45 : 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Pill header — tapping here closes the panel ──
                        GestureDetector(
                          onTap: widget.onDismiss,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: SizedBox(
                              height: widget.pillHeight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppIcon(
                                        name: 'git-branch',
                                        size: 11,
                                        color: t.accentBright),
                                    const SizedBox(width: 5),
                                    Text(
                                      widget.currentBranch,
                                      style: TextStyle(
                                        color: t.textNormal,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Chevron pointing down (open state)
                                    Transform.rotate(
                                      angle: math.pi / 2,
                                      child: AppIcon(
                                          name: 'chevron-right',
                                          size: 10,
                                          color: t.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Divider between pill header and branch list
                        Container(
                          height: 1,
                          color: borderColor.withValues(alpha: 0.5),
                        ),
                        // ── Branch list ──────────────────────────────────
                        _PanelBody(
                          branches: widget.branches,
                          loading: widget.loading,
                          switching: widget.switching,
                          currentBranch: widget.currentBranch,
                          onCheckout: widget.onCheckout,
                          onOpenAsDesk: widget.onOpenAsDesk,
                          onCreateDeskFromHead: widget.onCreateDeskFromHead,
                          branchesOpenAsDesks: widget.branchesOpenAsDesks,
                          onNavigate: widget.onNavigate,
                          t: t,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelBody extends StatelessWidget {
  final List<BranchInfo> branches;
  final bool loading;
  final bool switching;
  final String currentBranch;
  final ValueChanged<String> onCheckout;
  final ValueChanged<String>? onOpenAsDesk;
  final Set<String> branchesOpenAsDesks;
  /// Create a new branch from HEAD and open it on a new desk, in one motion.
  final ValueChanged<String>? onCreateDeskFromHead;
  final VoidCallback onNavigate;
  final AppTokens t;

  const _PanelBody({
    required this.branches,
    required this.loading,
    required this.switching,
    required this.currentBranch,
    required this.onCheckout,
    this.onOpenAsDesk,
    this.branchesOpenAsDesks = const {},
    this.onCreateDeskFromHead,
    required this.onNavigate,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: t.accentBright.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final sorted = [...branches]..sort((a, b) {
        if (a.current) return -1;
        if (b.current) return 1;
        return a.name.compareTo(b.name);
      });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        for (final branch in sorted)
          _BranchRow(
            branch: branch,
            isCurrent: branch.current,
            switching: switching,
            t: t,
            onTap: branch.current
                ? null
                : () => onCheckout(branch.name),
            onOpenAsDesk: onOpenAsDesk == null
                ? null
                : () => onOpenAsDesk!(branch.name),
            alreadyOpenAsDesk: branchesOpenAsDesks.contains(branch.name),
          ),
        const SizedBox(height: 4),
        Container(
          height: 1,
          color: t.chromeBorder.withValues(alpha: 0.12),
          margin: const EdgeInsets.symmetric(horizontal: 8),
        ),
        if (onCreateDeskFromHead != null)
          _NewDeskRow(t: t, onSubmit: onCreateDeskFromHead!),
        _NavRow(t: t, onTap: onNavigate),
      ],
    );
  }
}

class _BranchRow extends StatefulWidget {
  final BranchInfo branch;
  final bool isCurrent;
  final bool switching;
  final AppTokens t;
  final VoidCallback? onTap;
  /// When non-null, shows a hover-reveal "open on new desk" affordance.
  /// If the branch already has a worktree, this instead jumps to that desk.
  final VoidCallback? onOpenAsDesk;
  /// True when this branch is already open as a separate desk — the desk
  /// action then "jumps" instead of creating a new one.
  final bool alreadyOpenAsDesk;

  const _BranchRow({
    required this.branch,
    required this.isCurrent,
    required this.switching,
    required this.t,
    required this.onTap,
    this.onOpenAsDesk,
    this.alreadyOpenAsDesk = false,
  });

  @override
  State<_BranchRow> createState() => _BranchRowState();
}

class _BranchRowState extends State<_BranchRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final b = widget.branch;
    final canSwitch = widget.onTap != null && !widget.switching;

    return MouseRegion(
      cursor:
          canSwitch ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: canSwitch ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: _hovered && canSwitch
              ? t.secondaryBtnHoverBg
              : Colors.transparent,
          child: Row(
            children: [
              // Current indicator dot
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isCurrent
                      ? t.accentBright
                      : t.chromeBorder.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 8),
              // Branch name
              Expanded(
                child: Text(
                  b.name,
                  style: TextStyle(
                    color: widget.isCurrent ? t.textStrong : t.textNormal,
                    fontSize: 11,
                    fontWeight: widget.isCurrent
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Upstream tracking
              if (b.upstream != null && (b.ahead > 0 || b.behind > 0)) ...[
                const SizedBox(width: 6),
                if (b.ahead > 0)
                  Text(
                    '↑${b.ahead}',
                    style: TextStyle(
                      color: t.accentBright.withValues(alpha: 0.75),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (b.ahead > 0 && b.behind > 0)
                  const SizedBox(width: 3),
                if (b.behind > 0)
                  Text(
                    '↓${b.behind}',
                    style: TextStyle(
                      color: t.stateModified.withValues(alpha: 0.80),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
              // Trailing desk affordances — only for non-current branches.
              // The current branch is already where you are; there's no
              // "jump to" or "open on new desk" meaning for it.
              if (widget.onOpenAsDesk != null && !widget.isCurrent) ...[
                const SizedBox(width: 6),
                if (widget.alreadyOpenAsDesk)
                  Tooltip(
                    message: 'Jump to desk',
                    child: GestureDetector(
                      onTap: widget.onOpenAsDesk,
                      child: Text(
                        '→ open',
                        style: TextStyle(
                          color: t.accentBright.withValues(alpha: 0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else if (_hovered)
                  Tooltip(
                    message: 'Open on a new desk',
                    child: GestureDetector(
                      onTap: widget.onOpenAsDesk,
                      child: Text(
                        '+ desk',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline "+ new desk from HEAD..." row. Collapsed to a button by default;
/// expands into a text field where you name a new branch. Enter creates
/// the branch AND opens it on a new desk in one motion.
class _NewDeskRow extends StatefulWidget {
  final AppTokens t;
  final ValueChanged<String> onSubmit;
  const _NewDeskRow({required this.t, required this.onSubmit});

  @override
  State<_NewDeskRow> createState() => _NewDeskRowState();
}

class _NewDeskRowState extends State<_NewDeskRow> {
  bool _hovered = false;
  bool _expanded = false;
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    widget.onSubmit(name);
    _ctrl.clear();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Text('+ ', style: TextStyle(color: t.accentBright, fontSize: 12)),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: 'new-branch-name',
                  hintStyle: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _expanded = false;
                _ctrl.clear();
              }),
              child: Text('esc',
                  style: TextStyle(color: t.textMuted, fontSize: 9)),
            ),
          ],
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          setState(() => _expanded = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusNode.requestFocus();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: _hovered ? t.secondaryBtnHoverBg : Colors.transparent,
          child: Row(
            children: [
              Text(
                '+ New desk',
                style: TextStyle(
                  color: _hovered ? t.textNormal : t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'from HEAD...',
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatefulWidget {
  final AppTokens t;
  final VoidCallback onTap;

  const _NavRow({required this.t, required this.onTap});

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? t.secondaryBtnHoverBg : Colors.transparent,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Row(
            children: [
              Text(
                'View all branches',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(width: 4),
              AppIcon(name: 'chevron-right', size: 9, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps all three pages alive so that in-progress work (like a running
/// review) survives page switches. Uses an [IndexedStack] underneath
/// with [TickerMode] to pause off-screen pages' tickers/animations.
class _KeepAlivePages extends StatelessWidget {
  final _WorkspaceMode mode;
  final String? selectedCommitHash;
  final VoidCallback onOpenXray;

  const _KeepAlivePages({
    required this.mode,
    this.selectedCommitHash,
    required this.onOpenXray,
  });

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ChangesPage(),
      HistoryPage(
        initialCommitHash: selectedCommitHash,
        onOpenXray: onOpenXray,
      ),
      const BranchesPage(),
    ];
    return IndexedStack(
      index: mode.index,
      children: [
        for (var i = 0; i < pages.length; i++)
          TickerMode(enabled: i == mode.index, child: pages[i]),
      ],
    );
  }
}

class _SlidePanel extends StatelessWidget {
  final String? title;
  final VoidCallback onClose;
  final Widget child;

  const _SlidePanel({
    this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final panelTone = t.id == AppThemeId.redshift
        ? AppMaterialTone.surface2
        : AppMaterialTone.surface1;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.4)),
          ),
        ),
        Positioned(
          top: 48,
          left: 8,
          right: 8,
          bottom: 8,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 40),
                child: child,
              ),
            ),
            child: MaterialSurface(
              tone: panelTone,
              radius: 12,
              borderAlpha: 0.30,
              elevated: true,
              child: title == null
                  ? child
                  : Column(
                      children: [
                        _SlideHeader(title: title!, onClose: onClose),
                        Expanded(child: child),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlideHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _SlideHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: t.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.96,
            ),
          ),
          const Spacer(),
          _PanelCloseButton(onClose: onClose),
        ],
      ),
    );
  }
}

class _PanelCloseButton extends StatefulWidget {
  final VoidCallback onClose;

  const _PanelCloseButton({required this.onClose});

  @override
  State<_PanelCloseButton> createState() => _PanelCloseButtonState();
}

class _PanelCloseButtonState extends State<_PanelCloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = ghostButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      enabled: true,
      baseBorderColor: t.secondaryBtnBorder,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onClose,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: HyperReactive(
          borderRadius: 6,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 80),
            scale: chrome.scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: chrome.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: chrome.borderColor,
                ),
                boxShadow: chrome.shadows,
              ),
              child: Transform.translate(
                offset: chrome.offset,
                child: Text(
                  'Close',
                  style: TextStyle(color: t.textNormal, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
