import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../backend/dtos.dart';
import '../backend/git.dart';
import '../backend/logos_dream.dart';
import '../backend/logos_free_energy.dart';
import '../backend/logos_git.dart' show LogosGit;
import '../backend/logos_spectrogeometry.dart' show UniversalityVector;
import '../components/icons/app_icons.dart';
import '../features/branches/branches_page.dart';
import '../features/changes/changes_page.dart';
import '../features/history/history_page.dart';
import '../features/search/search_panel.dart';
import '../features/settings/settings_page.dart';
import 'settings_navigation_state.dart';
import '../features/xray/repo_xray_panel.dart';
import '../ui/animated_icons.dart';
import '../ui/control_chrome.dart';
import '../ui/design_primitives.dart';
import '../ui/dream_hint.dart';
import '../ui/form_controls.dart';
import '../ui/hyperhealth_text.dart';
import '../ui/interaction_feedback.dart';
import '../ui/material_surface.dart';
import '../ui/context_menu.dart';
import '../ui/morph_text.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import '../diagnostics/diagnostics_state.dart';
import '../backend/desk_issue.dart';
import '../backend/remote_issue_provider.dart' show IssueSummary;
import 'desk_drop_payload.dart';
import 'desk_issue_state.dart';
import 'desk_pr_state.dart';
import 'file_coupling_state.dart';
import 'preferences_state.dart';
import 'window_activity.dart';
import 'remote_issue_cache_state.dart';
import 'hyper_reactivity.dart';
import 'logos_git_state.dart';
import 'repository_state.dart';
import 'repository_xray_state.dart';
import 'symbol_frequency_state.dart';
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
  // Deep-link target for the settings page. Consumed once when the
  // settings panel renders; cleared after a single use so subsequent
  // panel toggles don't re-focus.
  SettingsSection? _pendingSettingsFocus;
  SettingsNavigationState? _settingsNavState;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navState = context.read<SettingsNavigationState>();
    if (!identical(_settingsNavState, navState)) {
      _settingsNavState?.removeListener(_onSettingsNavChanged);
      _settingsNavState = navState;
      navState.addListener(_onSettingsNavChanged);
    }
  }

  /// Handle a deep-link request from elsewhere in the app (e.g., the
  /// project context menu's "Open with…" zero-state). Open the
  /// settings panel and stash the focus section for the SettingsPage
  /// to consume on render.
  void _onSettingsNavChanged() {
    final section = _settingsNavState?.consume();
    if (section == null) return;
    if (!mounted) return;
    setState(() {
      _pendingSettingsFocus = section;
      _panel = _Panel.settings;
    });
  }

  /// Single chokepoint for panel transitions. Clearing
  /// [_pendingSettingsFocus] on every "leaves settings" path used to
  /// be wired only into the close button — Esc, the backdrop tap,
  /// mode-switch shortcuts, and topbar panel toggles all bypassed it
  /// and left a stale deep-link token to fire on the next reopen.
  /// Funnel every panel write through here so the cleanup happens
  /// uniformly.
  void _setPanel(_Panel next) {
    setState(() {
      if (_panel == _Panel.settings && next != _Panel.settings) {
        _pendingSettingsFocus = null;
      }
      _panel = next;
    });
  }

  @override
  void dispose() {
    _settingsNavState?.removeListener(_onSettingsNavChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final t = context.tokens;
    final syncMaxHeight = size.height > 64 ? size.height - 64 : size.height;
    final activeRepoPath = context.select<RepositoryState, String?>(
      (s) => s.activePath,
    );
    if (_lastRepoPathForXray != activeRepoPath) {
      _lastRepoPathForXray = activeRepoPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        context.read<RepositoryXrayState>().invalidateAllExcept(activeRepoPath);
        // LogosGitState and FileCouplingState keep their LRU caches
        // across repo switches — the resolver manages its own budget.
        // Only xray and symbol frequency evict aggressively (larger
        // footprint, less value when cached across repos).
        context
            .read<SymbolFrequencyState>()
            .invalidateAllExcept(activeRepoPath);
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
                onModeChanged: (m) {
                  _setPanel(_Panel.none);
                  setState(() {
                    _mode = m;
                    _awaitingGPrefix = false;
                  });
                },
                onTogglePanel: (p) {
                  _setPanel(_panel == p ? _Panel.none : p);
                  setState(() => _awaitingGPrefix = false);
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _KeepAlivePages(
                      mode: _mode,
                      selectedCommitHash: _selectedCommitHash,
                      onOpenXray: () => _setPanel(_Panel.xray),
                      onOpenChanges: () => _selectMode(_WorkspaceMode.changes),
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
                  duration: context.surfaceShader.duration,
                  // safeCurve — value feeds Opacity which asserts [0, 1].
                  curve: context.surfaceShader.safeCurve,
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
                    onClose: () => _setPanel(_Panel.none),
                    onCommitSelected: (hash) {
                      _setPanel(_Panel.none);
                      setState(() {
                        _selectedCommitHash = hash;
                        _mode = _WorkspaceMode.history;
                      });
                    },
                  ),
                ),
              ),
            ),
          // Settings/search panel overlay. Backdrop and panel animate
          // INDEPENDENTLY:
          //   - Backdrop fades only (stays full-screen, doesn't slide)
          //   - Panel fades + slides
          // Merging them would slide the backdrop with the panel, leaving
          // the top of the screen un-dimmed during the close-slide for a
          // frame.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _panel != _Panel.settings && _panel != _Panel.search,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: context.surfaceShader.duration,
                      curve: context.surfaceShader.safeCurve,
                      opacity:
                          (_panel == _Panel.settings || _panel == _Panel.search)
                              ? 1.0
                              : 0.0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setPanel(_Panel.none),
                        // Black scrim sized by theme darkness. Pure
                        // `t.bg0 @ 0.72` washes light themes (kirby,
                        // petrichor, halo, nacre, barbie) toward gray
                        // because cream-over-cream lerps to muddy tan;
                        // a thin black dim on light themes preserves
                        // the surface vibrance while still signalling
                        // the workspace is gated behind a panel.
                        child: Container(
                          color: Colors.black.withValues(
                            alpha: t.isDark ? 0.4 : 0.18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: context.surfaceShader.duration,
                      reverseDuration: context.surfaceShader.duration,
                      switchInCurve: context.surfaceShader.safeCurve,
                      switchOutCurve: context.surfaceShader.safeCurve,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: switch (_panel) {
                        _Panel.settings => _SlidePanel(
                            key: const ValueKey('settings'),
                            title: 'Settings',
                            // _setPanel handles the focus-token clear
                            // because it knows we're transitioning out
                            // of _Panel.settings.
                            onClose: () => _setPanel(_Panel.none),
                            child: SettingsPage(focusSection: _pendingSettingsFocus),
                          ),
                        _Panel.search => _SlidePanel(
                            key: const ValueKey('search'),
                            onClose: () => _setPanel(_Panel.none),
                            child: SearchPanel(
                              onClose: () => _setPanel(_Panel.none),
                              onCommitSelected: (hash) {
                                _setPanel(_Panel.none);
                                setState(() {
                                  _selectedCommitHash = hash;
                                  _mode = _WorkspaceMode.history;
                                });
                              },
                            ),
                          ),
                        _ => const SizedBox.shrink(key: ValueKey('none')),
                      },
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
        _setPanel(_Panel.none);
        setState(() {
          _awaitingGPrefix = false;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.slash) {
      _setPanel(_panel == _Panel.search ? _Panel.none : _Panel.search);
      setState(() {
        _awaitingGPrefix = false;
      });
      return KeyEventResult.handled;
    }

    // `?` (shift + slash) → global keyboard cheatsheet. Covers the
    // workspace-level bindings (page switch, panels, search, g-prefix
    // chords) so the shortcuts are discoverable without reading code.
    // Page-local bindings (j/k nav on the branches lens, etc.) still
    // live in that page's own overlay when relevant.
    if (key == LogicalKeyboardKey.question ||
        (key == LogicalKeyboardKey.slash &&
            HardwareKeyboard.instance.isShiftPressed)) {
      _showGlobalKeyboardCheatsheet();
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

  void _showGlobalKeyboardCheatsheet() {
    final profile = context.read<ThemeState>().keybindingProfile;
    final isCompact = profile == KeybindingProfile.compact;
    final rows = <(String, String)>[
      if (isCompact) ...[
        ('1', 'Changes'),
        ('2', 'History'),
        ('3', 'Branches'),
        ('4', 'Xray panel'),
        ('5', 'Settings panel'),
      ] else ...[
        ('g c', 'Changes'),
        ('g h', 'History'),
        ('g b', 'Branches'),
        ('g s', 'Xray panel'),
        ('g ,', 'Settings panel'),
        ('g g', 'Re-arm g-prefix (second g)'),
      ],
      ('/', 'Search panel'),
      ('esc', 'Close panel / overlay'),
      ('?', 'This cheatsheet'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          title: Text('Keyboard',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 13,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              )),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            r.$1,
                            style: TextStyle(
                              color: t.accentBright,
                              fontSize: 11,
                              fontFamily: AppFonts.mono,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.$2,
                            style: TextStyle(color: t.textNormal, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  isCompact
                      ? 'Using compact profile · switch in Settings'
                      : 'Using classic profile · switch in Settings',
                  style: TextStyle(color: t.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Close', style: TextStyle(color: t.textMuted)),
            ),
          ],
        );
      },
    );
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
    _setPanel(_Panel.none);
    setState(() {
      _mode = mode;
      _awaitingGPrefix = false;
      _panelOpenStopwatch = null;
    });
  }

  void _togglePanel(_Panel panel) {
    final isOpening = _panel != panel;
    if (isOpening) {
      _panelOpenStopwatch = Stopwatch()..start();
    }
    // Route through _setPanel so leaving the settings panel via a
    // keyboard shortcut clears _pendingSettingsFocus too. Without
    // this, deep-link tokens (set when "Open with…" zero-state
    // jumps into Settings) survived a `5` / `g,` close and re-fired
    // the focus animation on the next settings open.
    _setPanel(_panel == panel ? _Panel.none : panel);
    setState(() {
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
    final topbarTone = t.chromeTone;
    // Narrow subscription: only rebuild when activePath or status
    // change, not on every unrelated RepositoryState mutation. The
    // topbar reads activeRepoName (derived from path) + status, no
    // other state. The prior `context.watch` rebuilt this tree on
    // every status tick across 30-50 widgets for no useful reason.
    final repoPath = context
        .select<RepositoryState, String?>((s) => s.activePath);
    final status = context
        .select<RepositoryState, RepositoryStatus?>((s) => s.status);
    final repo = context.read<RepositoryState>();
    final repoName = repo.activeRepoName;
    // Free-energy anomaly read — the repo name gets a sheen swoosh
    // whose strength scales with this continuous 0..1 signal. Colour
    // of the title stays whatever it was; only the sheen carries the
    // health indication.
    //
    // Select only the engine for the active repo, not the whole
    // LogosGitState. Other repos' engine updates shouldn't churn the
    // topbar.
    final engine = repoPath == null
        ? null
        : context.select<LogosGitState, LogosGit?>(
            (s) => s.engineFor(repoPath),
          );
    final anomaly =
        engine == null ? 0.0 : (repoAnomalyLevel(engine) ?? 0.0);
    // Pull the repo's universality classification for the sheen. The
    // engine caches the report by `manifoldRevision`, so this is a
    // cheap map lookup on every build; no recomputation.
    final universality = engine?.spectrogeometry()?.universality;

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
                    onRefresh: () => repo.userRefresh(),
                    anomaly: anomaly,
                    universality: universality,
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

  // Mode-button icons opt into animation one at a time. Icons that have a
  // hand-painted `Animated<Name>Icon` are dispatched here; everything else
  // (e.g. 'changes', and any future icon added to the top bar) falls through
  // to a static `AppIcon` — deliberate graceful fallback, not a missing
  // case. Adding animation is a per-icon effort, not an automatic upgrade.
  Widget _buildIcon(Color color) {
    final state = _hovered ? IconAnimState.hovered : IconAnimState.idle;
    return switch (widget.icon) {
      'history' => AnimatedHistoryIcon(state: state, color: color, size: 16),
      'branches' => AnimatedBranchesIcon(state: state, color: color, size: 16),
      'xray' => AnimatedXrayIcon(state: state, color: color, size: 16),
      'settings' => AnimatedSettingsIcon(state: state, color: color, size: 16),
      _ => AppIcon(name: widget.icon, size: 16, color: color),
    };
  }

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

    return InteractionFeedback(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      onHoverChanged: (h) => setState(() => _hovered = h),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: HyperReactive(
          selected: widget.active,
          borderRadius: 6,
          child: AnimatedScale(
            scale: chrome.scale,
            duration: context.motion(context.surfaceShader.duration),
            curve: context.surfaceShader.curve,
            child: AnimatedContainer(
              duration: context.motion(context.surfaceShader.duration),
              // safeCurve (no overshoot) because this AnimatedContainer
              // lerps boxShadow — easeOutBack's overshoot past 1.0 drives
              // BoxShadow.lerp to extrapolate blurRadius negative,
              // tripping a Shadow assertion on elastic themes.
              curve: context.surfaceShader.safeCurve,
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
                  child: _buildIcon(iconColor),
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

  /// Continuous F-anomaly in `[0, 1]`. 0 = perfectly-stable repo; 1 =
  /// every bit of free energy on the upper-spectrum modes. Drives the
  /// title's sheen strength; leaves the base text colour untouched.
  final double anomaly;

  /// Repo's universality classification — the nearest spectral
  /// archetype (crystalline / poisson / goe / tree / bulk /
  /// modular). Shapes the sheen's band count, width, palette, and
  /// tilt: crystalline repos get tight ordered sweeps, chaotic ones
  /// get multi-band turbulent ones. Null on no-basis repos.
  final UniversalityVector? universality;

  const _RepoNameLabel({
    required this.name,
    required this.hasRepo,
    this.repoPath,
    required this.onRefresh,
    this.anomaly = 0.0,
    this.universality,
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
    final baseColor =
        widget.hasRepo ? t.textStrong : t.textMuted.withValues(alpha: 0.5);
    // Hover is the ONLY thing that recolours the title. Health state is
    // communicated entirely through the sheen; the letters themselves
    // stay the colour the user's eye expects from pure interaction.
    final color = widget.hasRepo && _hovered ? t.accentBright : baseColor;

    return MouseRegion(
      cursor: widget.hasRepo ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.hasRepo ? _fetch : null,
        child: AnimatedDefaultTextStyle(
          // Base-colour transitions calmly, over ~600ms — slow enough
          // not to flicker on each rebuild, fast enough to feel live.
          duration: context.motion(const Duration(milliseconds: 600)),
          style: TextStyle(
            color: _fetching ? t.accentBright.withValues(alpha: 0.6) : color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          child: HyperhealthText(
            text: widget.name,
            intensity: widget.anomaly,
            refreshing: _fetching,
            universality: widget.universality,
            // No special "fetching colour" — the refresh sheen itself
            // is the affordance now, so the base text stays readable
            // in its hover/default colour while the swoosh does the
            // job the old dim accent used to do.
            baseColor: color,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _XrayModeBtn extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _XrayModeBtn({
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ModeBtn(icon: 'xray', active: active, width: 34, onTap: onTap);
  }
}

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
    // Narrow the RepositoryState subscription to the two fields the
    // desk strip actually rebuilds against (`activePath` + `status`).
    // `repoState` below is `context.read` — used for mutating calls
    // (`setActivePath`, `refreshStatus`) and passed into helper flows
    // that expect the full instance. Because `read` doesn't subscribe,
    // the only rebuild trigger is the narrow select above.
    final repoSnap = context
        .select<RepositoryState, ({String? path, RepositoryStatus? status})>(
      (s) => (path: s.activePath, status: s.status),
    );
    final repoActivePath = repoSnap.path;
    final repoStatus = repoSnap.status;
    final repoState = context.read<RepositoryState>();
    final activeNormalized =
        activeRepoPath?.replaceAll('\\', '/').toLowerCase();
    final activeDesk = worktreeState.activeDesk;
    final activeActivity =
        activeDesk == null ? null : worktreeState.activityFor(activeDesk.path);
    // Other desks = every known worktree except the one currently active.
    final otherDesks = worktreeState.desks.where((d) {
      return d.path.replaceAll('\\', '/').toLowerCase() != activeNormalized;
    }).toList();
    final suggestedSyncTargetPath = _suggestedSyncTargetPath(
      activeDesk: activeDesk,
      activeActivity: activeActivity,
      otherDesks: otherDesks,
      worktreeState: worktreeState,
    );

    // Wrap the whole desk row in a DragTarget so dragging a branch row
    // (from BRANCHES) or a PR row (from PRS) and dropping it anywhere
    // across the strip materialises a new desk. The drop-affordance
    // lights up the strip itself, so the user sees "drop here" without
    // having to aim for a specific spot — the entire row is fair game.
    return DragTarget<DeskDropPayload>(
      onWillAcceptWithDetails: (_) => activeRepoPath != null,
      onAcceptWithDetails: (details) =>
          _handleDeskDrop(context, details.data, worktreeState),
      builder: (ctx, candidates, _) {
        final hasCandidate = candidates.isNotEmpty;
        final t = ctx.tokens;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            // Soft accent wash when something is dragged over — fades
            // in/out so the affordance is obvious without being loud.
            color: hasCandidate
                ? t.accentBright.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasCandidate
                  ? t.accentBright.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
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
                  highlightSyncTarget: desk.path == suggestedSyncTargetPath,
                  onTap: () {
                    if (desk.path != repoActivePath) {
                      repoState.setActivePath(desk.path, addToRecents: false);
                    }
                  },
                  onClose: desk.isMain
                      ? null
                      : () => _closeDeskFlow(context, desk, worktreeState),
                  onSecondaryTap: (pos) => _showDeskContextMenu(
                      context, pos, desk, repoState, worktreeState),
                ),
              ],
              if (hasCandidate) ...[
                const SizedBox(width: 6),
                // Ghost placeholder showing where the new desk will land.
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: t.accentBright.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: t.accentBright.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('+',
                          style: TextStyle(
                            color: t.accentBright,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          )),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          candidates.first?.label ?? 'new desk',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.accentBright,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String? _suggestedSyncTargetPath({
    required WorktreeData? activeDesk,
    required DeskActivity? activeActivity,
    required List<WorktreeData> otherDesks,
    required WorktreeState worktreeState,
  }) {
    if (activeDesk == null || activeDesk.isDetached || activeDesk.isLocked) {
      return null;
    }
    WorktreeData? bestDesk;
    var bestScore = 0;
    for (final targetDesk in otherDesks) {
      if (targetDesk.isDetached || targetDesk.isLocked) continue;
      final score = _syncSuggestionScore(
        activeDesk: activeDesk,
        activeActivity: activeActivity,
        targetDesk: targetDesk,
        targetActivity: worktreeState.activityFor(targetDesk.path),
      );
      if (score > bestScore) {
        bestScore = score;
        bestDesk = targetDesk;
      }
    }
    return bestDesk?.path;
  }

  int _syncSuggestionScore({
    required WorktreeData activeDesk,
    required DeskActivity? activeActivity,
    required WorktreeData targetDesk,
    required DeskActivity? targetActivity,
  }) {
    final targetDirty = targetDesk.dirtyFileCount > 0;
    final targetAhead = (targetActivity?.ahead ?? 0) > 0;
    final activeBehind = (activeActivity?.behind ?? 0) > 0;
    final targetIsMeaningfullyNewer = _isMeaningfullyNewer(
      candidate: targetActivity?.lastActivity,
      baseline: activeActivity?.lastActivity,
    );

    // On feature desks, prefer main when it looks newer.
    if (!activeDesk.isMain && targetDesk.isMain) {
      var score = 0;
      if (activeBehind) score += 5;
      if (targetDirty) score += 3;
      if (targetAhead) score += 2;
      if (targetIsMeaningfullyNewer) score += 2;
      return score;
    }

    // On main, prefer the busiest feature desk.
    if (activeDesk.isMain && !targetDesk.isMain) {
      var score = 0;
      if (targetDirty) score += 4;
      if (targetAhead) score += 3;
      if (targetIsMeaningfullyNewer) score += 2;
      return score;
    }

    return 0;
  }

  bool _isMeaningfullyNewer({
    required DateTime? candidate,
    required DateTime? baseline,
  }) {
    if (candidate == null) return false;
    if (baseline == null) return true;
    return candidate.isAfter(baseline.add(const Duration(hours: 6)));
  }

  Future<void> _handleDeskDrop(
    BuildContext context,
    DeskDropPayload payload,
    WorktreeState worktreeState,
  ) async {
    if (activeRepoPath == null) return;
    if (payload.isBranch) {
      final existing = worktreeState.desks.firstWhere(
        (d) => d.branch == payload.branchName,
        orElse: () => const WorktreeData(
          path: '',
          head: '',
          isMain: false,
          isDetached: false,
          isLocked: false,
        ),
      );
      if (existing.path.isNotEmpty) {
        // Already has a desk — just switch to it.
        await context
            .read<RepositoryState>()
            .setActivePath(existing.path, addToRecents: false);
        return;
      }
      final err = await worktreeState.addDesk(payload.branchName!);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open as desk: $err")),
        );
      }
    } else if (payload.isRemotePr) {
      final prN = payload.remotePrNumber!;
      final localRef = 'pr-$prN';
      final existing = worktreeState.desks.firstWhere(
        (d) => d.branch == localRef,
        orElse: () => const WorktreeData(
          path: '',
          head: '',
          isMain: false,
          isDetached: false,
          isLocked: false,
        ),
      );
      if (existing.path.isNotEmpty) {
        await context
            .read<RepositoryState>()
            .setActivePath(existing.path, addToRecents: false);
        return;
      }
      final remoteRes = await primaryRemoteName(activeRepoPath!);
      final remote = remoteRes.ok ? remoteRes.data : null;
      if (remote == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
              "Couldn't fetch PR: no remote configured.",
            )),
          );
        }
        return;
      }
      // If the local ref already exists without a live worktree, confirm
      // before force-overwriting — any local commits on that branch would
      // become unreachable with no UI path to the reflog.
      final refCheck = await Process.run(
        'git',
        ['rev-parse', '--verify', localRef],
        workingDirectory: activeRepoPath!,
      );
      if (refCheck.exitCode == 0 && context.mounted) {
        final t = context.tokens;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(
              'Overwrite $localRef with the latest from GitHub?',
              style: TextStyle(color: t.textNormal, fontSize: 12),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: TextStyle(color: t.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Overwrite',
                    style: TextStyle(color: t.stateDeleted)),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      if (!context.mounted) return;
      final fetchRes = await Process.run(
        'git',
        // '+' forces the local ref to update even if non-fast-forward
        // (force-pushed PR or ref exists from a previously closed desk).
        ['fetch', remote, '+pull/$prN/head:$localRef'],
        workingDirectory: activeRepoPath!,
      );
      if (fetchRes.exitCode != 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "Couldn't fetch PR: ${(fetchRes.stderr as String).trim()}")),
          );
        }
        return;
      }
      final err = await worktreeState.addDesk(localRef);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't open as desk: $err")),
        );
      }
    }
  }

  void _showDeskContextMenu(
    BuildContext context,
    Offset pos,
    WorktreeData desk,
    RepositoryState repoState,
    WorktreeState worktreeState,
  ) {
    final deskPrState = context.read<DeskPrState>();
    final branch = desk.branch;
    final hasPr = branch != null && deskPrState.prFor(branch) != null;
    final canPromote = branch != null && !desk.isDetached && !hasPr;
    final currentDesk = worktreeState.activeDesk;
    final currentDeskLabel = currentDesk == null
        ? (repoState.status?.branch ?? 'current')
        : _deskDisplayLabel(currentDesk);
    // Resolve main worktree path so we can exclude it from "Apply to
    // main" even in the edge case where a desk's path resolves to the
    // main worktree but isMain is false (unusual rebuilt state).
    // Without this guard, applyBranchToBase would merge a branch into
    // itself and the PR lifecycle would still transition to MERGED.
    String? mainPath;
    for (final d in worktreeState.desks) {
      if (d.isMain) {
        mainPath = d.path;
        break;
      }
    }
    final canApply = branch != null &&
        !desk.isDetached &&
        !desk.isMain &&
        desk.path != mainPath;
    final canUpdateCurrentFromDesk = desk.path != repoState.activePath &&
        desk.isMain &&
        currentDesk != null &&
        !currentDesk.isMain &&
        !currentDesk.isDetached &&
        !currentDesk.isLocked;
    showAppContextMenu(context, pos, [
      ListMenuSection([
        if (canPromote)
          AppContextMenuItem(
            icon: Icons.rocket_launch_outlined,
            label: 'Promote desk to PR',
            onTap: () =>
                _promoteDeskFlow(context, desk, repoState, deskPrState),
          ),
        if (canApply)
          AppContextMenuItem(
            icon: Icons.call_merge,
            label: 'Apply to main',
            onTap: () => _applyDeskToMainFlow(
                context, desk, repoState, deskPrState, worktreeState),
          ),
        // Keep branch upkeep separate from patch preview.
        if (canUpdateCurrentFromDesk)
          AppContextMenuItem(
            icon: Icons.system_update_alt,
            label: 'Update $currentDeskLabel from ${_deskDisplayLabel(desk)}',
            onTap: () => _updateCurrentDeskFromDeskFlow(
                context, desk, repoState, worktreeState),
          ),
        if (!canUpdateCurrentFromDesk && desk.path != repoState.activePath)
          AppContextMenuItem(
            icon: Icons.download_outlined,
            label: 'Bring changes from ${_deskDisplayLabel(desk)} here',
            onTap: () => _bringDeskChangesHereFlow(
                context, desk, repoState, worktreeState),
          ),
        if (hasPr)
          AppContextMenuItem(
            icon: Icons.edit_outlined,
            label: 'Edit local PR',
            onTap: () =>
                _editLocalPrFlow(context, desk, branch, repoState, deskPrState),
          ),
        if (hasPr)
          AppContextMenuItem(
            icon: Icons.delete_outline,
            label: 'Discard local PR',
            destructive: true,
            onTap: () async {
              final repo = repoState.activePath;
              if (repo == null) return;
              await deskPrState.abandon(repoPath: repo, branch: branch);
            },
          ),
      ]),
      if (!desk.isMain)
        ListMenuSection([
          AppContextMenuItem(
            icon: Icons.close,
            label: 'Close desk',
            destructive: true,
            onTap: () => _closeDeskFlow(context, desk, worktreeState),
          ),
        ]),
    ]);
  }

  Future<void> _promoteDeskFlow(
    BuildContext context,
    WorktreeData desk,
    RepositoryState repoState,
    DeskPrState deskPrState,
  ) async {
    final repo = repoState.activePath;
    final branch = desk.branch;
    if (repo == null || branch == null) return;
    final err = await deskPrState.promote(
      repoPath: repo,
      branch: branch,
      title: branch,
    );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't promote: $err")),
      );
    }
  }

  /// "Apply to main" routes through the same PR plumbing the branches
  /// page uses for its PR-row merge — desks are glorified PRs, so the
  /// audit trail and lifecycle transitions are identical.
  /// Steps:
  ///   1. Refuse if the desk has uncommitted edits (mirrors the branches
  ///      page's `dirtyFileCount > 0` guard).
  ///   2. Auto-promote the desk to a PR if it isn't one yet, so the
  ///      MERGED state has a record to land on.
  ///   3. Run the shared `applyBranchToBase` engine (rebase strategy by
  ///      default — linear history, matches GitHub's "Rebase and merge"
  ///      button) against the *main* worktree, which is found via the
  ///      WorktreeState's known desks.
  ///   4. Mark the PR as MERGED via DeskPrState (the existing audit
  ///      trail in `refs/manifold/desks/...` records the transition).
  ///   5. Refresh the worktree list so ahead/behind chrome catches up.
  Future<void> _applyDeskToMainFlow(
    BuildContext context,
    WorktreeData desk,
    RepositoryState repoState,
    DeskPrState deskPrState,
    WorktreeState worktreeState,
  ) async {
    final branch = desk.branch;
    if (branch == null) return;

    if (desk.dirtyFileCount > 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
            "Commit or shelve the desk's changes before applying.",
          )),
        );
      }
      return;
    }

    // Locate the main worktree path — that's where the merge happens.
    String? mainRepoPath;
    for (final d in worktreeState.desks) {
      if (d.isMain) {
        mainRepoPath = d.path;
        break;
      }
    }
    if (mainRepoPath == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
            'Could not resolve the main worktree path.',
          )),
        );
      }
      return;
    }

    // Auto-promote if no PR record exists yet — every apply lands a
    // metadata trail. baseRef is resolved by promote() against the
    // repo's actual default branch (origin/HEAD → main → master); if a
    // PR already exists with a different base, honour it.
    final existing = deskPrState.prFor(branch);
    if (existing == null) {
      final err = await deskPrState.promote(
        repoPath: mainRepoPath,
        branch: branch,
        title: branch,
      );
      if (err != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Couldn't promote desk: $err")),
          );
        }
        return;
      }
    }
    final baseRef = deskPrState.prFor(branch)?.baseRef;
    if (baseRef == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
            "Couldn't determine the base branch for this desk.",
          )),
        );
      }
      return;
    }
    if (baseRef == branch) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
            "PR base and head are the same branch ($branch) — nothing to apply.",
          )),
        );
      }
      return;
    }

    final result = await applyBranchToBase(
      mainRepoPath: mainRepoPath,
      branch: branch,
      baseRef: baseRef,
      method: BranchMergeMethod.rebase,
      deleteBranch: false, // desk worktree still references the branch
    );
    if (!context.mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Apply failed')),
      );
      return;
    }
    await deskPrState.setStateFor(
      repoPath: mainRepoPath,
      branch: branch,
      state: 'MERGED',
    );
    await worktreeState.refreshFor(mainRepoPath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied $branch to $baseRef')),
      );
    }
  }

  /// Preview updates from the clicked desk onto the current desk.
  ///
  /// Tries the simplest thing first: if the current desk is strictly
  /// behind [desk] (the source) and has a clean worktree, do a
  /// fast-forward merge — one git op, no dialog. Only falls back to
  /// the patch-preview flow when fast-forward isn't possible
  /// (uncommitted changes, diverged history, or the user's desk has
  /// its own commits ahead of the source).
  Future<void> _updateCurrentDeskFromDeskFlow(
    BuildContext context,
    WorktreeData desk,
    RepositoryState repoState,
    WorktreeState worktreeState,
  ) async {
    // Capture stable, widget-tree-rooted handles BEFORE any await.
    // After the first await the context-menu overlay is gone AND the
    // sidebar may have rebuilt (a 70 k-line `git diff` can take a few
    // hundred ms to stream, and the desk tile that originally owned
    // this context gets re-created during that window). Relying on
    // the raw `context.mounted` from that point on silently drops
    // snackbars and swallows the dialog — the "nothing happens" bug.
    // NavigatorState and ScaffoldMessengerState, by contrast, are
    // rooted at MaterialApp and survive all the rebuild churn below.
    // Navigator + messenger captured off the live widget-tree context
    // BEFORE any await. After the first await the context-menu overlay
    // is torn down and the desk tile may have rebuilt; raw context use
    // past that point silently swallows snackbars (the original
    // "nothing happens" bug).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final targetDesk = worktreeState.activeDesk;
    final targetLabel = targetDesk == null
        ? (repoState.status?.branch ?? 'current')
        : _deskDisplayLabel(targetDesk);
    final sourceLabel = _deskDisplayLabel(desk);
    final targetPath = repoState.activePath;
    final sourceRef = desk.branch ?? desk.head;
    if (targetPath == null ||
        sourceRef.isEmpty ||
        desk.path == targetPath) {
      return;
    }
    void toast(String msg) =>
        messenger.showSnackBar(SnackBar(content: Text(msg)));

    // Staleness guard: if the user switches to a different repo mid-
    // await, our captured `targetPath` no longer reflects the visible
    // state and any continuation would mutate/report on the wrong
    // repo. Widget-mount checks are the wrong layer — the overlay
    // context dies as soon as the menu dismisses, which is exactly
    // what produced the original silent-failure bug. Equality against
    // `repoState.activePath` is the real freshness signal.
    bool stillOnTarget() => repoState.activePath == targetPath;

    // Fast-forward safety shape:
    //   • Only when the source resolves AND target is STRICTLY behind
    //     (behind > 0, ahead == 0).
    //   • Only on a clean worktree — we don't want to entangle
    //     uncommitted work with an upstream merge. Dirty worktrees
    //     skip to patch preview where the user can review hunks.
    //   • `git merge --ff-only` refuses any non-fast-forward and leaves
    //     the worktree unchanged on failure; fall through to patch
    //     preview so the user always has a path forward.
    //   • Every branch surfaces a snackbar — silent no-op is the bug
    //     we're fixing.
    final isClean = repoState.status?.files.isEmpty ?? false;
    final compare = await getDeskAheadBehind(targetPath, sourceRef);
    if (!stillOnTarget()) return;
    if (compare.ok && isClean) {
      final info = compare.data!;
      if (info.behind > 0 && info.ahead == 0) {
        final ff = await fastForwardDeskTo(targetPath, sourceRef);
        if (!stillOnTarget()) return;
        if (ff.ok) {
          final n = info.behind;
          toast('Updated $targetLabel to $sourceLabel '
              '($n commit${n == 1 ? '' : 's'}).');
          await repoState.refreshStatus();
          if (!stillOnTarget()) return;
          await worktreeState.refreshFor(targetPath);
          return;
        }
        // FF declined (hook / stale index / unexpected). Surface WHY
        // before falling through to the patch flow so the dialog isn't
        // a surprise.
        toast("Fast-forward couldn't land cleanly — "
            'showing a patch preview instead.');
      } else if (info.behind == 0) {
        toast(info.ahead > 0
            ? '$targetLabel is ahead of $sourceLabel by '
                '${info.ahead} commit${info.ahead == 1 ? '' : 's'}.'
            : '$targetLabel is already up to date with $sourceLabel.');
        return;
      }
    } else if (compare.ok && !isClean) {
      // Dirty worktree — skip FF (entanglement risk) but explain the
      // choice so the patch dialog doesn't read as random.
      toast('Uncommitted changes in $targetLabel — '
          'previewing as a patch instead.');
    }

    if (!stillOnTarget()) return;
    await _openDeskPatchPreviewFlow(
      navigator.context,
      sourceDesk: desk,
      repoState: repoState,
      worktreeState: worktreeState,
      previewLabel: 'update $targetLabel from $sourceLabel',
      emptyMessage: 'No updates to bring from $sourceLabel.',
      failureLabel: 'Update prep failed',
    );
  }

  /// Preview the clicked desk's changes on the current desk.
  Future<void> _bringDeskChangesHereFlow(
    BuildContext context,
    WorktreeData desk,
    RepositoryState repoState,
    WorktreeState worktreeState,
  ) async {
    final targetDesk = worktreeState.activeDesk;
    final targetLabel = targetDesk == null
        ? (repoState.status?.branch ?? 'current')
        : _deskDisplayLabel(targetDesk);
    final sourceLabel = _deskDisplayLabel(desk);
    await _openDeskPatchPreviewFlow(
      context,
      sourceDesk: desk,
      repoState: repoState,
      worktreeState: worktreeState,
      previewLabel: 'bring changes from $sourceLabel into $targetLabel',
      emptyMessage:
          'No patchable changes to bring from $sourceLabel into $targetLabel.',
      failureLabel: 'Patch prep failed',
    );
  }

  Future<void> _openDeskPatchPreviewFlow(
    BuildContext context, {
    required WorktreeData sourceDesk,
    required RepositoryState repoState,
    required WorktreeState worktreeState,
    required String previewLabel,
    required String emptyMessage,
    required String failureLabel,
  }) async {
    final repoPath = repoState.activePath;
    if (repoPath == null) return;
    if (sourceDesk.path == repoPath) return; // can't preview from self
    final targetRef = repoState.status?.branch ?? 'HEAD';
    final result = await getDeskDumpDiff(sourceDesk.path, targetRef);
    if (!context.mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failureLabel: ${result.error}')),
      );
      return;
    }
    final diff = result.data ?? '';
    if (diff.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emptyMessage)),
      );
      return;
    }
    await showPatchPreviewDialog(
      context,
      repoPath: repoPath,
      rawPatch: diff,
      sourceLabel: previewLabel,
      onApplied: () async {
        if (!context.mounted) return;
        await repoState.refreshStatus();
        await worktreeState.refreshFor(repoPath);
      },
    );
  }

  Future<void> _editLocalPrFlow(
    BuildContext context,
    WorktreeData desk,
    String branch,
    RepositoryState repoState,
    DeskPrState deskPrState,
  ) async {
    final repo = repoState.activePath;
    if (repo == null) return;
    final pr = deskPrState.prFor(branch);
    if (pr == null) return;
    final titleCtrl = TextEditingController(text: pr.title);
    final bodyCtrl = TextEditingController(text: pr.body);
    var isDraft = pr.isDraft;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return StatefulBuilder(builder: (ctx, setSt) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Edit local PR',
                        style: t.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: titleCtrl,
                      hintText: 'title',
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    AppMultilineTextField(
                      controller: bodyCtrl,
                      hintText: 'body',
                      minHeight: 96,
                      maxHeight: 220,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AppCheckbox(
                          value: isDraft,
                          onChanged: (v) => setSt(() => isDraft = v),
                        ),
                        const SizedBox(width: 8),
                        const Text('draft', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('cancel'),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    if (result != true) return;
    final err = await deskPrState.editMeta(
      repoPath: repo,
      branch: branch,
      title: titleCtrl.text.trim(),
      body: bodyCtrl.text,
      isDraft: isDraft,
    );
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save: $err")),
      );
    }
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
  final bool highlightSyncTarget;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  /// Right-click handler. Called with the global pointer position so
  /// the caller can anchor a context menu to the cursor.
  final ValueChanged<Offset>? onSecondaryTap;

  const _DeskTab({
    required this.desk,
    this.highlightSyncTarget = false,
    required this.onTap,
    required this.onClose,
    this.onSecondaryTap,
  });

  @override
  State<_DeskTab> createState() => _DeskTabState();
}

class _DeskTabState extends State<_DeskTab>
    with SingleTickerProviderStateMixin, WindowAwakeGuardedMixin {
  static const Duration _authoredPulse = Duration(milliseconds: 1600);
  bool _hovered = false;
  late final AnimationController _dotPulseCtrl;
  late final Animation<double> _dotPulse;
  PreferencesState? _prefs;

  @override
  void initState() {
    super.initState();
    _dotPulseCtrl = AnimationController(
      vsync: this,
      duration: _authoredPulse,
    );
    _dotPulse = CurvedAnimation(
      parent: _dotPulseCtrl,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesState>();
    if (!identical(_prefs, prefs)) {
      _prefs?.removeListener(_onPrefsChanged);
      _prefs = prefs;
      prefs.addListener(_onPrefsChanged);
    }
    _syncDotPulse();
  }

  @override
  void onWindowAwakeChanged() => _onPrefsChanged();

  void _onPrefsChanged() {
    if (mounted) _syncDotPulse();
  }

  @override
  void didUpdateWidget(covariant _DeskTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightSyncTarget != widget.highlightSyncTarget) {
      _syncDotPulse();
    }
  }

  void _syncDotPulse() {
    final rate = _prefs?.motionRate ?? 1.0;
    final awake = WindowActivity.instance.awake;
    final reduce = rate <= kMotionRateOff || !awake;
    if (widget.highlightSyncTarget && !reduce) {
      _dotPulseCtrl.duration = Duration(
        microseconds: (_authoredPulse.inMicroseconds / rate).round().clamp(
              const Duration(milliseconds: 200).inMicroseconds,
              const Duration(seconds: 60).inMicroseconds,
            ),
      );
      if (!_dotPulseCtrl.isAnimating) {
        _dotPulseCtrl.repeat(reverse: true);
      }
      return;
    }
    _dotPulseCtrl.stop();
    _dotPulseCtrl.value = 0;
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _dotPulseCtrl.dispose();
    super.dispose();
  }

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

    // Watch the desk-PR state so the tab can carry a "has local PR"
    // glyph without polling — the context-menu options change shape
    // alongside it. Narrowed to a single bool so the tab no longer
    // rebuilds on unrelated PR mutations (audit entries, review
    // comments, status ticks) — only when this branch's PR-presence
    // flips.
    final branch = widget.desk.branch;
    final hasLocalPr = branch != null &&
        context.select<DeskPrState, bool>(
          (s) => s.prFor(branch) != null,
        );
    // Per-desk activity probes — already-cached on WorktreeState so
    // this is a synchronous lookup with no I/O on the build path.
    // Drives the dirty / ahead / behind / last-touched chrome that
    // makes the desk row a status map at a glance. Narrowed so the
    // tab only rebuilds when THIS desk's activity changes, not on
    // every other desk's poll tick.
    final activity = context.select<WorktreeState, DeskActivity?>(
      (s) => s.activityFor(widget.desk.path),
    );
    final dirtyN = widget.desk.dirtyFileCount;
    final aheadN = activity?.ahead ?? 0;
    final behindN = activity?.behind ?? 0;
    final syncHighlight = widget.highlightSyncTarget;
    final backgroundColor =
        _hovered ? t.secondaryBtnHoverBg : t.bg0.withValues(alpha: 0.25);
    final borderColor = t.chromeBorder.withValues(alpha: 0.2);

    return Tooltip(
      message: _composeTooltip(
        branch: label,
        dirty: dirtyN,
        ahead: aheadN,
        behind: behindN,
        lastActivity: activity?.lastActivity,
        hasLocalPr: hasLocalPr,
      ),
      waitDuration: const Duration(milliseconds: 400),
      child: LongPressDraggable<DeskDropPayload>(
        data: DeskDropPayload.desk(path: d.path, label: label),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DeskTabDragFeedback(label: label, tokens: t),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onSecondaryTap == null
                ? null
                : (d) => widget.onSecondaryTap!(d.globalPosition),
            child: AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 80)),
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: borderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot by default; close affordance on hover.
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: showCloseOverDot ? 0.0 : 1.0,
                          duration:
                              context.motion(const Duration(milliseconds: 100)),
                          child: AnimatedBuilder(
                            animation: _dotPulse,
                            builder: (context, _) {
                              final pulseT =
                                  syncHighlight ? _dotPulse.value : 0.0;
                              final haloScale = 1.15 + (0.65 * pulseT);
                              final dotScale = 1.0 + (0.18 * pulseT);
                              final haloAlpha =
                                  syncHighlight ? 0.08 + (0.14 * pulseT) : 0.0;
                              final liveDotColor = syncHighlight
                                  ? t.accentBright
                                      .withValues(alpha: 0.78 + (0.18 * pulseT))
                                  : dotColor;
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (syncHighlight)
                                    Transform.scale(
                                      scale: haloScale,
                                      child: Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: t.accentBright
                                              .withValues(alpha: haloAlpha),
                                        ),
                                      ),
                                    ),
                                  Transform.scale(
                                    scale: dotScale,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: liveDotColor,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        if (canClose)
                          AnimatedOpacity(
                            opacity: showCloseOverDot ? 1.0 : 0.0,
                            duration: context
                                .motion(const Duration(milliseconds: 100)),
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
                  if (hasLocalPr) ...[
                    const SizedBox(width: 6),
                    // "Local PR" sigil. Same accentBright as other "live"
                    // indicators so the eye groups them as the same kind
                    // of signal (this desk has metadata, the PR list will
                    // show it).
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.accentBright.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  if (dirtyN > 0) ...[
                    const SizedBox(width: 6),
                    // Dirty count — the number of modified-or-staged files
                    // in this worktree. Tabular figures so it doesn't jitter
                    // when the count crosses a digit boundary. Read at a
                    // glance: "this desk has work waiting on you."
                    Text(
                      '$dirtyN',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 9.5,
                        fontFamily: AppFonts.mono,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (aheadN > 0) ...[
                    const SizedBox(width: 6),
                    // Ahead-of-base — green up-chevron with count. Same
                    // accentBright as the rest of the live signals so they
                    // feel like one family of "this desk is alive."
                    _DeskTrendGlyph(
                      glyph: '↑',
                      count: aheadN,
                      color: t.stateAdded,
                    ),
                  ],
                  if (behindN > 0) ...[
                    const SizedBox(width: 4),
                    // Behind-of-base — warm down-chevron. Always shown when
                    // non-zero because "you're behind" is the kind of state
                    // where surprise is bad — better quiet awareness than
                    // discovery on a failed merge.
                    _DeskTrendGlyph(
                      glyph: '↓',
                      count: behindN,
                      color: t.stateConflicted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compose the hover-peek text. Reads as a one-line status sentence
  /// instead of a label list so the tooltip pops into the eye as
  /// "what's going on here" not "data fields about this desk."
  String _composeTooltip({
    required String branch,
    required int dirty,
    required int ahead,
    required int behind,
    required DateTime? lastActivity,
    required bool hasLocalPr,
  }) {
    final parts = <String>[branch];
    if (widget.highlightSyncTarget) parts.add('suggested source');
    if (dirty > 0) parts.add('$dirty modified');
    if (ahead > 0) parts.add('$ahead ahead');
    if (behind > 0) parts.add('$behind behind');
    if (hasLocalPr) parts.add('local PR');
    final head = parts.join(' · ');
    if (lastActivity == null) return head;
    final age = DateTime.now().difference(lastActivity);
    String rel;
    if (age.inMinutes < 1) {
      rel = 'just now';
    } else if (age.inMinutes < 60) {
      rel = '${age.inMinutes}m ago';
    } else if (age.inHours < 24) {
      rel = '${age.inHours}h ago';
    } else if (age.inDays < 30) {
      rel = '${age.inDays}d ago';
    } else {
      rel = '${(age.inDays / 30).floor()}mo ago';
    }
    return '$head\nlast touched $rel';
  }
}

String _deskDisplayLabel(WorktreeData desk) {
  if (desk.branch != null && desk.branch!.trim().isNotEmpty) {
    return desk.branch!;
  }
  if (desk.isDetached && desk.head.isNotEmpty) {
    return desk.head.substring(0, math.min(7, desk.head.length));
  }
  return 'desk';
}

/// Drag feedback chip shown while the user is dragging a desk tab to
/// "dump" its diff somewhere else (currently: the Changes page). Same
/// visual family as the branch/PR drag chip in branches_page.dart but
/// owned here so workspace_shell doesn't need a cross-feature import.
class _DeskTabDragFeedback extends StatelessWidget {
  final String label;
  final AppTokens tokens;
  const _DeskTabDragFeedback({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.accentBright.withValues(alpha: 0.18),
          border: Border.all(color: t.accentBright, width: 1),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: t.shadowElev.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⇢',
              style: TextStyle(
                color: t.accentBright,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact trend glyph + count. Used for ahead/behind in the desk
/// tab so the row-level status reads as a single visual family
/// instead of three loose pieces.
class _DeskTrendGlyph extends StatelessWidget {
  final String glyph;
  final int count;
  final Color color;
  const _DeskTrendGlyph({
    required this.glyph,
    required this.count,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          glyph,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        const SizedBox(width: 1),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontFamily: AppFonts.mono,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
      title: Text(
        'Close desk?',
        style: TextStyle(color: t.textStrong, fontSize: 14),
      ),
      // Buttons carry the verbs; copy just states the situation. The
      // user already knows what shelve/discard mean — explaining them
      // turns the dialog into a tutorial.
      content: Text(
        '${desk.dirtyFileCount} uncommitted '
        'file${desk.dirtyFileCount == 1 ? '' : 's'}.',
        style: TextStyle(color: t.textNormal, fontSize: 12),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_CloseDeskChoice.cancel),
          child: Text('Cancel', style: TextStyle(color: t.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_CloseDeskChoice.discard),
          child:
              Text('Discard & close', style: TextStyle(color: t.stateDeleted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_CloseDeskChoice.shelve),
          child:
              Text('Shelve & close', style: TextStyle(color: t.accentBright)),
        ),
      ],
    );
  }
}

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

    final issueState = context.read<DeskIssueState>();
    final openIssues = issueState.all.where((i) => i.state == 'OPEN').toList();

    // Remote issues from the global cache — no gh call needed at open time.
    final remoteCache = context.read<RemoteIssueCacheState>();
    final remoteIssues = remoteCache.all;

    // Build branch → remote-issue-numbers map from local desk PRs so the
    // side panel can filter remote issues when hovering a branch row.
    // DeskPr.linkedRemoteIssues records which remote issues a branch's PR
    // addresses — the exact join we need for hover filtering.
    final deskPrs = context.read<DeskPrState>().all;
    final branchRemoteIssues = <String, Set<int>>{};
    for (final pr in deskPrs) {
      if (pr.linkedRemoteIssues.isNotEmpty) {
        branchRemoteIssues[pr.headRef] = pr.linkedRemoteIssues.toSet();
      }
    }

    _overlay = OverlayEntry(builder: (_) {
      return _BranchPanelOverlay(
        // Panel starts at pill's top — pill fades out, panel morphs in.
        // Panel width matches the pill's actual rendered width so the
        // morph reads as a continuation, not an expansion into a
        // neighboring region.
        top: origin.dy,
        left: origin.dx,
        pillHeight: pillSize.height,
        minWidth: pillSize.width.clamp(240.0, _kBranchPillMaxWidth),
        branches: _branches,
        loading: _loading,
        switching: _switching,
        currentBranch: widget.branch,
        issues: openIssues,
        remoteIssues: remoteIssues,
        branchRemoteIssues: branchRemoteIssues,
        onDismiss: _close,
        onCheckout: _checkout,
        onOpenAsDesk: (branchName) async {
          // If this branch already has a desk, jump to it. Otherwise
          // create a new worktree for it and switch to it.
          final existing = worktreeState.desks.firstWhere(
            (d) => d.branch == branchName,
            orElse: () => const WorktreeData(
              path: '',
              head: '',
              isMain: false,
              isDetached: false,
              isLocked: false,
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
        onCreateIssue: widget.repoPath == null
            ? null
            : ({
                required String title,
                required String body,
                required bool promoteRemote,
              }) async {
                final err = await issueState.createMaybeRemote(
                  repoPath: widget.repoPath!,
                  title: title,
                  body: body,
                  promoteRemote: promoteRemote,
                );
                if (err == null && promoteRemote) {
                  // ignore: unawaited_futures
                  remoteCache.refreshFor(widget.repoPath!);
                }
                if (err == null && mounted) _close();
                return err;
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
      duration: context.motion(const Duration(milliseconds: 100)),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: ConstrainedBox(
            // Cap the pill's width so long branch names can't balloon
            // the pill wider than the popup that overlays it. Without
            // this cap, a long branch name pushed the next desk tab
            // rightward, leaving visible dead space between the popup
            // (fixed-width) and the next tab when the popup was open.
            constraints: const BoxConstraints(maxWidth: _kBranchPillMaxWidth),
            child: AnimatedContainer(
              key: _pillKey,
              duration: context.motion(const Duration(milliseconds: 150)),
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
                  Flexible(
                    child: Text(
                      widget.branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: t.textNormal,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AppIcon(name: 'chevron-right', size: 10, color: t.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hard cap for the branch pill + its overlay panel. Chosen to fit most
/// conventional branch names in full (e.g. `feature/long-descriptive-name`)
/// while clipping truly hostile ones like CI-generated codex branches.
/// Pill and panel share this so the panel visually replaces the pill
/// without leaving a gap against the next desk tab.
const double _kBranchPillMaxWidth = 280;

class _BranchPanelOverlay extends StatefulWidget {
  final double top;
  final double left;
  final double pillHeight;
  final double minWidth;
  final List<BranchInfo> branches;
  final bool loading;
  final bool switching;
  final String currentBranch;
  final List<DeskIssue> issues;

  /// Remote issues from [RemoteIssueCacheState].
  final List<IssueSummary> remoteIssues;

  /// Maps desk-PR head branches to the remote issue numbers they address.
  final Map<String, Set<int>> branchRemoteIssues;
  final VoidCallback onDismiss;
  final ValueChanged<String> onCheckout;
  final ValueChanged<String>? onOpenAsDesk;
  final ValueChanged<String>? onCreateDeskFromHead;
  final Set<String> branchesOpenAsDesks;
  final VoidCallback onNavigate;

  /// Submit a new issue. Returns an error string or null on success.
  final Future<String?> Function({
    required String title,
    required String body,
    required bool promoteRemote,
  })? onCreateIssue;

  const _BranchPanelOverlay({
    required this.top,
    required this.left,
    required this.pillHeight,
    required this.minWidth,
    required this.branches,
    required this.loading,
    required this.switching,
    required this.currentBranch,
    this.issues = const [],
    this.remoteIssues = const [],
    this.branchRemoteIssues = const {},
    required this.onDismiss,
    required this.onCheckout,
    this.onOpenAsDesk,
    this.onCreateDeskFromHead,
    this.branchesOpenAsDesks = const {},
    required this.onNavigate,
    this.onCreateIssue,
  });

  @override
  State<_BranchPanelOverlay> createState() => _BranchPanelOverlayState();
}

class _BranchPanelOverlayState extends State<_BranchPanelOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _reveal;
  late final Animation<double> _fade;
  String? _hoveredBranch;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _reveal = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honor reduce-motion on reveal: snap straight to the opened state.
    if (context.reduceMotion) {
      _ctrl.value = 1;
    } else if (_ctrl.value < 1 && !_ctrl.isAnimating) {
      _ctrl.forward();
    }
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
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
                                        Flexible(
                                          child: ThemeMorphText(
                                            widget.currentBranch,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            style: TextStyle(
                                              color: t.textNormal,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                              onBranchHover: (b) =>
                                  setState(() => _hoveredBranch = b),
                              t: t,
                            ),
                          ],
                        ),
                      ),
                      // ── Issues side panel — always present so the popout
                      // functions as the issue hub (list, filter, create).
                      const SizedBox(width: 6),
                      _IssuesSidePanel(
                        localIssues: widget.issues,
                        remoteIssues: widget.remoteIssues,
                        branchRemoteIssues: widget.branchRemoteIssues,
                        hoveredBranch: _hoveredBranch,
                        borderColor: borderColor,
                        onCreateIssue: widget.onCreateIssue,
                        t: t,
                      ),
                    ],
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

  /// Called with branch name on row hover-enter, null on hover-exit.
  final ValueChanged<String?>? onBranchHover;
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
    this.onBranchHover,
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
            onTap: branch.current ? null : () => onCheckout(branch.name),
            onOpenAsDesk:
                onOpenAsDesk == null ? null : () => onOpenAsDesk!(branch.name),
            alreadyOpenAsDesk: branchesOpenAsDesks.contains(branch.name),
            onHoverChanged: (hovered) =>
                onBranchHover?.call(hovered ? branch.name : null),
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

  /// Reports hover state changes to parent (true = entered, false = exited).
  final ValueChanged<bool>? onHoverChanged;

  const _BranchRow({
    required this.branch,
    required this.isCurrent,
    required this.switching,
    required this.t,
    required this.onTap,
    this.onOpenAsDesk,
    this.alreadyOpenAsDesk = false,
    this.onHoverChanged,
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
      cursor: canSwitch ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHoverChanged?.call(true);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHoverChanged?.call(false);
      },
      child: GestureDetector(
        onTap: canSwitch ? widget.onTap : null,
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 80)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: _hovered && canSwitch
              ? t.secondaryBtnHoverBg
              : t.secondaryBtnHoverBg.withValues(alpha: 0),
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
                    fontWeight:
                        widget.isCurrent ? FontWeight.w600 : FontWeight.w400,
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
                if (b.ahead > 0 && b.behind > 0) const SizedBox(width: 3),
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
                    child: HoverableTap(
                      onTap: widget.onOpenAsDesk,
                      builder: (context, hovered) =>
                          AnimatedDefaultTextStyle(
                        duration: AppMotion.snap,
                        curve: AppMotion.snapCurve,
                        style: TextStyle(
                          color: hovered
                              ? t.accentBright
                              : t.accentBright.withValues(alpha: 0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        child: const Text('→ open'),
                      ),
                    ),
                  )
                else if (_hovered)
                  Tooltip(
                    message: 'Open on a new desk',
                    child: HoverableTap(
                      onTap: widget.onOpenAsDesk,
                      builder: (context, hovered) =>
                          AnimatedDefaultTextStyle(
                        duration: AppMotion.snap,
                        curve: AppMotion.snapCurve,
                        style: TextStyle(
                          color: hovered ? t.textStrong : t.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                        child: const Text('+ desk'),
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
  final DreamHintController<String> _branchDream = DreamHintController();

  @override
  void initState() {
    super.initState();
    _branchDream.addListener(_onDreamChanged);
  }

  void _onDreamChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _branchDream.removeListener(_onDreamChanged);
    _branchDream.dispose();
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

  /// Compute a dreamed branch-name slug from the current working-tree
  /// diff. Same pipeline the commit composer uses, with the output
  /// kebab-cased into a branch-ref-shaped token. Null if there's no
  /// meaningful diff yet (new branch on a clean tree).
  Future<String?> _computeBranchNameDream(String repoPath) async {
    final engine = context.read<LogosGitState>().engineFor(repoPath);
    if (engine == null) return null;
    final results = await Future.wait([
      runGitProbe(repoPath, [
        'diff', '-U3', '--no-color', '--patience', '--ignore-cr-at-eol',
      ]),
      runGitProbe(repoPath, [
        'diff', '--cached', '-U3', '--no-color', '--patience',
        '--ignore-cr-at-eol',
      ]),
      runGitProbe(repoPath, ['log', '--format=%s', '-100']),
    ]);
    final unstaged =
        results[0].exitCode == 0 ? results[0].stdout.toString() : '';
    final staged =
        results[1].exitCode == 0 ? results[1].stdout.toString() : '';
    final diffText = [staged, unstaged]
        .where((d) => d.trim().isNotEmpty)
        .join('\n');
    if (diffText.isEmpty) return null;
    final subjects = results[2].exitCode == 0
        ? results[2]
            .stdout
            .toString()
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : const <String>[];
    final phrase = await dreamFromDiff(
      repoPath: repoPath,
      diffText: diffText,
      engine: engine,
      recentSubjects: subjects,
    );
    if (phrase == null) return null;
    final slug = slugifyForBranch(phrase);
    return slug.isEmpty ? null : slug;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (_expanded) {
      // Dream a branch-name slug from the current working-tree diff.
      // Scheduler short-circuits on unchanged signature so calling on
      // every rebuild is cheap.
      final repoPath = context.select<RepositoryState, String?>(
        (s) => s.activePath,
      );
      if (repoPath != null && _ctrl.text.trim().isEmpty) {
        final engineReady = context.select<LogosGitState, bool>(
          (s) => s.engineFor(repoPath) != null,
        );
        final sig = '$repoPath|${engineReady ? 'rdy' : 'wait'}';
        _branchDream.schedule(
          sig,
          () => _computeBranchNameDream(repoPath),
        );
      }
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
                  hintText: _branchDream.value ?? 'new-branch-name',
                  hintStyle: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            HoverableTap(
              onTap: () => setState(() {
                _expanded = false;
                _ctrl.clear();
              }),
              builder: (context, hovered) => AnimatedDefaultTextStyle(
                duration: AppMotion.snap,
                curve: AppMotion.snapCurve,
                style: TextStyle(
                  color: hovered ? t.textStrong : t.textMuted,
                  fontSize: 9,
                ),
                child: const Text('esc'),
              ),
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
          duration: context.motion(const Duration(milliseconds: 80)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          // RGB-matched lerp endpoint to avoid the gray-flash that
          // `Colors.transparent` (= transparent BLACK) produces.
          color: _hovered
              ? t.secondaryBtnHoverBg
              : t.secondaryBtnHoverBg.withValues(alpha: 0),
          child: Row(
            children: [
              Text(
                '+ new desk',
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
          duration: context.motion(const Duration(milliseconds: 80)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered
                ? t.secondaryBtnHoverBg
                : t.secondaryBtnHoverBg.withValues(alpha: 0),
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

const double _kIssuesPanelWidth = 172.0;

/// Unified item for the side panel — wraps either a local [DeskIssue] or a
/// pure-remote [IssueSummary] (one that has no local counterpart yet).
class _SidePanelIssue {
  final int displayId;
  final String title;
  final String state;

  /// True when backed by a local DeskIssue (has git storage).
  final bool isLocal;

  /// True when the issue exists on GitHub (local+promoted counts here too).
  final bool isRemote;

  const _SidePanelIssue({
    required this.displayId,
    required this.title,
    required this.state,
    required this.isLocal,
    required this.isRemote,
  });

  bool get isOpen => state == 'OPEN';
}

/// Side panel attached to the branch picker overlay.
/// Shows a deduplicated list of open issues from both local storage
/// ([localIssues]) and the GitHub cache ([remoteIssues]). A local issue
/// with [DeskIssue.remoteNumber] set is considered the canonical record and
/// suppresses the matching remote entry.
/// Hover filter:
///   • Local issues → `addressedBy.contains(hoveredBranch)`
///   • Remote-only  → `branchRemoteIssues[hoveredBranch]?.contains(number)`
class _IssuesSidePanel extends StatefulWidget {
  final List<DeskIssue> localIssues;
  final List<IssueSummary> remoteIssues;
  final Map<String, Set<int>> branchRemoteIssues;
  final String? hoveredBranch;
  final Color borderColor;
  final Future<String?> Function({
    required String title,
    required String body,
    required bool promoteRemote,
  })? onCreateIssue;
  final AppTokens t;

  const _IssuesSidePanel({
    required this.localIssues,
    required this.remoteIssues,
    required this.branchRemoteIssues,
    required this.hoveredBranch,
    required this.borderColor,
    required this.onCreateIssue,
    required this.t,
  });

  @override
  State<_IssuesSidePanel> createState() => _IssuesSidePanelState();
}

class _IssuesSidePanelState extends State<_IssuesSidePanel> {
  bool _composing = false;
  bool _promoteRemote = false;
  bool _submitting = false;
  String? _error;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _titleFocus = FocusNode();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _openCompose() {
    setState(() {
      _composing = true;
      _error = null;
    });
    // Focus after the frame so the field is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  void _cancelCompose() {
    setState(() {
      _composing = false;
      _error = null;
      _promoteRemote = false;
      _titleCtrl.clear();
      _bodyCtrl.clear();
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || widget.onCreateIssue == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await widget.onCreateIssue!(
      title: title,
      body: _bodyCtrl.text.trim(),
      promoteRemote: _promoteRemote,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _submitting = false;
        _error = err;
      });
    } else {
      // Reset form state so the widget is not frozen if the parent is slow
      // to close the overlay (e.g. due to a rebuild race).
      setState(() {
        _submitting = false;
        _composing = false;
      });
    }
  }

  List<_SidePanelIssue> _buildItems() {
    // Build a fast lookup map so the hover-filter pass never does a linear
    // scan and can't throw StateError on a missing id.
    final localById = {for (final i in widget.localIssues) i.issueId: i};

    // Remote issue numbers already represented locally (promoted / imported).
    final promotedNumbers = widget.localIssues
        .where((i) => i.remoteNumber != null)
        .map((i) => i.remoteNumber!)
        .toSet();

    final items = <_SidePanelIssue>[
      for (final i in widget.localIssues)
        _SidePanelIssue(
          displayId: i.issueId,
          title: i.title,
          state: i.state,
          isLocal: true,
          isRemote: i.remoteNumber != null,
        ),
      for (final r in widget.remoteIssues)
        if (!promotedNumbers.contains(r.number))
          _SidePanelIssue(
            displayId: r.number,
            title: r.title,
            state: r.state,
            isLocal: false,
            isRemote: true,
          ),
    ];

    if (widget.hoveredBranch == null) return items;

    final linked = widget.branchRemoteIssues[widget.hoveredBranch] ?? const {};
    return items.where((item) {
      if (item.isLocal) {
        final local = localById[item.displayId];
        if (local == null) return false; // shouldn't happen, but safe
        return local.addressedBy.contains(widget.hoveredBranch) ||
            (local.remoteNumber != null && linked.contains(local.remoteNumber));
      }
      // Pure-remote: check via DeskPr linkage.
      return linked.contains(item.displayId);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final items = _buildItems();

    return Container(
      width: _kIssuesPanelWidth,
      decoration: BoxDecoration(
        color: Color.alphaBlend(t.inputBg, t.bg0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.45 : 0.18),
            blurRadius: 10,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with inline "+ new" affordance.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 6, 5),
            child: Row(
              children: [
                Text(
                  'issues',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length}',
                  style: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.55),
                    fontSize: 9,
                  ),
                ),
                if (widget.onCreateIssue != null) ...[
                  const SizedBox(width: 6),
                  _CompactIconButton(
                    icon: _composing ? 'x' : 'plus',
                    tooltip: _composing ? 'cancel' : 'new issue',
                    onTap: _composing ? _cancelCompose : _openCompose,
                    t: t,
                  ),
                ],
              ],
            ),
          ),
          Container(
            height: 1,
            color: widget.borderColor.withValues(alpha: 0.5),
          ),
          if (_composing)
            _IssueComposeForm(
              titleCtrl: _titleCtrl,
              bodyCtrl: _bodyCtrl,
              titleFocus: _titleFocus,
              promoteRemote: _promoteRemote,
              submitting: _submitting,
              error: _error,
              onPromoteToggle: (v) => setState(() => _promoteRemote = v),
              onSubmit: _submit,
              t: t,
            ),
          if (!_composing && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                widget.hoveredBranch != null ? 'none linked' : 'no open issues',
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.45),
                  fontSize: 9.5,
                ),
              ),
            ),
          if (!_composing)
            for (final item in items.take(8))
              _SidePanelIssueRow(item: item, t: t),
        ],
      ),
    );
  }
}

/// Small icon button for header actions (+/x).
class _CompactIconButton extends StatefulWidget {
  final String icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppTokens t;

  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.t,
  });

  @override
  State<_CompactIconButton> createState() => _CompactIconButtonState();
}

class _CompactIconButtonState extends State<_CompactIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _hovered
                  ? t.accentBright.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: AppIcon(
              name: widget.icon,
              size: 10,
              color: _hovered ? t.accentBright : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline compose form for creating a new issue (local, optionally promoted).
class _IssueComposeForm extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final FocusNode titleFocus;
  final bool promoteRemote;
  final bool submitting;
  final String? error;
  final ValueChanged<bool> onPromoteToggle;
  final VoidCallback onSubmit;
  final AppTokens t;

  const _IssueComposeForm({
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.titleFocus,
    required this.promoteRemote,
    required this.submitting,
    required this.error,
    required this.onPromoteToggle,
    required this.onSubmit,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleCtrl,
            focusNode: titleFocus,
            enabled: !submitting,
            onSubmitted: (_) => onSubmit(),
            style: TextStyle(color: t.textNormal, fontSize: 10.5),
            decoration: InputDecoration(
              hintText: 'title',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              hintStyle: TextStyle(
                color: t.textMuted.withValues(alpha: 0.55),
                fontSize: 10.5,
              ),
              filled: true,
              fillColor: t.inputBg,
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: t.inputBorder.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: t.inputBorder.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.inputFocusBorder),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: bodyCtrl,
            enabled: !submitting,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: t.textNormal, fontSize: 10),
            decoration: InputDecoration(
              hintText: 'body (optional)',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              hintStyle: TextStyle(
                color: t.textMuted.withValues(alpha: 0.55),
                fontSize: 10,
              ),
              filled: true,
              fillColor: t.inputBg,
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: t.inputBorder.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: t.inputBorder.withValues(alpha: 0.6),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.inputFocusBorder),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _RemoteToggle(
                value: promoteRemote,
                onChanged: submitting ? null : onPromoteToggle,
                t: t,
              ),
              const Spacer(),
              _SubmitButton(
                label: promoteRemote ? 'create + push' : 'create',
                busy: submitting,
                onTap: onSubmit,
                t: t,
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: TextStyle(
                color: t.danger,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemoteToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppTokens t;

  const _RemoteToggle({
    required this.value,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onChanged == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: value ? t.accentBright : Colors.transparent,
                border: Border.all(
                  color: value
                      ? t.accentBright
                      : t.inputBorder.withValues(alpha: 0.7),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child:
                  value ? AppIcon(name: 'check', size: 8, color: t.bg0) : null,
            ),
            const SizedBox(width: 5),
            Text(
              'remote',
              style: TextStyle(
                color: value ? t.accentBright : t.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitButton extends StatefulWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;
  final AppTokens t;

  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onTap,
    required this.t,
  });

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: widget.busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.busy
                ? t.accentBright.withValues(alpha: 0.35)
                : _hovered
                    ? t.accentBright
                    : t.accentBright.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.busy ? '…' : widget.label,
            style: TextStyle(
              color: t.bg0,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SidePanelIssueRow extends StatelessWidget {
  final _SidePanelIssue item;
  final AppTokens t;

  const _SidePanelIssueRow({required this.item, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.isOpen
                    ? t.accentBright.withValues(alpha: 0.85)
                    : t.chromeBorder.withValues(alpha: 0.35),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '#${item.displayId} ${item.title}',
              style: TextStyle(
                color: t.textNormal,
                fontSize: 10,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Subtle indicator: remote-only issues get a faint cloud dot;
          // promoted (local+remote) issues get nothing extra — they're first-class.
          if (item.isRemote && !item.isLocal) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '↑',
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.4),
                  fontSize: 8,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Keeps all three pages alive so that in-progress work (like a running
/// review) survives page switches, while cross-fading + sliding the new
/// page in so rail navigation reads as motion, not a teleport. Direction
/// of the slide follows rail order (downward rail step = incoming rises
/// from below). Duration + curve come from `context.surfaceShader` so
/// each theme asserts its own nav cadence. Reduce-motion short-circuits
/// the animation entirely — state is preserved, visual is instant.
class _KeepAlivePages extends StatefulWidget {
  final _WorkspaceMode mode;
  final String? selectedCommitHash;
  final VoidCallback onOpenXray;
  final VoidCallback onOpenChanges;

  const _KeepAlivePages({
    required this.mode,
    this.selectedCommitHash,
    required this.onOpenXray,
    required this.onOpenChanges,
  });

  @override
  State<_KeepAlivePages> createState() => _KeepAlivePagesState();
}

class _KeepAlivePagesState extends State<_KeepAlivePages>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, value: 1);
  int _from = 0;
  int _to = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.mode.index;
    _to = widget.mode.index;
  }

  @override
  void didUpdateWidget(covariant _KeepAlivePages old) {
    super.didUpdateWidget(old);
    if (old.mode == widget.mode) return;
    _from = old.mode.index;
    _to = widget.mode.index;
    if (context.reduceMotionRead) {
      _ac.value = 1;
      return;
    }
    final shader = context.surfaceShader;
    _ac
      ..duration = shader.duration
      ..stop()
      ..value = 0
      // safeCurve — our opacity read (`t`) asserts [0, 1]; the lerp
      // math downstream (width, color) also can't extrapolate safely.
      ..animateTo(1, curve: shader.safeCurve);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ChangesPage(),
      HistoryPage(
        initialCommitHash: widget.selectedCommitHash,
        onOpenXray: widget.onOpenXray,
        onOpenChanges: widget.onOpenChanges,
      ),
      const BranchesPage(),
    ];
    // Pure crossfade — no slide. Sliding looked bad when both pages
    // shared content (e.g. the "no repository selected" empty state):
    // identical text would fade out 10px up while identical text faded
    // in from 10px down, producing a ghost-double effect mid-transition.
    // With opacity-only, two identical glyphs at the same position lerp
    // between themselves and visually stay still — the transition reads
    // as "nothing changed" for shared content, and as a clean fade for
    // pages with distinct content.
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ac,
        builder: (context, _) {
          final t = _ac.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < pages.length; i++)
                _buildLayer(pages[i], i, t),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLayer(Widget page, int i, double t) {
    final isIncoming = i == _to;
    final isOutgoing = i == _from && _from != _to && t < 1;
    // Any page that isn't the incoming or the outgoing stays offstage
    // but mounted — TickerMode off so its animations don't burn cycles.
    if (!isIncoming && !isOutgoing) {
      return Offstage(
        offstage: true,
        child: TickerMode(enabled: false, child: page),
      );
    }
    final opacity = isIncoming ? t : (1 - t);
    return IgnorePointer(
      ignoring: !isIncoming,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: TickerMode(enabled: isIncoming, child: page),
      ),
    );
  }
}

class _SlidePanel extends StatelessWidget {
  final String? title;
  final VoidCallback onClose;
  final Widget child;

  const _SlidePanel({
    super.key,
    this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final panelTone = t.innerPanelTone;
    // Enter/exit motion is driven by the parent AnimatedSwitcher — no
    // internal TweenAnimationBuilder here so the two can't double-animate
    // and fight each other on rapid toggles.
    // Backdrop is rendered separately by the parent so it can fade
    // without sliding when the panel animates in/out. This widget is
    // now just the panel body.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 48, 8, 8),
      child: MaterialSurface(
        tone: panelTone,
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
            duration: context.motion(const Duration(milliseconds: 80)),
            scale: chrome.scale,
            child: AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 80)),
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
