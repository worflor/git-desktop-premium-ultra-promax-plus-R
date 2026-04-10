import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../backend/git.dart';
import '../components/icons/app_icons.dart';
import '../ui/control_chrome.dart';
import '../ui/form_controls.dart';
import '../ui/material_surface.dart';
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
  bool _isCloneMode = false;
  String? _error;
  String? _cloningEntry;

  @override
  void dispose() {
    _pathController.dispose();
    _cloneTargetController.dispose();
    super.dispose();
  }

  void _onInputChanged(String value) {
    final isUrl = _isGitUrl(value);
    if (isUrl && _cloneTargetController.text.isEmpty) {
      _cloneTargetController.text = _extractRepoName(value);
    }
    setState(() {
      _isCloneMode = isUrl;
      _error = null;
    });
  }

  Future<String?> _pickDirectory() {
    return FilePicker.platform.getDirectoryPath(dialogTitle: 'Open Repository');
  }

  Future<void> _onOpen() async {
    if (_isCloneMode) {
      await _onClone();
      return;
    }

    final repo = context.read<RepositoryState>();
    var path = _pathController.text.trim();
    if (path.isEmpty) {
      final picked = await _pickDirectory();
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
      _isCloneMode = false;
    });
  }

  Future<void> _onClone() async {
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
    if (!result.ok) {
      setState(() {
        _running = false;
        _cloningEntry = null;
        _error = result.error;
      });
      return;
    }

    final repo = context.read<RepositoryState>();
    await repo.setActivePath(result.data!);
    if (!mounted) return;
    setState(() {
      _running = false;
      _cloningEntry = null;
      _showPathEntry = false;
      _pathController.clear();
      _cloneTargetController.clear();
      _isCloneMode = false;
    });
  }

  Future<void> _onInit() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
    });
    final result = await initRepository(path);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _running = false;
        _error = result.error;
      });
      return;
    }

    final repo = context.read<RepositoryState>();
    await repo.setActivePath(result.data!);
    if (!mounted) return;
    setState(() {
      _running = false;
      _showPathEntry = false;
      _pathController.clear();
      _cloneTargetController.clear();
      _isCloneMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repo = context.watch<RepositoryState>();
    final railTone = t.id == AppThemeId.redshift
        ? AppMaterialTone.surface1
        : AppMaterialTone.surface0;

    return MaterialSurface(
      tone: railTone,
      radius: 0,
      border: Border(right: BorderSide(color: t.secondaryBtnBorder)),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: BrandLockup(),
          ),
          const SizedBox(height: 12),
          _ProjectsHeader(
            active: _showPathEntry,
            onTap: () => setState(() {
              _showPathEntry = !_showPathEntry;
              _error = null;
              if (_showPathEntry) {
                _pathController.clear();
                _cloneTargetController.clear();
                _isCloneMode = false;
              }
            }),
          ),
          if (_showPathEntry)
            _PathEntry(
              pathController: _pathController,
              cloneTargetController: _cloneTargetController,
              isCloneMode: _isCloneMode,
              running: _running,
              error: _error,
              onInputChanged: _onInputChanged,
              onOpen: _onOpen,
              onInit: _onInit,
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
            child: repo.recentPaths.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      'No projects yet',
                      style: TextStyle(color: t.textMuted, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: repo.recentPaths.length,
                    itemBuilder: (context, index) {
                      final path = repo.recentPaths[index];
                      return _ProjectItem(
                        name: _toProjectName(path),
                        path: path,
                        isActive: repo.activePath != null &&
                            _normalizePath(repo.activePath!) ==
                                _normalizePath(path),
                        onTap: () async {
                          final err = await repo.setActivePath(path);
                          if (err != null && mounted) {
                            setState(() => _error = err);
                          }
                        },
                      );
                    },
                  ),
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
  final bool isCloneMode;
  final bool running;
  final String? error;
  final ValueChanged<String> onInputChanged;
  final VoidCallback onOpen;
  final VoidCallback onInit;

  const _PathEntry({
    required this.pathController,
    required this.cloneTargetController,
    required this.isCloneMode,
    required this.running,
    this.error,
    required this.onInputChanged,
    required this.onOpen,
    required this.onInit,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StyledInput(
                  controller: pathController,
                  placeholder: isCloneMode
                      ? 'Repository URL'
                      : '/path/to/project or URL',
                  onChanged: onInputChanged,
                  onSubmitted: (_) => onOpen(),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: isCloneMode ? 54 : 48,
                height: 26,
                child: _PrimaryButton(
                  label: running ? '...' : (isCloneMode ? 'Clone' : 'Open'),
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
              placeholder: 'Clone to path',
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
                  onTap: running ? null : onInit,
                  child: Text(
                    'Initialize repository',
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
              borderRadius: BorderRadius.circular(6),
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

  const _ProjectItem({
    required this.name,
    required this.path,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ProjectItem> createState() => _ProjectItemState();
}

class _ProjectItemState extends State<_ProjectItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final background = widget.isActive
        ? t.itemActiveBg
        : (_hovered ? t.itemHoverBg : Colors.transparent);
    final borderColor =
        widget.isActive ? t.itemActiveBorder : Colors.transparent;

    return MouseRegion(
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
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
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
                  : (_hovered ? t.secondaryBtnHoverBg : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.active || _hovered
                    ? t.secondaryBtnBorder
                    : Colors.transparent,
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.3, end: 1.0).animate(_controller);
  }

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
