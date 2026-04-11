import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../components/icons/app_icons.dart';
import '../features/branches/branches_page.dart';
import '../features/changes/changes_page.dart';
import '../features/history/history_page.dart';
import '../features/search/search_panel.dart';
import '../features/settings/settings_page.dart';
import '../features/sync/sync_panel.dart';
import '../ui/control_chrome.dart';
import '../ui/material_surface.dart';
import '../ui/tokens.dart';
import '../diagnostics/diagnostics_state.dart';
import 'hyper_reactivity.dart';
import 'repository_state.dart';
import 'theme_state.dart';

enum _WorkspaceMode { changes, history, branches }

enum _Panel { none, sync, settings, search }

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
                    child: _MainContent(
                      mode: _mode,
                      selectedCommitHash: _selectedCommitHash,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_panel == _Panel.sync)
            Positioned(
              top: 48,
              right: 12,
              left: size.width < 420 ? 8 : null,
              width: size.width < 420 ? null : 380,
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
                  child: SyncPanel(
                    onClose: () => setState(() => _panel = _Panel.none),
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
        _togglePanel(_Panel.sync);
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
        _togglePanel(_Panel.sync);
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
    final syncSummary = status != null &&
            (status.ahead > 0 || status.behind > 0)
        ? '${status.ahead > 0 ? '${status.ahead}↑' : ''}${status.behind > 0 ? '${status.behind}↓' : ''}'
        : null;

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
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repoName ?? 'No repository open',
                    style: TextStyle(
                      color: repoName != null
                          ? t.textStrong
                          : t.textMuted.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 4),
                    _BranchPill(
                      branch: status.branch,
                      onTap: () => onModeChanged(_WorkspaceMode.branches),
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
              _SyncModeBtn(
                active: panel == _Panel.sync,
                summary: syncSummary,
                onTap: () => onTogglePanel(_Panel.sync),
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

class _SyncModeBtn extends StatelessWidget {
  final bool active;
  final String? summary;
  final VoidCallback onTap;

  const _SyncModeBtn({
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
        _ModeBtn(icon: 'sync', active: active, width: 34, onTap: onTap),
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
                    color:
                        t.accentBright.withValues(alpha: active ? 0.28 : 0.18),
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

class _BranchPill extends StatefulWidget {
  final String branch;
  final VoidCallback onTap;

  const _BranchPill({
    required this.branch,
    required this.onTap,
  });

  @override
  State<_BranchPill> createState() => _BranchPillState();
}

class _BranchPillState extends State<_BranchPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? t.itemHoverBg : t.surface0,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.secondaryBtnBorder),
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
    );
  }
}

class _MainContent extends StatelessWidget {
  final _WorkspaceMode mode;
  final String? selectedCommitHash;

  const _MainContent({required this.mode, this.selectedCommitHash});

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case _WorkspaceMode.changes:
        return const ChangesPage();
      case _WorkspaceMode.history:
        return HistoryPage(initialCommitHash: selectedCommitHash);
      case _WorkspaceMode.branches:
        return const BranchesPage();
    }
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
