import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/control_chrome.dart';
import '../../ui/form_controls.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../app/repository_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../diff/diff_shell.dart';

class ChangesPage extends StatefulWidget {
  const ChangesPage({super.key});
  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  final Set<String> _selected = {};
  String? _selectedDiffPath;
  String? _visibleDiffPath;
  String? _diffContent;
  bool _diffLoading = false;
  String? _diffError;
  final _commitMsgCtrl = TextEditingController();
  bool _actionRunning = false;
  String? _actionMessage;
  String? _actionError;

  // Drag-to-select state
  final _listScrollCtrl = ScrollController();
  String? _dragCandidatePath;
  Offset? _dragCandidatePoint;
  bool _isDragging = false;
  bool? _dragSelectMode; // true = select, false = deselect
  final Set<String> _dragVisited = {};
  static const double _kItemH = 42.0; // approximate row height
  static const double _kListPaddingH = 8.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'changes.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
    });
  }

  @override
  void dispose() {
    _commitMsgCtrl.dispose();
    _listScrollCtrl.dispose();
    super.dispose();
  }

  bool _isDirty(String s) => s.isNotEmpty && s.trim().isNotEmpty;

  void _applyDragSelection(String path, bool select) {
    setState(() {
      if (select) {
        _selected.add(path);
      } else {
        _selected.remove(path);
      }
    });
  }

  void _onDragPointerDown(String path, PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryButton) == 0) {
      _onDragPointerUp();
      return;
    }
    _dragCandidatePath = path;
    _dragCandidatePoint = event.localPosition;
    _isDragging = false;
    _dragSelectMode = null;
    _dragVisited.clear();
  }

  void _onDragPointerMove(Offset pos, List<RepositoryStatusFile> files) {
    if (_dragCandidatePath == null || _dragCandidatePoint == null) return;
    final dx = (pos.dx - _dragCandidatePoint!.dx).abs();
    final dy = (pos.dy - _dragCandidatePoint!.dy).abs();
    if (!_isDragging && (dx >= 4 || dy >= 4)) {
      _isDragging = true;
      _dragSelectMode = !_selected.contains(_dragCandidatePath!);
      _dragVisited.add(_dragCandidatePath!);
      _applyDragSelection(_dragCandidatePath!, _dragSelectMode!);
    }
    if (!_isDragging) return;

    // Determine which item is under the pointer using the scroll controller
    final scrollOff = _listScrollCtrl.hasClients ? _listScrollCtrl.offset : 0.0;
    // pos.dy is in the local coord of the Listener (the Expanded list area)
    final virtualY = pos.dy + scrollOff - _kListPaddingH;
    final idx = (virtualY / _kItemH).floor();
    if (idx >= 0 && idx < files.length) {
      final path = files[idx].path;
      if (!_dragVisited.contains(path)) {
        _dragVisited.add(path);
        _applyDragSelection(path, _dragSelectMode!);
      }
    }
  }

  void _onDragPointerUp() {
    _dragCandidatePath = null;
    _dragCandidatePoint = null;
    _isDragging = false;
    _dragSelectMode = null;
    _dragVisited.clear();
  }

  Future<void> _loadDiff(String repo, String path) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _selectedDiffPath = path;
      _diffLoading = true;
      _diffError = null;
    });
    final r = await getFileDiff(repo, path);
    if (!mounted) return;
    if (_selectedDiffPath != path) return;
    setState(() {
      _diffLoading = false;
      if (r.ok) {
        _visibleDiffPath = path;
        _diffContent = r.data;
      } else {
        _diffError = r.error;
      }
    });
    stopwatch.stop();
    await DiagnosticsState.instance.recordUiTiming(
      event: 'changes.diff.load',
      phase: 'interaction',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      ok: r.ok,
      errorCode: r.ok ? null : 'diff.load_failed',
    );
  }

  Future<void> _stage(String repo) async {
    if (_selected.isEmpty) return;
    setState(() {
      _actionRunning = true;
      _actionError = null;
      _actionMessage = null;
    });
    final r = await stagePaths(repo, _selected.toList());
    if (!mounted) return;
    setState(() {
      _actionRunning = false;
      if (r.ok) {
        _actionMessage = 'Staged ${_selected.length} path(s).';
        _selected.clear();
      } else {
        _actionError = r.error;
      }
    });
    await context.read<RepositoryState>().refreshStatus();
  }

  Future<void> _unstage(String repo) async {
    if (_selected.isEmpty) return;
    setState(() {
      _actionRunning = true;
      _actionError = null;
      _actionMessage = null;
    });
    final r = await unstagePaths(repo, _selected.toList());
    if (!mounted) return;
    setState(() {
      _actionRunning = false;
      if (r.ok) {
        _actionMessage = 'Unstaged ${_selected.length} path(s).';
        _selected.clear();
      } else {
        _actionError = r.error;
      }
    });
    await context.read<RepositoryState>().refreshStatus();
  }

  Future<void> _commit(String repo, String branch) async {
    final msg = _commitMsgCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() {
      _actionRunning = true;
      _actionError = null;
      _actionMessage = null;
    });
    final r = await createCommit(repo, msg);
    if (!mounted) return;
    setState(() {
      _actionRunning = false;
      if (r.ok) {
        final d = r.data!;
        final shortHash = d.commitHash.length >= 8
            ? d.commitHash.substring(0, 8)
            : d.commitHash;
        _actionMessage = '${d.summary} ($shortHash)';
        _commitMsgCtrl.clear();
      } else {
        _actionError = r.error;
      }
    });
    await context.read<RepositoryState>().refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repo = context.watch<RepositoryState>();
    final repoPath = repo.activePath;
    final status = repo.status;

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }
    if (repo.statusError != null) {
      return AppStatusView.error(
        title: 'Repository status unavailable',
        message: repo.statusError!,
      );
    }
    if (status == null) {
      return const AppStatusView.loading(
        title: 'Loading repository status',
        message: 'Reading the working tree.',
      );
    }
    if (status.files.isEmpty) {
      return const AppStatusView(
        title: 'Working tree clean',
        message: 'No staged or unstaged changes detected.',
      );
    }

    final stagedCount = status.files.where((f) => _isDirty(f.staged)).length;
    final unstagedCount =
        status.files.where((f) => _isDirty(f.unstaged)).length;

    return Stack(children: [
      Row(children: [
        // Left panel — file list
        MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: 0,
          border: Border(
            right: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
          ),
          elevated: false,
          width: 280,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(children: [
                Text('Changes',
                    style: TextStyle(
                        color: t.textStrong,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.04)),
                const SizedBox(width: 8),
                _StatusChip(label: '$stagedCount S', color: t.stateStaged),
                const SizedBox(width: 4),
                _StatusChip(label: '$unstagedCount U', color: t.stateDeleted),
              ]),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                Expanded(
                    child: _ActionBtn(
                        label: 'Stage',
                        t: t,
                        enabled: _selected.isNotEmpty && !_actionRunning,
                        onTap: () => _stage(repoPath))),
                const SizedBox(width: 4),
                Expanded(
                    child: _ActionBtn(
                        label: 'Unstage',
                        t: t,
                        enabled: _selected.isNotEmpty && !_actionRunning,
                        onTap: () => _unstage(repoPath))),
              ]),
            ),
            // File list
            Expanded(
              child: Listener(
                onPointerMove: (e) =>
                    _onDragPointerMove(e.localPosition, status.files),
                onPointerUp: (_) => _onDragPointerUp(),
                onPointerCancel: (_) => _onDragPointerUp(),
                child: ListView.builder(
                  controller: _listScrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: status.files.length,
                  itemBuilder: (ctx, i) {
                    final file = status.files[i];
                    final isSelected = _selectedDiffPath == file.path;
                    final isChecked = _selected.contains(file.path);
                    return _FileRow(
                      file: file,
                      tokens: t,
                      isSelected: isSelected,
                      isChecked: isChecked,
                      onTap: () => _loadDiff(repoPath, file.path),
                      onCheck: (v) => setState(() {
                        if (v)
                          _selected.add(file.path);
                        else
                          _selected.remove(file.path);
                      }),
                      onPointerDown: (event) =>
                          _onDragPointerDown(file.path, event),
                    );
                  },
                ),
              ),
            ),
            // Commit footer
            MaterialSurface(
              tone: AppMaterialTone.surface0,
              radius: 0,
              border: Border(
                top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
              ),
              elevated: false,
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        (HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed)) {
                      _commit(repoPath, status.branch);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AppTextField(
                    controller: _commitMsgCtrl,
                    height: 34,
                    fontSize: 12,
                    hintText: 'Commit message...',
                    onSubmitted: (_) => _commit(repoPath, status.branch),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: _ActionBtn(
                    label: _actionRunning
                        ? 'Committing...'
                        : 'Commit to ${status.branch}',
                    t: t,
                    enabled: !_actionRunning,
                    onTap: () => _commit(repoPath, status.branch),
                  ),
                ),
                if (_actionMessage != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_actionMessage!,
                          style: TextStyle(color: t.stateAdded, fontSize: 10))),
                if (_actionError != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_actionError!,
                          style: TextStyle(
                              color: t.stateConflicted, fontSize: 10))),
              ]),
            ),
          ]),
        ),

        // Right panel — diff
        Expanded(
          child: MaterialSurface(
            tone: AppMaterialTone.surface0,
            radius: 0,
            borderAlpha: 0,
            elevated: false,
            child: _selectedDiffPath == null
                ? const AppStatusView(
                    title: 'No file selected',
                    message: 'Select a changed file to inspect its diff.',
                    compact: true,
                  )
                : DiffShell(
                    key: ValueKey(_visibleDiffPath ?? _selectedDiffPath!),
                    filePath: _visibleDiffPath ?? _selectedDiffPath!,
                    diffContent: _diffContent,
                    loading: _diffLoading,
                    error: _diffError,
                    tokens: t,
                    repositoryPath: repoPath,
                  ),
          ),
        ),
      ]),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedOpacity(
          opacity: repo.statusLoading ? 1 : 0,
          duration: const Duration(milliseconds: 80),
          child: TopProgressLine(color: t.accentBright),
        ),
      ),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4)),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.t,
      required this.enabled,
      required this.onTap});
  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 24,
          decoration: BoxDecoration(
            color: chrome.background,
            gradient: chrome.gradient,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: chrome.borderColor),
            boxShadow: chrome.shadows,
          ),
          child: Transform.translate(
            offset: chrome.offset,
            child: Center(
                child: Text(widget.label,
                    style: TextStyle(
                        color: widget.enabled ? t.btnText : t.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final RepositoryStatusFile file;
  final AppTokens tokens;
  final bool isSelected;
  final bool isChecked;
  final VoidCallback onTap;
  final ValueChanged<bool> onCheck;
  final ValueChanged<PointerDownEvent>? onPointerDown;
  const _FileRow(
      {required this.file,
      required this.tokens,
      required this.isSelected,
      required this.isChecked,
      required this.onTap,
      required this.onCheck,
      this.onPointerDown});
  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final f = widget.file;
    final filename = f.path.split('/').last;
    final dir = f.path.contains('/')
        ? f.path.substring(0, f.path.lastIndexOf('/'))
        : '';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: widget.onPointerDown != null
            ? (e) => widget.onPointerDown!(e)
            : null,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? t.chromeBorder.withValues(alpha: 0.10)
                  : (_hovered ? t.itemHoverBg : Colors.transparent),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: widget.isChecked,
                  onChanged: (v) => widget.onCheck(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: t.accentBright,
                  checkColor: t.bg0,
                  side: BorderSide(color: t.chromeBorder.withOpacity(0.5)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(filename,
                          style: TextStyle(color: t.textNormal, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                      if (dir.isNotEmpty)
                        Text(dir,
                            style: TextStyle(
                                color: t.textMuted,
                                fontSize: 10,
                                fontFamily: 'JetBrainsMono'),
                            overflow: TextOverflow.ellipsis),
                    ]),
              ),
              if (f.staged.isNotEmpty)
                _StatusBadge(label: 'S', color: t.stateStaged),
              if (f.unstaged.isNotEmpty) ...[
                const SizedBox(width: 4),
                _StatusBadge(label: 'U', color: t.stateDeleted),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10),
          ],
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w900))),
      );
}
