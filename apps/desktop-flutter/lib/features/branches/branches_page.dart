import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/control_chrome.dart';
import '../../ui/form_controls.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../app/repository_state.dart';
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';

class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});
  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  List<BranchInfo> _branches = [];
  List<TagEntryData> _tags = [];
  bool _loading = false;
  String? _error;
  String? _lastRepo;
  String? _hoveredTag;

  final _newBranchCtrl = TextEditingController();
  bool _actionRunning = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'branches.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
    });
  }

  @override
  void dispose() {
    _newBranchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String repo) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    final bResult = await listBranches(repo);
    final tResult = await listTags(repo);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (bResult.ok) {
        _branches = bResult.data!;
      } else {
        _error = bResult.error;
      }
      if (tResult.ok) {
        _tags = tResult.data!;
      }
    });
    stopwatch.stop();
    await DiagnosticsState.instance.recordUiTiming(
      event: 'branches.snapshot.load',
      phase: 'interaction',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      ok: bResult.ok && tResult.ok,
      errorCode: bResult.ok && tResult.ok ? null : 'branches.load_failed',
    );
  }

  Future<void> _checkout(String repo, String name) async {
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await checkoutBranch(repo, name);
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    await _load(repo);
    if (!mounted) return;
    await context.read<RepositoryState>().refreshStatus();
  }

  Future<void> _deleteBranch(String repo, String name) async {
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await deleteBranch(repo, name);
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    await _load(repo);
  }

  Future<void> _deleteTag(String repo, String name) async {
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await deleteTag(repo, name);
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    await _load(repo);
  }

  Future<void> _createBranch(String repo) async {
    final name = _newBranchCtrl.text.trim();
    if (name.isEmpty || _actionRunning) return;
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await createBranch(repo, name, from: 'HEAD');
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    _newBranchCtrl.clear();
    await _load(repo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repo = context.watch<RepositoryState>();
    final repoPath = repo.activePath;

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }

    if (_lastRepo != repoPath) {
      _lastRepo = repoPath;
      _newBranchCtrl.clear();
      _actionError = null;
      _actionRunning = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(repoPath));
    }

    if (_loading && _branches.isEmpty) {
      return const AppStatusView.loading(
        title: 'Loading branches',
        message: 'Reading local branches and tags.',
      );
    }

    if (_error != null && _branches.isEmpty) {
      return AppStatusView.error(
        title: 'Branches unavailable',
        message: _error!,
      );
    }

    return Column(children: [
      // Header bar
      MaterialSurface(
        tone: AppMaterialTone.surface1,
        radius: 0,
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
        ),
        elevated: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          AppIcon(name: 'git-branch', size: 16, color: t.textNormal),
          const SizedBox(width: 8),
          Text('Branches',
              style: TextStyle(
                  color: t.textStrong,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: t.chromeBorder.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_branches.length} Local',
                style: TextStyle(color: t.textMuted, fontSize: 11)),
          ),
        ]),
      ),

      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!,
              style: TextStyle(color: t.stateConflicted, fontSize: 11)),
        ),

      // Two-column body
      Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Left: branch list + tags
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Repository Branches',
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.05)),
            const SizedBox(height: 8),
            // Branch list
            ...(_branches.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _BranchCard(
                    branch: b,
                    tokens: t,
                    actionRunning: _actionRunning,
                    onCheckout:
                        b.current ? null : () => _checkout(repoPath, b.name),
                    onDelete: b.current
                        ? null
                        : () => _deleteBranch(repoPath, b.name),
                  ),
                ))),

            // Tags section
            if (_tags.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
                child: Row(children: [
                  Expanded(
                      child: Divider(
                          color: t.chromeBorder.withOpacity(0.15),
                          height: 1,
                          thickness: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [
                      AppIcon(name: 'tag', size: 12, color: t.textMuted),
                      const SizedBox(width: 6),
                      Text('Tags',
                          style: TextStyle(
                              color: t.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.08)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: t.chromeBorder.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${_tags.length}',
                            style: TextStyle(
                                color: t.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                  Expanded(
                      child: Divider(
                          color: t.chromeBorder.withOpacity(0.15),
                          height: 1,
                          thickness: 1)),
                ]),
              ),
              ...(_tags.map((tag) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _TagCard(
                      tag: tag,
                      tokens: t,
                      hovered: _hoveredTag == tag.name,
                      actionRunning: _actionRunning,
                      onHoverChange: (v) =>
                          setState(() => _hoveredTag = v ? tag.name : null),
                      onDelete: () => _deleteTag(repoPath, tag.name),
                    ),
                  ))),
            ],
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: Text('No tags yet',
                        style: TextStyle(color: t.textMuted, fontSize: 11))),
              ),
          ]),
        )),

        // Right: Create Branch sidebar (240px)
        MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: 0,
          border: Border(
            left: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
          ),
          elevated: false,
          width: 240,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Create New Branch',
                        style: TextStyle(
                            color: t.textStrong,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    // Branch name input
                    Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          _createBranch(repoPath);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AppTextField(
                        controller: _newBranchCtrl,
                        height: 34,
                        fontSize: 12,
                        hintText: 'Branch name (e.g. feature/auth)',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Create button
                    SizedBox(
                      height: 26,
                      child: _ChromeButton(
                        label: 'Create branch from HEAD',
                        enabled: !(_newBranchCtrl.text.trim().isEmpty ||
                            _actionRunning),
                        onPressed: (_newBranchCtrl.text.trim().isEmpty ||
                                _actionRunning)
                            ? null
                            : () => _createBranch(repoPath),
                      ),
                    ),
                    // Action error
                    if (_actionError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: t.stateConflicted.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: t.stateConflicted.withOpacity(0.2)),
                          ),
                          child: Text(_actionError!,
                              style: TextStyle(
                                  color: t.stateConflicted, fontSize: 11)),
                        ),
                      ),
                  ]),
            ),
          ]),
        ),
      ])),
    ]);
  }
}

class _BranchCard extends StatefulWidget {
  final BranchInfo branch;
  final AppTokens tokens;
  final bool actionRunning;
  final VoidCallback? onCheckout;
  final VoidCallback? onDelete;
  const _BranchCard(
      {required this.branch,
      required this.tokens,
      required this.actionRunning,
      this.onCheckout,
      this.onDelete});
  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final b = widget.branch;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: context.motion(const Duration(milliseconds: 80)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: b.current
              ? t.accentBright.withOpacity(0.06)
              : (_hovered ? t.itemHoverBg : t.surface1),
          borderRadius:
              BorderRadius.circular(context.surfaceShader.geometry.radius),
          border: Border.all(
            color: b.current
                ? t.accentBright.withOpacity(0.2)
                : t.chromeBorder.withOpacity(0.08),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Branch icon or checkmark
          b.current
              ? AppIcon(name: 'check', size: 12, color: t.accentBright)
              : AppIcon(name: 'git-branch', size: 12, color: t.textMuted),
          const SizedBox(width: 8),
          // Name + tracking
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      b.name,
                      style: TextStyle(
                        color: b.current ? t.textStrong : t.textNormal,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (b.current) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.accentBright,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('HEAD',
                          style: TextStyle(
                              color: t.surface0,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.02)),
                    ),
                  ],
                ]),
                if (b.upstream != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Text(
                      '→ tracking: ${b.upstream}',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ])),
          // Ahead/behind indicators
          if (b.ahead > 0)
            Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('${b.ahead}↑',
                    style: TextStyle(color: t.stateAdded, fontSize: 10))),
          if (b.behind > 0)
            Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('${b.behind}↓',
                    style: TextStyle(color: t.stateModified, fontSize: 10))),
          // Checkout button (invisible but present for current branch — keeps layout stable)
          const SizedBox(width: 8),
          if (!b.current) ...[
            if (widget.onDelete != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _BranchIconAction(
                  icon: 'trash',
                  enabled: !widget.actionRunning,
                  onTap: widget.onDelete!,
                ),
              ),
            SizedBox(
              width: 80,
              height: 24,
              child: _ChromeButton(
                label: 'Checkout',
                compact: true,
                enabled: !widget.actionRunning,
                onPressed: widget.actionRunning ? null : widget.onCheckout,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  final TagEntryData tag;
  final AppTokens tokens;
  final bool hovered;
  final bool actionRunning;
  final ValueChanged<bool> onHoverChange;
  final VoidCallback onDelete;
  const _TagCard(
      {required this.tag,
      required this.tokens,
      required this.hovered,
      required this.actionRunning,
      required this.onHoverChange,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return MouseRegion(
      onEnter: (_) => onHoverChange(true),
      onExit: (_) => onHoverChange(false),
      child: AnimatedContainer(
        duration: context.motion(const Duration(milliseconds: 80)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius:
              BorderRadius.circular(context.surfaceShader.geometry.radius),
          border: Border.all(color: t.chromeBorder.withOpacity(0.08)),
        ),
        child: Row(children: [
          AppIcon(name: 'tag', size: 12, color: t.textMuted),
          const SizedBox(width: 8),
          Expanded(
              child: Row(children: [
            Flexible(
              child: Text(
                tag.name,
                style: TextStyle(color: t.textNormal, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tag.targetHash != null) ...[
              const SizedBox(width: 8),
              Text(
                tag.targetHash!,
                style: TextStyle(
                    color: t.textMuted.withOpacity(0.7),
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono'),
              ),
            ],
            if (tag.tagType == 'annotated') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: t.accentBright.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('annotated',
                    style: TextStyle(
                        color: t.accentBright,
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ])),
          if (hovered)
            GestureDetector(
              onTap: actionRunning ? null : onDelete,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('✕',
                    style: TextStyle(
                        color: t.textMuted.withOpacity(0.6), fontSize: 10)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ChromeButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final bool compact;
  final VoidCallback? onPressed;

  const _ChromeButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.compact = false,
  });

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
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
        onTap: widget.enabled ? widget.onPressed : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: AnimatedScale(
            duration: context.motion(const Duration(milliseconds: 80)),
            scale: chrome.scale,
            child: AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 80)),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 12,
                vertical: widget.compact ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: chrome.background,
                gradient: chrome.gradient,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: chrome.borderColor),
                boxShadow: chrome.shadows,
              ),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: chrome.offset,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: t.btnText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchIconAction extends StatefulWidget {
  final String icon;
  final bool enabled;
  final VoidCallback onTap;

  const _BranchIconAction({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BranchIconAction> createState() => _BranchIconActionState();
}

class _BranchIconActionState extends State<_BranchIconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 80)),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered
                ? t.stateConflicted.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _hovered
                  ? t.stateConflicted.withOpacity(0.16)
                  : Colors.transparent,
            ),
          ),
          child: Center(
            child: AppIcon(
              name: widget.icon,
              size: 12,
              color: widget.enabled ? t.stateConflicted : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
