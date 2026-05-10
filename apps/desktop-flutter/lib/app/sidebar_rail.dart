import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_activity_state.dart';
import 'logos_git_state.dart';
import 'sidebar_org_state.dart';
import '../backend/external_tools.dart';
import '../backend/logos_git.dart';
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

String _normalizePath(String path) {
  final p = path.replaceAll('\\', '/');
  return Platform.isLinux ? p : p.toLowerCase();
}

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
              final org = context.watch<SidebarOrgState>();
              final visiblePaths = recentPaths
                  .where((p) =>
                      !p.replaceAll('\\', '/').contains('/.manifold/worktrees/'))
                  .toList();
              final organizedPaths = org.organizedPaths;
              final ungroupedPaths = visiblePaths
                  .where((p) => !organizedPaths.contains(p))
                  .toList();

              if (org.isEmpty && ungroupedPaths.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    'No projects yet',
                    style: TextStyle(color: t.textMuted, fontSize: 11),
                  ),
                );
              }

              final flat = <_FlatItem>[];
              void flatten(List<SidebarNode> nodes, int depth,
                  int? color, String? parentId) {
                for (final n in nodes) {
                  switch (n) {
                    case SidebarRepo(:final path):
                      flat.add(_FlatItem.repo(path, depth, color, parentId));
                    case SidebarGroup():
                      final c = n.colorSlot ?? color;
                      flat.add(_FlatItem.group(n, depth, c, parentId));
                      if (!n.collapsed) {
                        flatten(n.children, depth + 1, c, n.id);
                      }
                  }
                }
              }
              flatten(org.roots, 0, null, null);

              final hasOrganized = flat.isNotEmpty;
              final hasUngrouped = ungroupedPaths.isNotEmpty;
              final hairlineCount =
                  hasOrganized && hasUngrouped ? 1 : 0;

              Widget wrapDraggable(String path, String label, Widget child) {
                return LongPressDraggable<String>(
                  data: path,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: _SidebarDragFeedback(label: label, tokens: t),
                  childWhenDragging: Opacity(opacity: 0.3, child: child),
                  child: child,
                );
              }

              Widget wrapDropTarget({
                required Widget child,
                required String? selfPath,
                required void Function(String sourcePath) onDrop,
              }) {
                return DragTarget<String>(
                  onWillAcceptWithDetails: (d) => d.data != selfPath,
                  onAcceptWithDetails: (d) => onDrop(d.data),
                  builder: (ctx, candidates, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        child,
                        if (candidates.isNotEmpty)
                          Positioned(
                            left: 4,
                            right: 4,
                            top: -1,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: t.accentBright.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              }

              const topZone = 1;
              final totalWithTop =
                  topZone + flat.length + hairlineCount + ungroupedPaths.length;

              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: totalWithTop,
                itemBuilder: (context, rawIndex) {
                  // ── Top pin zone ──
                  // Drop here to pin at the very top (no nesting).
                  if (rawIndex == 0) {
                    return DragTarget<String>(
                      onWillAcceptWithDetails: (_) => true,
                      onAcceptWithDetails: (d) =>
                          org.moveToTopLevel(d.data, index: 0),
                      builder: (ctx, candidates, _) {
                        return AnimatedContainer(
                          duration: AppMotion.snap,
                          height: candidates.isNotEmpty ? 24 : 4,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: candidates.isNotEmpty
                              ? BoxDecoration(
                                  color: t.accentBright
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: t.accentBright
                                        .withValues(alpha: 0.4),
                                  ),
                                )
                              : null,
                        );
                      },
                    );
                  }
                  final index = rawIndex - topZone;

                  // ── Organized zone ──
                  if (index < flat.length) {
                    final item = flat[index];
                    if (item.group != null) {
                      final g = item.group!;
                      final header = _GroupHeader(
                        key: ValueKey('grp_${g.id}'),
                        group: g,
                        depth: item.depth,
                        effectiveColor: item.colorSlot,
                        isHeadActive: g.headRepoPath != null &&
                            activePath != null &&
                            _normalizePath(activePath) ==
                                _normalizePath(g.headRepoPath!),
                        onToggleCollapsed: () =>
                            org.toggleCollapsed(g.id),
                        onTapHead: g.headRepoPath == null
                            ? null
                            : () async {
                                final err = await repo
                                    .setActivePath(g.headRepoPath!);
                                if (err != null && mounted) {
                                  setState(() => _error = err);
                                }
                              },
                        onDissolve: () =>
                            org.dissolveGroup(g.id),
                        onForget: g.headRepoPath == null
                            ? null
                            : () {
                                repo.forgetRecent(g.headRepoPath!);
                                org.forgetRepo(g.headRepoPath!);
                              },
                      );
                      return wrapDropTarget(
                        selfPath: g.headRepoPath,
                        onDrop: (src) =>
                            org.insertIntoGroup(src, g.id),
                        child: header,
                      );
                    }
                    final repoWidget = _ProjectItem(
                      key: ValueKey('org_${item.path}'),
                      name: _toProjectName(item.path!),
                      path: item.path!,
                      isActive: activePath != null &&
                          _normalizePath(activePath) ==
                              _normalizePath(item.path!),
                      depth: item.depth,
                      colorSlot: item.colorSlot,
                      onTap: () async {
                        final err =
                            await repo.setActivePath(item.path!);
                        if (err != null && mounted) {
                          setState(() => _error = err);
                        }
                      },
                      onForget: () {
                        repo.forgetRecent(item.path!);
                        org.forgetRepo(item.path!);
                      },
                    );
                    // Drop on an organized repo = nest source under it.
                    return wrapDropTarget(
                      selfPath: item.path,
                      onDrop: (src) =>
                          org.nestUnder(src, item.path!),
                      child: wrapDraggable(
                        item.path!,
                        _toProjectName(item.path!),
                        repoWidget,
                      ),
                    );
                  }
                  // ── Hairline ──
                  if (hasOrganized &&
                      index == flat.length) {
                    return wrapDropTarget(
                      selfPath: null,
                      onDrop: (src) {
                        if (org.organizedPaths.contains(src)) {
                          org.unanchorRepo(src);
                        } else {
                          org.moveToTopLevel(src);
                        }
                      },
                      child: _ZoneHairline(color: t.chromeBorder),
                    );
                  }
                  // ── Free space (MRU) ──
                  // Drop here = nest under target (same as organized).
                  // Dragging out of organized to here = undo org.
                  final ui = index -
                      flat.length -
                      hairlineCount;
                  final path = ungroupedPaths[ui];
                  final mruWidget = _ProjectItem(
                    key: ValueKey('mru_$path'),
                    name: _toProjectName(path),
                    path: path,
                    isActive: activePath != null &&
                        _normalizePath(activePath) ==
                            _normalizePath(path),
                    onTap: () async {
                      final err =
                          await repo.setActivePath(path);
                      if (err != null && mounted) {
                        setState(() => _error = err);
                      }
                    },
                    onForget: () {
                      repo.forgetRecent(path);
                      org.forgetRepo(path);
                    },
                  );
                  return wrapDropTarget(
                    selfPath: path,
                    onDrop: (src) {
                      if (org.organizedPaths.contains(src)) {
                        org.unanchorRepo(src);
                      } else {
                        org.nestUnder(src, path);
                      }
                    },
                    child: wrapDraggable(
                      path,
                      _toProjectName(path),
                      mruWidget,
                    ),
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

// ── Tree flattening helper ──────────────────────────────────────

class _FlatItem {
  final SidebarGroup? group;
  final String? path;
  final int depth;
  final int? colorSlot;
  final String? parentGroupId;

  _FlatItem.group(SidebarGroup g, this.depth, this.colorSlot, this.parentGroupId)
      : group = g,
        path = null;
  _FlatItem.repo(String p, this.depth, this.colorSlot, this.parentGroupId)
      : path = p,
        group = null;
}

// ── Hairline between organized and MRU zones ────────────────────

class _ZoneHairline extends StatelessWidget {
  final Color color;
  const _ZoneHairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Container(height: 1, color: color.withValues(alpha: 0.35)),
    );
  }
}

// ── Drag feedback pill ───────────────────────────────────────────

class _SidebarDragFeedback extends StatelessWidget {
  final String label;
  final AppTokens tokens;
  const _SidebarDragFeedback({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.accentBright.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.accentBright),
          boxShadow: [
            BoxShadow(
              color: t.shadowElev.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: t.accentBright,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: AppFonts.mono,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ── Group header row ────────────────────────────────────────────

class _GroupHeader extends StatefulWidget {
  final SidebarGroup group;
  final int depth;
  final int? effectiveColor;
  final bool isHeadActive;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onTapHead;
  final VoidCallback onDissolve;
  final VoidCallback? onForget;

  const _GroupHeader({
    super.key,
    required this.group,
    required this.depth,
    this.effectiveColor,
    this.isHeadActive = false,
    required this.onToggleCollapsed,
    this.onTapHead,
    required this.onDissolve,
    this.onForget,
  });

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hovered = false;
  bool _editing = false;
  late TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(
      text: widget.group.label ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _GroupHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.label != widget.group.label && !_editing) {
      _labelCtrl.text = widget.group.label ?? '';
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _submitLabel() {
    final text = _labelCtrl.text.trim();
    context.read<SidebarOrgState>().setGroupLabel(
      widget.group.id,
      text.isEmpty ? null : text,
    );
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final g = widget.group;
    final displayName = g.label ?? (g.headRepoPath != null
        ? _toProjectName(g.headRepoPath!)
        : '');
    final hasColor = widget.effectiveColor != null;
    final tintColor = hasColor
        ? t.repoTint(widget.effectiveColor!)
        : null;

    final background = widget.isHeadActive
        ? t.itemActiveBg
        : (_hovered
            ? t.itemHoverBg
            : t.itemHoverBg.withValues(alpha: 0));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: g.headRepoPath != null ? widget.onTapHead : null,
        child: AnimatedContainer(
          duration: AppMotion.snap,
          curve: AppMotion.snapCurve,
          margin: EdgeInsets.only(
            left: widget.depth * 14.0,
            top: 1,
            bottom: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(
              context.surfaceShader.geometry.radius,
            ),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  // Collapse chevron
                  GestureDetector(
                    onTap: widget.onToggleCollapsed,
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: Icon(
                          g.collapsed
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          size: 14,
                          color: t.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Label / name
                  Expanded(
                    child: _editing
                        ? SizedBox(
                            height: 16,
                            child: TextField(
                              controller: _labelCtrl,
                              autofocus: true,
                              style: TextStyle(
                                color: t.textNormal,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (_) => _submitLabel(),
                              onEditingComplete: _submitLabel,
                            ),
                          )
                        : GestureDetector(
                            onDoubleTap: () {
                              _labelCtrl.text = g.label ?? '';
                              setState(() => _editing = true);
                            },
                            child: Text(
                              displayName,
                              style: TextStyle(
                                color: widget.isHeadActive
                                    ? t.textStrong
                                    : t.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                  // Child count (when collapsed)
                  if (g.collapsed && g.children.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: t.textFaint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${g.descendantCount}',
                        style: TextStyle(
                          color: t.textFaint,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  // Dissolve (hover)
                  if (_hovered)
                    GestureDetector(
                      onTap: widget.onDissolve,
                      behavior: HitTestBehavior.opaque,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Tooltip(
                          message: 'Dissolve group',
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: Center(
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: t.textFaint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              // Color strip
              if (hasColor)
                Positioned(
                  left: -6,
                  top: -5,
                  bottom: -5,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: tintColor!.withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(4),
                      ),
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
  final int depth;
  final int? colorSlot;
  final VoidCallback onTap;
  final VoidCallback? onForget;

  const _ProjectItem({
    super.key,
    required this.name,
    required this.path,
    required this.isActive,
    this.depth = 0,
    this.colorSlot,
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
  // Lightweight repo stats for the status strip. Probed once on mount
  // via two cheap git commands so every repo gets a strip, not just
  // the active one.
  int? _cachedFileCount;
  int? _cachedCommitCount;
  int? _cachedContributorCount;
  String? _cachedRepoSize;
  String? _cachedLastActive;

  @override
  void initState() {
    super.initState();
    _detectReadmeAsync();
    _resolveRemoteAndWeb();
    _probeRepoStats();
  }

  @override
  void didUpdateWidget(covariant _ProjectItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _webInfo = null;
      _originUrl = null;
      _readmePath = null;
      _cachedFileCount = null;
      _cachedCommitCount = null;
      _cachedContributorCount = null;
      _cachedRepoSize = null;
      _cachedLastActive = null;
      _detectReadmeAsync();
      _resolveRemoteAndWeb();
      _probeRepoStats();
    }
  }

  /// Walk common README filenames asynchronously. Was _detectReadmeSync
  /// with File.existsSync — 7 stat() calls per project, all on the
  /// main thread during initState. With 5–10 projects in the sidebar,
  /// that's 35–70 synchronous filesystem probes on the first frame.
  /// Now async: the context menu row renders without the README chip
  /// on cold mount, then picks it up via setState once the exists()
  /// futures resolve (typically <5 ms total, invisible to the user).
  Future<void> _detectReadmeAsync() async {
    const candidates = [
      'README.md',
      'readme.md',
      'README.MD',
      'Readme.md',
      'README',
      'README.txt',
      'README.rst',
    ];
    final pathAtCallTime = widget.path;
    final sep = Platform.pathSeparator;
    for (final name in candidates) {
      final path = '$pathAtCallTime$sep$name';
      if (await File(path).exists()) {
        if (!mounted || widget.path != pathAtCallTime) return;
        setState(() => _readmePath = path);
        return;
      }
    }
    if (mounted && widget.path == pathAtCallTime) {
      setState(() => _readmePath = null);
    }
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

  Future<void> _probeRepoStats() async {
    final pathAtCallTime = widget.path;
    try {
      final results = await Future.wait([
        runGitProbe(pathAtCallTime, ['rev-list', '--count', 'HEAD']),
        runGitProbe(pathAtCallTime, ['ls-files']),
        runGitProbe(pathAtCallTime, ['shortlog', '-sn', '--all', '--no-merges']),
        runGitProbe(pathAtCallTime, ['count-objects', '-vH']),
        runGitProbe(pathAtCallTime, ['log', '-1', '--format=%cr']),
      ]);
      if (!mounted || pathAtCallTime != widget.path) return;
      final commitCount = results[0].exitCode == 0
          ? int.tryParse(results[0].stdout.toString().trim())
          : null;
      final fileCount = results[1].exitCode == 0
          ? results[1].stdout.toString().trim().split('\n').where((l) => l.isNotEmpty).length
          : null;
      int? contribCount;
      if (results[2].exitCode == 0) {
        contribCount = results[2].stdout.toString().trim()
            .split('\n').where((l) => l.isNotEmpty).length;
      }
      String? repoSize;
      if (results[3].exitCode == 0) {
        final sizeMatch = RegExp(r'size-pack:\s*(.+)')
            .firstMatch(results[3].stdout.toString());
        if (sizeMatch != null) repoSize = sizeMatch.group(1)!.trim();
      }
      String? lastActive;
      if (results[4].exitCode == 0) {
        final raw = results[4].stdout.toString().trim();
        if (raw.isNotEmpty) lastActive = raw;
      }
      setState(() {
        _cachedCommitCount = commitCount;
        _cachedFileCount = fileCount;
        _cachedContributorCount = contribCount;
        _cachedRepoSize = repoSize;
        _cachedLastActive = lastActive;
      });
    } catch (_) {/* silent — broken repo */}
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

  Future<void> _exportAsZip() async {
    try {
      final picked = await pickDirectory('Export to');
      if (picked == null) return;
      final repoName = widget.path
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .last;
      final outputPath = '$picked${Platform.pathSeparator}$repoName.zip';
      final result = await archiveRepository(widget.path, outputPath);
      if (result.ok) {
        await revealInFileManager(outputPath);
      }
    } catch (_) {}
  }

  Future<void> _duplicateRepo() async {
    try {
      final picked = await pickDirectory('Clone to');
      if (picked == null) return;
      final repoName = widget.path
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .last;
      final targetPath = '$picked${Platform.pathSeparator}$repoName-copy';
      final result = await cloneRepository(widget.path, targetPath);
      if (!mounted || !result.ok || result.data == null) return;
      await context.read<RepositoryState>().setActivePath(result.data!);
    } catch (_) {}
  }

  Future<void> _templateFromRepo() async {
    try {
      final picked = await pickDirectory('Create from template in');
      if (picked == null) return;
      final repoName = widget.path
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .last;
      final targetPath = '$picked${Platform.pathSeparator}$repoName-new';
      final result = await templateFromRepository(widget.path, targetPath);
      if (!mounted || !result.ok || result.data == null) return;
      await context.read<RepositoryState>().setActivePath(result.data!);
    } catch (_) {}
  }

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
  void _showContextMenu(BuildContext context, Offset globalPos,
      {bool shiftHeld = false}) {
    final tools = context.read<ExternalToolsState>().tools;
    final t = context.tokens;
    final shiftTint = shiftHeld ? t.hyperChromatic1 : null;
    final webInfo = _webInfo;
    final originUrl = _originUrl;
    final readmePath = _readmePath;
    final showCloneUrl = shiftHeld && originUrl != null;
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
      if (showCloneUrl)
        AppContextMenuItem(
          icon: Icons.link,
          label: 'Clone URL',
          onTap: _copyCloneUrl,
          iconColor: shiftTint,
        )
      else
        AppContextMenuItem(
          icon: Icons.content_copy_outlined,
          label: 'Copy path',
          onTap: _copyPath,
        ),
    ];
    final chips = <AppContextMenuItem>[
      if (webInfo != null)
        AppContextMenuItem(
          icon: Icons.public_outlined,
          label: webInfo.label,
          onTap: _openOnWeb,
        ),
      AppContextMenuItem(
        icon: Icons.archive_outlined,
        label: 'Export',
        onTap: _exportAsZip,
      ),
      if (readmePath != null)
        AppContextMenuItem(
          icon: Icons.description_outlined,
          label: 'README',
          onTap: _openReadme,
        ),
    ];
    final toolChips = <AppContextMenuItem>[
      if (shiftHeld)
        AppContextMenuItem(
          icon: Icons.file_copy_outlined,
          label: 'Duplicate',
          onTap: _duplicateRepo,
          iconColor: shiftTint,
        ),
      if (shiftHeld)
        AppContextMenuItem(
          icon: Icons.auto_awesome_outlined,
          label: 'Template',
          onTap: _templateFromRepo,
          iconColor: shiftTint,
        ),
      for (final tool in tools)
        AppContextMenuItem(
          icon: tool.mode == ToolLaunchMode.newTerminal
              ? Icons.terminal
              : Icons.open_in_new,
          label: tool.displayLabel,
          onTap: () => _runTool(tool),
        ),
    ];
    // ── Status strip data ──────────────────────────────────────────
    // Snapshot repo state at menu-open time. The strip is inert (no
    // provider subscription, no rebuild) so it shows what was true
    // at the moment of the right-click — honest and cheap.
    final repo = context.read<RepositoryState>();
    final isActiveRepo = repo.activePath != null &&
        _normalizePath(repo.activePath!) == _normalizePath(widget.path);
    final repoStatus = isActiveRepo ? repo.status : null;
    final aiRecords = context.read<AiActivityState>().activeFor(widget.path);
    // Logos engine — prefer its stats, fall back to the lightweight
    // probe cache so every repo gets a status strip.
    final engine =
        context.read<LogosGitState>().engineFor(widget.path);
    final stripFileCount =
        engine?.stats.touches.length ?? _cachedFileCount;
    final stripCommitCount =
        engine?.stats.totalCommits ?? _cachedCommitCount;

    final sections = <MenuSection>[
      TileChipMenuSection(
          tiles: tiles, chips: chips, toolChips: toolChips),
      if (stripFileCount != null || stripCommitCount != null)
        StatusMenuSection(
          _ProjectStatusStrip(
            tokens: context.tokens,
            dirtyCount: repoStatus?.files.length ?? 0,
            aiRecords: aiRecords,
            fileCount: stripFileCount,
            commitCount: stripCommitCount,
            contributorCount: _cachedContributorCount,
            repoSize: _cachedRepoSize,
            lastActive: _cachedLastActive,
          ),
        ),
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
    final background = widget.isActive
        ? t.itemActiveBg
        : (_hovered ? t.itemHoverBg : t.itemHoverBg.withValues(alpha: 0));
    final borderColor = widget.isActive
        ? t.itemActiveBorder
        : t.itemActiveBorder.withValues(alpha: 0);
    final radius =
        BorderRadius.circular(context.surfaceShader.geometry.radius);
    final badgeRight = _hovered ? 22.0 : 0.0;

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
        onSecondaryTapDown: (pos) {
          final shift = HardwareKeyboard.instance.logicalKeysPressed
              .any((k) => k == LogicalKeyboardKey.shiftLeft ||
                  k == LogicalKeyboardKey.shiftRight);
          _showContextMenu(context, pos, shiftHeld: shift);
        },
        child: AnimatedScale(
          duration: AppMotion.snap,
          curve: AppMotion.snapCurve,
          scale: _pressed ? 0.99 : 1.0,
          child: AnimatedContainer(
            duration: AppMotion.snap,
            curve: AppMotion.snapCurve,
            margin: EdgeInsets.only(
              left: widget.depth * 14.0,
              top: 1,
              bottom: 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: Border.all(color: borderColor),
            ),
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
                      if (_hovered)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) =>
                              setState(() => _affordanceHovered = true),
                          onExit: (_) =>
                              setState(() => _affordanceHovered = false),
                          child: Tooltip(
                            message: widget.path,
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
                  // Color strip
                  if (widget.colorSlot != null)
                    Positioned(
                      left: -8,
                      top: -6,
                      bottom: -6,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: t
                              .repoTint(widget.colorSlot!)
                              .withValues(alpha: 0.75),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  // AI activity badge
                  if (WindowActivity.instance.awake)
                    AnimatedPositioned(
                      duration: AppMotion.snap,
                      curve: AppMotion.snapCurve,
                      top: -3,
                      right: badgeRight,
                      child: _ProjectAiStatusOverlay(repoPath: widget.path),
                    )
                  else
                    Positioned(
                      top: -3,
                      right: badgeRight,
                      child: _ProjectAiStatusOverlay(repoPath: widget.path),
                    ),
                ],
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

/// Inert status gauge between the mosaic and Forget. Pure icons,
/// symbols, and animations — zero text labels. Communicates repo
/// health through visual language: arrows for ahead/behind, a
/// pip for dirty count, animated AI icons for in-flight work.
/// Ultra-dim opacity + tiny icon size signals "dashboard readout,
/// not a button." AI activity icons reuse the toolbar's animated
/// icon set (sparkle / search / bubble) at miniature scale. — calm green for clean/synced, amber for dirty,
class _ProjectStatusStrip extends StatefulWidget {
  final AppTokens tokens;
  final int dirtyCount;
  final List<AiActivityRecord> aiRecords;
  final int? fileCount;
  final int? commitCount;
  final int? contributorCount;
  final String? repoSize;
  final String? lastActive;

  const _ProjectStatusStrip({
    required this.tokens,
    required this.dirtyCount,
    required this.aiRecords,
    this.fileCount,
    this.commitCount,
    this.contributorCount,
    this.repoSize,
    this.lastActive,
  });

  @override
  State<_ProjectStatusStrip> createState() => _ProjectStatusStripState();
}

class _ProjectStatusStripState extends State<_ProjectStatusStrip> {
  static const _prefsKey = 'status_strip_page';
  static final ValueNotifier<bool> _page2 = ValueNotifier(false);
  static bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _page2.addListener(_onPageChanged);
    if (!_loaded) _loadPref();
  }

  @override
  void dispose() {
    _page2.removeListener(_onPageChanged);
    super.dispose();
  }

  void _onPageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPref() async {
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _page2.value = prefs.getBool(_prefsKey) ?? false;
  }

  void _toggle() {
    _page2.value = !_page2.value;
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_prefsKey, _page2.value));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    if (widget.fileCount == null && widget.commitCount == null) {
      return const SizedBox.shrink();
    }

    final numStyle = TextStyle(
      color: t.accentBright.withValues(alpha: 0.85),
      fontSize: 9.5,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w500,
    );
    final labelStyle = numStyle.copyWith(
      color: t.textFaint,
      fontWeight: FontWeight.w400,
    );
    final dot = TextSpan(
      text: '   ·   ',
      style: labelStyle.copyWith(
        color: t.textFaint.withValues(alpha: 0.5),
      ),
    );

    final spans = <InlineSpan>[];
    final fc = widget.fileCount;
    if (fc != null && fc > 0) {
      spans.add(TextSpan(text: _compact(fc), style: numStyle));
      spans.add(TextSpan(text: ' files', style: labelStyle));
    }

    if (_page2.value) {
      final sz = widget.repoSize;
      if (sz != null && spans.isNotEmpty) {
        spans.add(dot);
        spans.add(TextSpan(text: sz, style: numStyle));
      }
      final la = widget.lastActive;
      if (la != null) {
        if (spans.isNotEmpty) spans.add(dot);
        spans.add(TextSpan(text: la, style: numStyle));
      }
    } else {
      final cc = widget.commitCount;
      if (cc != null && cc > 0) {
        if (spans.isNotEmpty) spans.add(dot);
        spans.add(TextSpan(text: _compact(cc), style: numStyle));
        spans.add(TextSpan(text: ' commits', style: labelStyle));
      }
      final contrib = widget.contributorCount;
      if (contrib != null && contrib > 0) {
        if (spans.isNotEmpty) spans.add(dot);
        spans.add(TextSpan(text: '$contrib \u{263A}', style: numStyle));
      }
    }

    if (spans.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Center(
          child: Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  static String _compact(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
