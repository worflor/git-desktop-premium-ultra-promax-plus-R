import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../backend/file_picker.dart';
import '../backend/git.dart';
import '../components/icons/app_icons.dart';
import '../ui/control_chrome.dart';
import '../ui/form_controls.dart';
import '../ui/hover_lift.dart';
import '../ui/material_surface.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import 'brand_lockup.dart';
import 'hyper_reactivity.dart';
import 'repository_state.dart';

bool _isGitUrl(String value) {
  final trimmed = value.trim();
  return trimmed.startsWith('https://') ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('git@') ||
      trimmed.startsWith('ssh://') ||
      trimmed.endsWith('.git');
}

String _extractRepoName(String url) {
  final cleaned = url
      .trim()
      .replaceAll(RegExp(r'\.git$'), '')
      .replaceAll(RegExp(r'/$'), '');
  final parts =
      cleaned.split(RegExp(r'[/:]')).where((part) => part.isNotEmpty).toList();
  return parts.isNotEmpty ? parts.last : 'repo';
}

String _toProjectName(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isNotEmpty ? parts.last : path;
}

String _normalizePath(String path) => path.replaceAll('\\', '/').toLowerCase();

enum _RepositoryEntryMode { open, clone, create }

class SidebarRail extends StatefulWidget {
  const SidebarRail({super.key});

  @override
  State<SidebarRail> createState() => _SidebarRailState();
}

class _SidebarRailState extends State<SidebarRail> {
  final _pathController = TextEditingController();
  final _cloneTargetController = TextEditingController();
  bool _showPathEntry = false;
  bool _running = false;
  _RepositoryEntryMode _entryMode = _RepositoryEntryMode.open;
  String? _error;
  String? _cloningEntry;

  @override
  void dispose() {
    _pathController.dispose();
    _cloneTargetController.dispose();
    super.dispose();
  }

  void _onInputChanged(String value) {
    if (_entryMode == _RepositoryEntryMode.clone &&
        _isGitUrl(value) &&
        _cloneTargetController.text.isEmpty) {
      _cloneTargetController.text = _extractRepoName(value);
    }
    setState(() {
      _error = null;
    });
  }

  Future<void> _onOpen() async {
    try {
      if (_entryMode == _RepositoryEntryMode.clone) {
        await _onClone();
        return;
      }
      if (_entryMode == _RepositoryEntryMode.create) {
        await _onInit();
        return;
      }

      final repo = context.read<RepositoryState>();
      var path = _pathController.text.trim();
      if (path.isEmpty) {
        final picked = await pickDirectory('Open Repository');
        if (picked == null) return;
        path = picked;
        _pathController.text = path;
      }

      setState(() {
        _running = true;
        _error = null;
      });
      final err = await repo.setActivePath(path);
      if (!mounted) return;
      setState(() => _running = false);
      if (err != null) {
        setState(() {
          _error = err.toLowerCase().contains('not a git')
              ? 'Not a git repository. Initialize one here?'
              : err;
        });
        return;
      }

      setState(() {
        _showPathEntry = false;
        _pathController.clear();
        _cloneTargetController.clear();
        _entryMode = _RepositoryEntryMode.open;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _onClone() async {
    try {
      final url = _pathController.text.trim();
      final target = _cloneTargetController.text.trim();
      if (url.isEmpty || target.isEmpty) {
        setState(() => _error = 'URL and target path required.');
        return;
      }

      setState(() {
        _running = true;
        _error = null;
        _cloningEntry = target;
      });
      final result = await cloneRepository(url, target);
      if (!mounted) return;
      if (!result.ok || result.data == null) {
        setState(() {
          _running = false;
          _cloningEntry = null;
          _error = result.error ?? 'Failed to clone repository.';
        });
        return;
      }

      final repo = context.read<RepositoryState>();
      final err = await repo.setActivePath(result.data!);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _running = false;
          _cloningEntry = null;
          _error = err;
        });
        return;
      }
      setState(() {
        _running = false;
        _cloningEntry = null;
        _showPathEntry = false;
        _pathController.clear();
        _cloneTargetController.clear();
        _entryMode = _RepositoryEntryMode.open;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _cloningEntry = null;
        _error = error.toString();
      });
    }
  }

  Future<void> _onInit() async {
    try {
      var path = _pathController.text.trim();
      if (path.isEmpty) {
        final picked = await pickDirectory('Create Repository');
        if (picked == null) return;
        path = picked;
        _pathController.text = path;
      }
      if (path.isEmpty) return;

      setState(() {
        _running = true;
        _error = null;
      });
      final result = await initRepository(path);
      if (!mounted) return;
      if (!result.ok || result.data == null) {
        setState(() {
          _running = false;
          _error = result.error ?? 'Failed to create repository.';
        });
        return;
      }

      final repo = context.read<RepositoryState>();
      final err = await repo.setActivePath(result.data!);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _running = false;
          _error = err;
        });
        return;
      }
      setState(() {
        _running = false;
        _showPathEntry = false;
        _pathController.clear();
        _cloneTargetController.clear();
        _entryMode = _RepositoryEntryMode.open;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repo = context.watch<RepositoryState>();
    final railTone = t.chromeTone;

    return MaterialSurface(
      tone: railTone,
      radius: 0,
      border: Border(right: BorderSide(color: t.secondaryBtnBorder)),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36),
          _ProjectsHeader(
            active: _showPathEntry,
            onTap: () => setState(() {
              _showPathEntry = !_showPathEntry;
              _error = null;
              if (_showPathEntry) {
                _pathController.clear();
                _cloneTargetController.clear();
                _entryMode = _RepositoryEntryMode.open;
              }
            }),
          ),
          if (_showPathEntry)
            _PathEntry(
              pathController: _pathController,
              cloneTargetController: _cloneTargetController,
              mode: _entryMode,
              running: _running,
              error: _error,
              onInputChanged: _onInputChanged,
              onModeChanged: (mode) => setState(() {
                _entryMode = mode;
                _error = null;
                if (mode != _RepositoryEntryMode.clone) {
                  _cloneTargetController.clear();
                }
              }),
              onOpen: _onOpen,
            ),
          if (_error != null && !_showPathEntry)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text(
                _error!,
                style: TextStyle(color: t.stateDeleted, fontSize: 11),
              ),
            ),
          if (_cloningEntry != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: Row(
                children: [
                  _PulsingDot(color: t.accentBright),
                  const SizedBox(width: 6),
                  Text('Cloning...',
                      style: TextStyle(color: t.textMuted, fontSize: 11)),
                ],
              ),
            ),
          Expanded(
            child: () {
              // Filter out any worktree paths that may have leaked into
              // recents (e.g. from pre-fix sessions). Worktrees are desks,
              // not projects — the sidebar is for distinct repos only.
              final visiblePaths = repo.recentPaths
                  .where((p) =>
                      !p.replaceAll('\\', '/').contains('/.manifold/worktrees/'))
                  .toList();
              if (visiblePaths.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    'No projects yet',
                    style: TextStyle(color: t.textMuted, fontSize: 11),
                  ),
                );
              }
              return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: visiblePaths.length,
                    itemBuilder: (context, index) {
                      final path = visiblePaths[index];
                      return _ProjectItem(
                        name: _toProjectName(path),
                        path: path,
                        isActive: repo.activePath != null &&
                            _normalizePath(repo.activePath!) ==
                                _normalizePath(path),
                        onTap: () async {
                          try {
                            final err = await repo.setActivePath(path);
                            if (err != null && mounted) {
                              setState(() => _error = err);
                            }
                          } catch (error) {
                            if (mounted) {
                              setState(() => _error = error.toString());
                            }
                          }
                        },
                        onForget: () => repo.forgetRecent(path),
                      );
                    },
                  );
            }(),
          ),
        ],
      ),
    );
  }
}

class _ProjectsHeader extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _ProjectsHeader({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
      child: Row(
        children: [
          Text(
            'Projects',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.4,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          _SidebarIconBtn(icon: 'plus', active: active, onTap: onTap),
        ],
      ),
    );
  }
}

class _PathEntry extends StatelessWidget {
  final TextEditingController pathController;
  final TextEditingController cloneTargetController;
  final _RepositoryEntryMode mode;
  final bool running;
  final String? error;
  final ValueChanged<String> onInputChanged;
  final ValueChanged<_RepositoryEntryMode> onModeChanged;
  final VoidCallback onOpen;

  const _PathEntry({
    required this.pathController,
    required this.cloneTargetController,
    required this.mode,
    required this.running,
    this.error,
    required this.onInputChanged,
    required this.onModeChanged,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isCloneMode = mode == _RepositoryEntryMode.clone;
    final isCreateMode = mode == _RepositoryEntryMode.create;
    final primaryLabel =
        isCloneMode ? 'Clone' : (isCreateMode ? 'Create' : 'Open');
    final pathPlaceholder = isCloneMode
        ? 'Repository URL'
        : (isCreateMode ? '/path/to/folder' : '/path/to/project');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ModeChoiceBtn(
                  label: 'Open',
                  active: mode == _RepositoryEntryMode.open,
                  onTap: () => onModeChanged(_RepositoryEntryMode.open),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ModeChoiceBtn(
                  label: 'Clone',
                  active: isCloneMode,
                  onTap: () => onModeChanged(_RepositoryEntryMode.clone),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ModeChoiceBtn(
                  label: 'Create',
                  active: isCreateMode,
                  onTap: () => onModeChanged(_RepositoryEntryMode.create),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _StyledInput(
                  controller: pathController,
                  placeholder: pathPlaceholder,
                  onChanged: onInputChanged,
                  onSubmitted: (_) => onOpen(),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: isCloneMode ? 58 : 56,
                height: 26,
                child: _PrimaryButton(
                  label: running ? '...' : primaryLabel,
                  enabled: !running,
                  onTap: onOpen,
                ),
              ),
            ],
          ),
          if (isCloneMode) ...[
            const SizedBox(height: 4),
            _StyledInput(
              controller: cloneTargetController,
              placeholder: 'Clone to folder path',
              fontSize: 11,
              onSubmitted: (_) => onOpen(),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error!, style: TextStyle(color: t.stateDeleted, fontSize: 11)),
            if (error!.contains('Initialize'))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: running
                      ? null
                      : () => onModeChanged(_RepositoryEntryMode.create),
                  child: Text(
                    'Switch to Create repo',
                    style: TextStyle(color: t.accentBright, fontSize: 10),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModeChoiceBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeChoiceBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 24,
        decoration: BoxDecoration(
          color: active ? t.itemActiveBg : t.surface0,
          borderRadius: BorderRadius.circular(context.surfaceShader.geometry.radius),
          border: Border.all(
            color: active ? t.itemActiveBorder : t.secondaryBtnBorder,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? t.textStrong : t.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _StyledInput extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final double fontSize;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _StyledInput({
    required this.controller,
    required this.placeholder,
    this.fontSize = 11,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<_StyledInput> createState() => _StyledInputState();
}

class _StyledInputState extends State<_StyledInput> {
  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      hintText: widget.placeholder,
      height: 26,
      fontSize: widget.fontSize,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = primaryButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      enabled: widget.enabled,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 80),
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(context.surfaceShader.geometry.radius),
              border: Border.all(
                color: chrome.borderColor,
              ),
              boxShadow: chrome.shadows,
            ),
            alignment: Alignment.center,
            child: Transform.translate(
              offset: chrome.offset,
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.enabled ? t.btnText : t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectItem extends StatefulWidget {
  final String name;
  final String path;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onForget;

  const _ProjectItem({
    required this.name,
    required this.path,
    required this.isActive,
    required this.onTap,
    this.onForget,
  });

  @override
  State<_ProjectItem> createState() => _ProjectItemState();
}

class _ProjectItemState extends State<_ProjectItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // RGB-matched lerp endpoints (`X.withValues(alpha: 0)` instead of
    // `Colors.transparent` = transparent BLACK) prevent the gray flash
    // that mid-lerp transparent-black causes during hover transitions.
    final background = widget.isActive
        ? t.itemActiveBg
        : (_hovered ? t.itemHoverBg : t.itemHoverBg.withValues(alpha: 0));
    final borderColor = widget.isActive
        ? t.itemActiveBorder
        : t.itemActiveBorder.withValues(alpha: 0);

    return HoverLift(
      liftBy: widget.isActive ? 0 : 2,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(context.surfaceShader.geometry.radius),
              border: Border.all(color: borderColor),
            ),
          // Tooltip exposes the full path so duplicate-named entries (e.g.
          // the same repo cloned in two locations) can be told apart.
          child: Tooltip(
            message: widget.path,
            waitDuration: const Duration(milliseconds: 400),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      color: widget.isActive ? t.textStrong : t.textNormal,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Hover-reveal "forget" action. Removes the entry from
                // recents without touching the repo on disk.
                if (_hovered && widget.onForget != null)
                  Tooltip(
                    message: 'Forget this project',
                    child: GestureDetector(
                      onTap: widget.onForget,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: Center(
                          child: Text(
                            '×',
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _SidebarIconBtn extends StatefulWidget {
  final String icon;
  final bool active;
  final VoidCallback onTap;

  const _SidebarIconBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SidebarIconBtn> createState() => _SidebarIconBtnState();
}

class _SidebarIconBtnState extends State<_SidebarIconBtn> {
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
        child: HyperReactive(
          selected: widget.active,
          borderRadius: 6,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: widget.active
                  ? t.itemActiveBg
                  : (_hovered
                      ? t.secondaryBtnHoverBg
                      : t.secondaryBtnHoverBg.withValues(alpha: 0)),
              borderRadius: BorderRadius.circular(context.surfaceShader.geometry.radius),
              border: Border.all(
                color: widget.active || _hovered
                    ? t.secondaryBtnBorder
                    : t.secondaryBtnBorder.withValues(alpha: 0),
              ),
            ),
            child: Center(
              child: AppIcon(
                name: widget.icon,
                size: 16,
                color: widget.active ? t.accentBright : t.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin, MotionLoopSync {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // MotionLoopSync starts/stops _controller in didChangeDependencies,
    // reacting live to Reduce Motion. At rest (reduce on) _controller.value
    // is 0 → opacity sits at 0.3, a static faint dot rather than a pulse.
    _opacity = Tween(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  List<AnimationController> get motionLoops => [_controller];

  @override
  List<bool> get motionLoopReverse => const [true];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
