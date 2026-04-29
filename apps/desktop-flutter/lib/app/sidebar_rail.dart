import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'ai_activity_state.dart';
import '../backend/external_tools.dart';
import '../backend/file_picker.dart';
import '../backend/git.dart';
import '../backend/repo_web_url.dart';
import '../backend/system_browser.dart';
import '../backend/system_paths.dart';
import '../components/icons/app_icons.dart';
import '../ui/context_menu.dart';
import '../ui/control_chrome.dart';
import '../ui/design_primitives.dart';
import '../ui/form_controls.dart';
import '../ui/hover_lift.dart';
import '../ui/interaction_feedback.dart';
import '../ui/animated_icons.dart';
import '../ui/material_surface.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import 'window_activity.dart';
import 'external_tools_state.dart';
import 'hyper_reactivity.dart';
import 'repository_state.dart';
import 'settings_navigation_state.dart';

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
    // Narrow subscription: the rail only reads activePath and
    // recentPaths. Mutations (setActivePath, forgetRecent) go through
    // `context.read`. The prior `context.watch` forced a full rail
    // rebuild on every status tick of every repo.
    final activePath =
        context.select<RepositoryState, String?>((s) => s.activePath);
    final recentPaths = context
        .select<RepositoryState, List<String>>((s) => s.recentPaths);
    final repo = context.read<RepositoryState>();
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
              final visiblePaths = recentPaths
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
                        isActive: activePath != null &&
                            _normalizePath(activePath) ==
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
                child: HoverableTap(
                  onTap: running
                      ? null
                      : () => onModeChanged(_RepositoryEntryMode.create),
                  builder: (context, hovered) => AnimatedDefaultTextStyle(
                    duration: AppMotion.snap,
                    curve: AppMotion.snapCurve,
                    style: TextStyle(
                      color: hovered ? t.textStrong : t.accentBright,
                      fontSize: 10,
                      decoration: hovered
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: t.accentBright,
                    ),
                    child: const Text('Switch to Create repo'),
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
    final radius =
        BorderRadius.circular(context.surfaceShader.geometry.radius);
    return ChromeButton(
      onTap: onTap,
      borderRadius: radius,
      padding: EdgeInsets.zero,
      chromeBuilder: ({required hovered, required pressed}) =>
          modeButtonChrome(
        t,
        hovered: hovered,
        pressed: pressed,
        active: active,
      ),
      child: SizedBox(
        height: 24,
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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius =
        BorderRadius.circular(context.surfaceShader.geometry.radius);
    return ChromeButton(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      borderRadius: radius,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      padding: EdgeInsets.zero,
      chromeBuilder: ({required hovered, required pressed}) =>
          primaryButtonChrome(
        t,
        hovered: hovered,
        pressed: pressed,
        enabled: enabled,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? t.btnText : t.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
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

class _ProjectItemState extends State<_ProjectItem>
    with WindowAwakeMixin<_ProjectItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _affordanceHovered = false;

  /// The badge's slide-into-place animation depends on the engine
  /// scheduling continuous frames. When the window is unfocused the
  /// platform throttles frame production, so [AnimatedPositioned]
  /// kicks off its tween but never gets a second tick to advance —
  /// the badge stays at its starting `right: 0` while the hover-
  /// reveal "Open in Explorer" icon renders inline at that same
  /// edge, and the two visually overlap. We rebuild on awake-state
  /// changes so the build below can pick the right widget shape:
  /// [AnimatedPositioned] when awake (smooth slide), plain
  /// [Positioned] when not (instant snap, no intermediate frames
  /// required to land at the target).
  @override
  void onWindowAwakeChanged() {
    if (mounted) setState(() {});
  }
  // Cached web URL info for this project's `origin` remote, or null
  // when the repo has no remote / no derivable web URL. Resolved
  // asynchronously on mount.
  RepoWebInfo? _webInfo;
  // Cached origin remote URL for the "Copy clone URL" action. Stored
  // verbatim — preserves whatever form (SSH-shorthand, ssh://,
  // https://) the user configured locally.
  String? _originUrl;
  // Cached path to a README file in the repo root, or null when none
  // exists. Detected synchronously on mount (cheap fs check).
  String? _readmePath;

  @override
  void initState() {
    super.initState();
    _detectReadmeSync();
    _resolveRemoteAndWeb();
  }

  @override
  void didUpdateWidget(covariant _ProjectItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _webInfo = null;
      _originUrl = null;
      _detectReadmeSync();
      _resolveRemoteAndWeb();
    }
  }

  /// Walk a small priority-ordered list of common README filenames
  /// in the repo root. First hit wins; null when none exist.
  /// Synchronous — `existsSync` is microseconds and we want the
  /// menu row to render the first time the user right-clicks
  /// without waiting on an async hop.
  void _detectReadmeSync() {
    const candidates = [
      'README.md',
      'readme.md',
      'README.MD',
      'Readme.md',
      'README',
      'README.txt',
      'README.rst',
    ];
    final sep = Platform.pathSeparator;
    for (final name in candidates) {
      final path = '${widget.path}$sep$name';
      if (File(path).existsSync()) {
        _readmePath = path;
        return;
      }
    }
    _readmePath = null;
  }

  /// Resolve `origin` once, derive both the raw URL (for "Copy clone
  /// URL") and the classified web info (for "Open on <Host>") in a
  /// single subprocess spawn. Stale-result guard handles the case
  /// where the bound path changed between spawn and resolve.
  Future<void> _resolveRemoteAndWeb() async {
    final pathAtCallTime = widget.path;
    String? raw;
    try {
      final r = await Process.run(
        'git',
        ['remote', 'get-url', 'origin'],
        workingDirectory: pathAtCallTime,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode == 0) {
        final s = (r.stdout as String).trim();
        if (s.isNotEmpty) raw = s;
      }
    } catch (_) {/* silent — local-only repo */}
    if (!mounted || pathAtCallTime != widget.path) return;
    final info = raw == null ? null : classifyRemote(raw);
    setState(() {
      _originUrl = raw;
      _webInfo = info;
    });
  }

  /// Open the project's web page in the system browser. No-op if
  /// the web URL hasn't been resolved yet — the menu row only
  /// renders after resolution succeeds, so in practice this is
  /// always available when the row is.
  Future<void> _openOnWeb() async {
    final info = _webInfo;
    if (info == null) return;
    try {
      await openInSystemBrowser(info.webUrl);
    } catch (_) {/* silent — same rationale as system_paths.dart */}
  }

  /// Copy the origin remote URL verbatim. Preserves the form (SSH /
  /// HTTPS / ssh://) the user configured — they chose it for a
  /// reason; we don't try to be clever.
  Future<void> _copyCloneUrl() async {
    final url = _originUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
  }

  /// Open the detected README file via the OS default app. Routes
  /// through `openInDefaultApp` which handles the platform dispatch
  /// — the actual editor that opens depends on the user's OS-level
  /// file association.
  Future<void> _openReadme() async {
    final path = _readmePath;
    if (path == null) return;
    try {
      await openInDefaultApp(path);
    } catch (_) {/* silent */}
  }

  /// Open the OS file manager at the project's folder. Failures are
  /// silent on purpose — see `system_paths.dart` rationale.
  Future<void> _openInFileManager() async {
    try {
      await openInDefaultApp(widget.path);
    } catch (_) {
      // Tool missing or access denied — nothing useful to surface here.
    }
  }

  /// Open a terminal session with cwd at the project's folder.
  Future<void> _openInTerminal() async {
    try {
      await openTerminalAt(widget.path);
    } catch (_) {/* ignore */}
  }

  /// Copy the absolute project path to the clipboard.
  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: widget.path));
  }

  /// Run [tool] against the project. Substitutes `{path}` into the
  /// argv slots and dispatches via the appropriate launcher mode.
  /// Failures are silent — same rationale as `system_paths.dart`.
  Future<void> _runTool(ExternalTool tool) async {
    final exec = tool.executable.trim();
    if (exec.isEmpty) return;
    final args = tool.resolveArgs(widget.path);
    try {
      switch (tool.mode) {
        case ToolLaunchMode.newTerminal:
          await runInTerminal(
            executable: exec,
            args: args,
            workingDirectory: widget.path,
          );
        case ToolLaunchMode.detached:
          await runDetached(
            executable: exec,
            args: args,
            workingDirectory: widget.path,
          );
      }
    } catch (_) {/* silent — see system_paths.dart */}
  }

  /// Deep-link into Settings, scrolling to the External Tools section.
  /// Used by both the zero-state "Open with…" entry and the
  /// "Edit tools…" footer of a populated submenu.
  void _openExternalToolsSettings() {
    context
        .read<SettingsNavigationState>()
        .requestFocus(SettingsSection.externalTools);
  }

  /// Open the right-click context menu at [globalPos]. Sections build
  /// the canonical project actions (open / terminal / open-with /
  /// copy) above a destructive forget row, separated by a divider so
  /// the dangerous action stays visually quarantined from the safe
  /// ones.
  ///
  /// "Open with" only appears when at least one external tool is
  /// configured — when none are set, the row is omitted entirely so
  /// the menu stays focused on the project-intrinsic actions. First-
  /// time setup discoverability lives in Settings rather than as a
  /// ghost menu entry that just deep-links there.
  void _showContextMenu(BuildContext context, Offset globalPos) {
    // Outlined-icon variants in the context menu match the register
    // used by changes_page.dart's right-click menus. The inline
    // affordance icon (filled folder_open) stays filled since it's
    // an action button, not a menu glyph.
    final tools = context.read<ExternalToolsState>().tools;
    final webInfo = _webInfo;
    final originUrl = _originUrl;
    final readmePath = _readmePath;
    // Tile/chip section: locked-3 always-tiles on top (Explorer,
    // Terminal, Copy path — every project has these), conditional
    // chips beneath (Open Host, Copy URL, README, Open with…) in
    // canonical order. Chips read as ambient secondary register so
    // a wrap-laid position doesn't violate the muscle-memory rule
    // the way a tile-position shuffle would.
    final tiles = <AppContextMenuItem>[
      AppContextMenuItem(
        icon: Icons.folder_open_outlined,
        label: 'Explorer',
        onTap: _openInFileManager,
      ),
      AppContextMenuItem(
        icon: Icons.terminal,
        label: 'Terminal',
        onTap: _openInTerminal,
      ),
      AppContextMenuItem(
        icon: Icons.content_copy_outlined,
        label: 'Copy path',
        onTap: _copyPath,
      ),
    ];
    final chips = <AppContextMenuItem>[
      // "Open on <Host>" — project-intrinsic action, only shown when
      // the repo's origin remote resolves to a clean https URL.
      // Label is brand-pretty for github/gitlab/bitbucket.com, bare
      // host otherwise (Codeberg, sourcehut, Gitea, self-hosted all
      // show as their actual hostname).
      if (webInfo != null)
        AppContextMenuItem(
          icon: Icons.public_outlined,
          label: webInfo.label,
          onTap: _openOnWeb,
        ),
      // Clone URL → "Clone" + link icon. The action is "copy the
      // clone URL to clipboard" but the chip rail can't fit
      // "Clone URL" without truncation; the link icon already carries
      // the URL semantics, and "Clone" is the verb the user reaches
      // for ("git clone <this>") which preserves intent.
      if (originUrl != null)
        AppContextMenuItem(
          icon: Icons.link,
          label: 'Clone',
          onTap: _copyCloneUrl,
        ),
      // README — orientation aid, surfaces only when a README file
      // actually exists in the repo root.
      if (readmePath != null)
        AppContextMenuItem(
          icon: Icons.description_outlined,
          label: 'README',
          onTap: _openReadme,
        ),
      // "Open with…" — only when the user has set up at least one
      // external tool. Fits the philosophy: this slot exists because
      // *the user* opted in, not because the project happens to have
      // a remote / README / etc.
      if (tools.isNotEmpty)
        AppContextMenuItem(
          icon: Icons.launch,
          // "Tools" instead of "Open with" — fits the cell, and the
          // launch icon already carries the "open externally"
          // semantics. Chevron after the label hints the chip
          // expands to a submenu of configured tools.
          label: 'Tools',
          // Chip opens the submenu on click (cells in the mosaic
          // are stable, so a click-anchored submenu stays aligned
          // for its lifetime).
          onTap: () {},
          submenuBuilder: () => [
            for (final tool in tools)
              AppContextMenuItem(
                icon: tool.mode == ToolLaunchMode.newTerminal
                    ? Icons.terminal
                    : Icons.open_in_new,
                label: tool.displayLabel,
                onTap: () => _runTool(tool),
              ),
            AppContextMenuItem(
              icon: Icons.tune,
              label: 'Edit tools…',
              onTap: _openExternalToolsSettings,
            ),
          ],
        ),
    ];
    final sections = <MenuSection>[
      TileChipMenuSection(tiles: tiles, chips: chips),
      if (widget.onForget != null)
        ListMenuSection([
          AppContextMenuItem(
            icon: Icons.close,
            label: 'Forget this project',
            destructive: true,
            onTap: widget.onForget!,
          ),
        ]),
    ];
    showAppContextMenu(context, globalPos, sections);
  }

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
    final radius =
        BorderRadius.circular(context.surfaceShader.geometry.radius);

    return HoverLift(
      liftBy: widget.isActive ? 0 : 2,
      child: InteractionFeedback(
        onTap: widget.onTap,
        borderRadius: radius,
        onHoverChanged: (h) {
          if (h == _hovered) return;
          setState(() => _hovered = h);
        },
        onPressedChanged: (p) {
          if (p == _pressed) return;
          setState(() => _pressed = p);
        },
        // Right-click anywhere on the row opens the project context
        // menu. `globalPosition` anchors the overlay; the menu owns
        // its own dismiss tap-catcher via `showAppContextMenu`.
        onSecondaryTapDown: (pos) => _showContextMenu(context, pos),
        child: AnimatedScale(
          duration: AppMotion.snap,
          curve: AppMotion.snapCurve,
          scale: _pressed ? 0.99 : 1.0,
          child: AnimatedContainer(
            duration: AppMotion.snap,
            curve: AppMotion.snapCurve,
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: Border.all(color: borderColor),
            ),
            // Tooltip exposes the full path so duplicate-named entries
            // (e.g. the same repo cloned in two locations) can be told
            // apart.
            child: Tooltip(
              message: widget.path,
              waitDuration: const Duration(milliseconds: 400),
              // Stack so the AI activity overlay can float in the
              // upper-right corner of the pill without being part of
              // the row's flex math. The base Row keeps text + folder
              // button at their natural baseline; the overlay sits
              // above the text vertically and beside the folder
              // button horizontally, slightly transparent.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.name,
                          style: TextStyle(
                            color: widget.isActive
                                ? t.textStrong
                                : t.textNormal,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Hover-reveal "open in explorer" action. Inner
                      // MouseRegion + GestureDetector with opaque
                      // behavior wins the gesture arena so the
                      // icon's own click doesn't bubble up to the
                      // parent's row-tap. The destructive "forget"
                      // action moved to the right-click context menu
                      // — the inline affordance is reserved for the
                      // most-common positive action.
                      if (_hovered)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) =>
                              setState(() => _affordanceHovered = true),
                          onExit: (_) =>
                              setState(() => _affordanceHovered = false),
                          child: Tooltip(
                            message: 'Open in Explorer',
                            child: GestureDetector(
                              onTap: _openInFileManager,
                              behavior: HitTestBehavior.opaque,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: Center(
                                  child: Icon(
                                    Icons.folder_open,
                                    size: 14,
                                    color: _affordanceHovered
                                        ? t.textStrong
                                        : t.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Floats above the text and BESIDE the folder button.
                  // The hover-shown folder occupies an 18px slot at the
                  // row's right edge plus a 4px gap; offsetting the
                  // badge by that distance keeps the two icons in the
                  // same right-aligned column when both are visible
                  // and slides the badge back to the edge when the
                  // folder hides. When the window is awake we use
                  // [AnimatedPositioned] so the slide reads as one
                  // motion with the folder reveal; when unfocused the
                  // engine throttles frames and the tween would stick
                  // at its starting position, so we fall back to a
                  // plain [Positioned] that lays out at the target
                  // value without needing intermediate frames.
                  if (WindowActivity.instance.awake)
                    AnimatedPositioned(
                      duration: AppMotion.snap,
                      curve: AppMotion.snapCurve,
                      top: -3,
                      right: _hovered ? 22 : 0,
                      child: _ProjectAiStatusOverlay(repoPath: widget.path),
                    )
                  else
                    Positioned(
                      top: -3,
                      right: _hovered ? 22 : 0,
                      child: _ProjectAiStatusOverlay(repoPath: widget.path),
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

/// Floating AI-activity badge in the upper-right of a project entry.
/// Renders one tiny icon per running-or-unread record on the repo,
/// reading from [AiActivityState] keyed by [repoPath]. Returns an
/// empty widget when there's nothing to surface so the pill stays
/// visually clean for repos with no in-flight or unread runs.
///
/// Each badge is clickable: tapping switches the active repo to
/// [repoPath] and queues a `requestDrawerOpen` on AiActivityState
/// for the kind. The changes page reads that queue at build time
/// and opens the matching drawer (also firing markSeen so the
/// badge clears). Generate badges are clickable but don't open a
/// drawer — generate has no drawer; the click just routes the
/// user to the repo so they can re-engage with the message-apply
/// flow, and markSeen quiets the pill.
class _ProjectAiStatusOverlay extends StatelessWidget {
  final String repoPath;

  const _ProjectAiStatusOverlay({required this.repoPath});

  @override
  Widget build(BuildContext context) {
    // `select` so this widget only rebuilds when its own repo's
    // records change — sidebar rails of unrelated projects don't
    // re-layout on every state tick.
    final records = context.select<AiActivityState, List<AiActivityRecord>>(
      (s) => s.activeFor(repoPath),
    );
    if (records.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final r in records)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: _AiKindBadge(
              record: r,
              tokens: t,
              onTap: () => _activate(context, r),
            ),
          ),
      ],
    );
  }

  void _activate(BuildContext context, AiActivityRecord record) {
    final repoState = context.read<RepositoryState>();
    final activity = context.read<AiActivityState>();
    // Queue the drawer-open intent BEFORE the repo switch — the
    // changes page rebuilds when the active path lands and drains
    // the queue on its next build for `repoPath`. Registering after
    // the switch would race the rebuild on a same-repo click.
    if (record.kind == AiActivityKind.generate) {
      // Generate has no drawer — the click just brings the user to
      // the originating repo. Mark seen so the badge clears; the
      // user will see the toolbar's "unread" half-lit state if the
      // result is still pending application.
      activity.markSeen(repoPath: repoPath, kind: record.kind);
    } else {
      activity.requestDrawerOpen(repoPath, record.kind);
    }
    if (repoState.activePath != repoPath) {
      // Async, but we don't await it — the user wants the click to
      // feel instant and the changes page reads its own active path
      // each build. Errors (rare; only fire on a missing repo) are
      // logged via RepositoryState's existing surfacing.
      unawaited(repoState.setActivePath(repoPath));
    }
  }
}

class _AiKindBadge extends StatelessWidget {
  final AiActivityRecord record;
  final AppTokens tokens;
  /// Optional click handler. When non-null the badge becomes
  /// interactive (cursor + tap region). Null = pure indicator.
  final VoidCallback? onTap;

  const _AiKindBadge({
    required this.record,
    required this.tokens,
    this.onTap,
  });

  /// Maps a record's status onto the toolbar icons' shared
  /// [IconAnimState] vocabulary. Same loading spin / success flash /
  /// error shake the toolbar paints — only difference is no `hovered`
  /// (the badge isn't hover-target driven; tooltip handles disclosure).
  IconAnimState get _animState {
    if (record.isRunning) return IconAnimState.loading;
    if (record.isError) return IconAnimState.error;
    if (record.isDone) return IconAnimState.success;
    return IconAnimState.idle;
  }

  Color get _color {
    // Slightly transparent so the badge stays ambient. Hue carries
    // the meaning:
    //   * running — accentBright (catches the eye, says "active")
    //   * done    — stateAdded   (positive, available to read)
    //   * error   — stateDeleted (gentle red, says "didn't go well")
    if (record.isRunning) return tokens.accentBright.withValues(alpha: 0.7);
    if (record.isError) return tokens.stateDeleted.withValues(alpha: 0.7);
    return tokens.stateAdded.withValues(alpha: 0.7);
  }

  String get _tooltipMessage {
    final kind = switch (record.kind) {
      AiActivityKind.generate => 'commit message',
      AiActivityKind.review => 'review',
      AiActivityKind.muse => 'muse',
      AiActivityKind.ask => 'ask',
    };
    if (record.isRunning) return '$kind running';
    if (record.isError) return '$kind failed (unread)';
    return '$kind ready (unread)';
  }

  /// Icon body, picked to match the same glyph the composer toolbar
  /// renders for that flow:
  ///   * generate → AnimatedSparkleIcon (toolbar uses the same)
  ///   * review   → AnimatedSearchIcon, lens morphs to the verdict
  ///                shield/check/eye/warn/x on success — exactly like
  ///                the toolbar
  ///   * muse     → bubble_chart_outlined (toolbar is static here too)
  ///   * ask      → diamond_outlined (toolbar's ◈ shape is page-local;
  ///                the static fallback still tracks state via colour)
  Widget _iconForState(double size) {
    final state = _animState;
    final color = _color;
    switch (record.kind) {
      case AiActivityKind.generate:
        return AnimatedSparkleIcon(state: state, color: color, size: size);
      case AiActivityKind.review:
        // Pull the verdict off the typed result so the lens morphs into
        // the same shape the toolbar's review button shows on done.
        final verdict = switch (record.result) {
          AiReviewResult(:final data) => data.verdict,
          _ => null,
        };
        return AnimatedSearchIcon(
          state: state,
          color: color,
          size: size,
          verdict: verdict,
        );
      case AiActivityKind.muse:
        return AnimatedBubbleIcon(state: state, color: color, size: size);
      case AiActivityKind.ask:
        return Icon(Icons.diamond_outlined, size: size, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inner = SizedBox(
      width: 14,
      height: 14,
      child: Center(child: _iconForState(13)),
    );
    return Tooltip(
      message: _tooltipMessage,
      waitDuration: const Duration(milliseconds: 400),
      child: onTap == null
          ? inner
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: inner,
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
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius =
        BorderRadius.circular(context.surfaceShader.geometry.radius);
    return HyperReactive(
      selected: widget.active,
      borderRadius: 6,
      child: ChromeButton(
        onTap: widget.onTap,
        borderRadius: radius,
        padding: EdgeInsets.zero,
        chromeBuilder: ({required hovered, required pressed}) =>
            modeButtonChrome(
          t,
          hovered: hovered,
          pressed: pressed,
          active: widget.active,
        ),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: AppIcon(
              name: widget.icon,
              size: 16,
              color: widget.active ? t.accentBright : t.textMuted,
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
