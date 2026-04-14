import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/animated_icons.dart';
import '../../ui/context_menu.dart';
import '../../ui/control_chrome.dart';
import '../../ui/material_surface.dart';
import '../../ui/morph_text.dart';
import '../../ui/status_view.dart';
import '../../ui/resonance_text.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/ai.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../backend/file_coupling.dart';
import '../../backend/logos_git.dart';
import '../../app/ai_settings_state.dart';
import '../../app/file_coupling_state.dart';
import '../../app/logos_git_state.dart';
import '../../app/preferences_state.dart';
import '../../app/repository_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../branches/branches_page.dart' show showPatchPreviewDialog;
import '../diff/diff_shell.dart';
import '../diff/diff_models.dart';

String _guardrailLabelForStage(int stage) {
  switch (stage.clamp(0, 3)) {
    case 0:
      return 'Loose';
    case 1:
      return 'Balanced';
    case 2:
      return 'Strict';
    default:
      return 'Paranoid';
  }
}

enum _CommitRunMode { commitOnly, commitAndSync }

class _PrimaryCommitAction {
  final String label;
  final String detail;
  final bool syncAfterCommit;

  const _PrimaryCommitAction({
    required this.label,
    required this.detail,
    required this.syncAfterCommit,
  });
}

class ChangesPage extends StatefulWidget {
  const ChangesPage({super.key});
  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  final Set<String> _includedPaths = {};
  final _commitMsgCtrl = TextEditingController();
  final _commitMsgFocusNode = FocusNode();

  String? _draftKey;
  String? _selectedDiffPath;
  String? _inspectionDiffPath;
  String? _visibleDiffPath;
  String? _diffContent;
  bool _diffLoading = false;
  String? _diffError;
  String? _multiDiffScopeKey;
  String? _multiDiffContent;
  bool _multiDiffLoading = false;
  String? _multiDiffError;
  List<_CombinedDiffSection> _multiDiffSections = const [];
  String? _multiDiffCurrentPath;
  int? _multiDiffJumpLineIndex;
  int _multiDiffJumpRequestId = 0;
  // True while the user is actively driving the diff scroll (drag, wheel,
  // ballistic fling). Programmatic animations (jump-to-section) do NOT set
  // this, so the timeline dot tracks user intent and never flickers back
  // to the previous section during an animated jump.
  bool _multiDiffUserDriving = false;
  bool _actionRunning = false;
  bool _generateRunning = false;
  bool _generateSuccess = false;
  bool _reviewRunning = false;
  bool _reviewSuccess = false;
  bool _commitAiLoading = false;
  String? _commitAiError;
  List<AiModelCategoryData> _commitAiCategories = const [];
  bool _reviewActive = false;
  bool _reviewTraceExpanded = false;
  bool _reviewReasoningExpanded = false;
  String? _reviewScopeKey;
  AiCommitReviewData? _reviewResult;
  String? _reviewError;
  // ── Muse (3-phase oracle) state — mirrors review's pattern.
  bool _museRunning = false;
  bool _museSuccess = false;
  bool _museActive = false;
  String? _museScopeKey;
  AiMuseData? _museResult;
  String? _museError;
  String? _actionMessage;
  String? _actionError;
  double _leftPanelWidth = 320.0;
  static const _minLeftPanelWidth = 220.0;
  static const _maxLeftPanelWidth = 520.0;
  bool _commitOnlyMode = false;
  bool _mergeResolving = false;
  bool _shaping = false;
  // Inline shape-commit mode. When true, the composer field swaps to
  // bind the shape controller (preserving the commit draft in the
  // background) and the bottom split-button morphs into "ask with [cat]"
  // with a chevron that cycles AI categories on each click.
  bool _shapeMode = false;
  final TextEditingController _shapeCtrl = TextEditingController();
  final FocusNode _shapeFocus = FocusNode();
  int _shapeCategoryIndex = 0;
  Timer? _commitDraftSaveDebounce;
  String? _lastDraftRepoPath;
  String? _lastDraftBranch;

  // Coupling rail — path under the mouse right now. Drives live peer
  // highlighting so moving the cursor along the rail visualizes which
  // files are most tightly coupled to the currently-hovered one.
  String? _railHoverPath;

  // Per-path line churn (adds + dels) feeding the "by impact" sort.
  // Refreshed whenever the status signature changes. Empty until the
  // first fetch lands; until then impact-sort tiebreaks alphabetically.
  Map<String, FileChangeWeight> _changeWeights = const {};
  String? _weightsFetchedForKey;

  // Filing cabinet (stashes)
  List<StashEntryData> _stashes = const [];
  bool _stashesLoading = false;
  bool _stashesExpanded = false;
  bool _stashExpandedInitialized = false;
  String? _stashPeekDiff;
  // Per-stash expanded state (keyed by stash.index) — the filing-cabinet
  // divider. Independent of the list-level _stashesExpanded toggle.
  final Set<int> _stashOpenIndices = {};
  // Lazy-loaded file list per stash (index → files). Populated on first
  // expand; dropped when the stash list is reloaded.
  final Map<int, List<StashFileStat>> _stashFiles = {};
  final Set<int> _stashFilesLoading = {};

  // Coupling-matrix loader guard: tracks "I kicked off a compute for this
  // repo in this session" so we don't spam the provider on every rebuild.
  String? _couplingKickedOffFor;
  int? _stashPeekIndex;

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
      _refreshCommitAiConfig();
      unawaited(context.read<AiSettingsState>().refreshProviders());
    });
  }

  /// Resolve the git directory for a repo. Handles worktrees and submodules
  /// where `.git` may be a file rather than a directory.
  Future<String?> _resolveGitDir(String repoPath) async {
    try {
      final result = await Process.run(
        'git', ['rev-parse', '--git-dir'],
        workingDirectory: repoPath,
      );
      if (result.exitCode == 0) {
        final gitDir = (result.stdout as String).trim();
        // rev-parse returns relative or absolute — normalize.
        return p.isAbsolute(gitDir) ? gitDir : p.join(repoPath, gitDir);
      }
    } catch (_) {}
    // Fallback to the common case.
    return p.join(repoPath, '.git');
  }

  File _draftFile(String gitDir, [String? branch]) {
    if (branch == null || branch.isEmpty) {
      return File(p.join(gitDir, 'MANIFOLD_COMMIT_MSG'));
    }
    // Sanitize branch name for use as a filename suffix.
    final safe = branch.replaceAll(RegExp(r'[^\w.-]'), '_');
    return File(p.join(gitDir, 'MANIFOLD_COMMIT_MSG_$safe'));
  }

  void _loadCommitDraft() {
    final repoState = context.read<RepositoryState>();
    final repoPath = repoState.activePath;
    if (repoPath == null) return;
    _lastDraftRepoPath = repoPath;
    _lastDraftBranch = repoState.status?.branch;
    _loadCommitDraftForRepo(repoPath, branch: _lastDraftBranch);
  }

  Future<void> _loadCommitDraftForRepo(String repoPath, {String? branch, bool force = false}) async {
    try {
      final gitDir = await _resolveGitDir(repoPath);
      if (gitDir == null) return;
      final file = _draftFile(gitDir, branch);
      if (await file.exists()) {
        final draft = await file.readAsString();
        if (mounted && (force || _commitMsgCtrl.text.isEmpty)) {
          _commitMsgCtrl.text = draft;
        }
      } else if (force && mounted) {
        _commitMsgCtrl.clear();
      }
    } catch (_) {}
  }

  void _saveCommitDraft(String value) {
    _commitDraftSaveDebounce?.cancel();
    // Capture repo path and branch NOW, not when the timer fires — prevents
    // saving to the wrong repo/branch after a switch.
    final capturedRepoPath = _lastDraftRepoPath;
    final capturedBranch = _lastDraftBranch;
    _commitDraftSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final repoPath = capturedRepoPath ?? context.read<RepositoryState>().activePath;
        if (repoPath == null) return;
        final gitDir = await _resolveGitDir(repoPath);
        if (gitDir == null) return;
        final file = _draftFile(gitDir, capturedBranch);
        if (value.trim().isEmpty) {
          if (await file.exists()) await file.delete();
        } else {
          await file.writeAsString(value);
        }
      } catch (_) {}
    });
  }

  Future<void> _clearCommitDraft() async {
    try {
      final repoPath = _lastDraftRepoPath ?? context.read<RepositoryState>().activePath;
      if (repoPath == null) return;
      final gitDir = await _resolveGitDir(repoPath);
      if (gitDir == null) return;
      final file = _draftFile(gitDir, _lastDraftBranch);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Immediately write a draft to disk — no debounce. Used on branch/repo
  /// switch and app lifecycle transitions to avoid losing in-progress text.
  Future<void> _flushDraft(String repoPath, String? branch, String value) async {
    try {
      final gitDir = await _resolveGitDir(repoPath);
      if (gitDir == null) return;
      final file = _draftFile(gitDir, branch);
      if (value.trim().isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(value);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _commitDraftSaveDebounce?.cancel();
    // Flush on dispose so closing the app doesn't lose the draft.
    final repo = _lastDraftRepoPath;
    final branch = _lastDraftBranch;
    final text = _commitMsgCtrl.text;
    if (repo != null && text.trim().isNotEmpty) {
      _flushDraft(repo, branch, text);
    }
    _commitMsgCtrl.dispose();
    _commitMsgFocusNode.dispose();
    _shapeCtrl.dispose();
    _shapeFocus.dispose();
    super.dispose();
  }

  /// Returns the AI categories the user has configured at least one
  /// model for. Used to drive the chevron-cycle on the shape ask
  /// button. Order is stable (insertion order from the prefs map).
  List<String> _shapeCategories(AiSettingsState ai) => ai.modelSelections.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => e.key)
      .toList(growable: false);

  /// Toggles inline shape-commit mode. Focus follows the active field.
  void _toggleShapeMode() {
    setState(() => _shapeMode = !_shapeMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_shapeMode ? _shapeFocus : _commitMsgFocusNode).requestFocus();
    });
  }

  bool _isDirty(String s) => s.trim().isNotEmpty;

  String _buildDraftKey(RepositoryStatus status) {
    final files = status.files
        .map((file) => '${file.path}|${file.staged}|${file.unstaged}')
        .join('||');
    return '${status.branch}|${status.upstream}|$files';
  }

  void _syncDraftFromStatus(RepositoryStatus status) {
    final nextKey = _buildDraftKey(status);
    if (_draftKey == nextKey) {
      return;
    }
    _draftKey = nextKey;
    final staged = status.files
        .where((file) => _isDirty(file.staged))
        .map((file) => file.path)
        .toSet();
    _includedPaths
      ..clear()
      ..addAll(
          staged.isNotEmpty ? staged : status.files.map((file) => file.path));
    _clearReviewState();
  }

  void _clearReviewState() {
    _reviewRunning = false;
    _reviewSuccess = false;
    _reviewActive = false;
    _reviewTraceExpanded = false;
    _reviewReasoningExpanded = false;
    _reviewScopeKey = null;
    _reviewResult = null;
    _reviewError = null;
    _museRunning = false;
    _museSuccess = false;
    _museActive = false;
    _museScopeKey = null;
    _museResult = null;
    _museError = null;
  }

  void _hideReviewPane() {
    _reviewActive = false;
  }

  void _cancelReviewRequest() {
    setState(() {
      _reviewRunning = false;
      _reviewSuccess = false;
      _reviewActive = false;
      _reviewScopeKey = null;
      _reviewError = null;
      _reviewResult = null;
      _reviewTraceExpanded = false;
      _reviewReasoningExpanded = false;
    });
  }

  int _includedDirtyCount(RepositoryStatus status) {
    return status.files
        .where((file) => _includedPaths.contains(file.path))
        .length;
  }

  List<String> _stagedExcludedPaths(RepositoryStatus status) {
    return status.files
        .where(
          (file) =>
              !_includedPaths.contains(file.path) && _isDirty(file.staged),
        )
        .map((file) => file.path)
        .toList();
  }

  _PrimaryCommitAction _primaryActionFor(RepositoryStatus status) {
    final branch = status.branch;
    if (branch == 'HEAD' || branch.startsWith('(')) {
      return const _PrimaryCommitAction(
        label: 'Commit changes',
        detail: 'Detached HEAD: commit locally without syncing.',
        syncAfterCommit: false,
      );
    }
    if (status.upstream == null) {
      return const _PrimaryCommitAction(
        label: 'Commit & publish',
        detail: 'Create the commit and publish this branch in one step.',
        syncAfterCommit: true,
      );
    }
    if (status.ahead > 0 || status.behind > 0) {
      return const _PrimaryCommitAction(
        label: 'Commit & sync',
        detail: 'Create the commit, then reconcile and ship the branch.',
        syncAfterCommit: true,
      );
    }
    return const _PrimaryCommitAction(
      label: 'Commit & push',
      detail: 'Create the commit and push it immediately.',
      syncAfterCommit: true,
    );
  }

  Future<void> _loadDiff(String repo, String path) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _hideReviewPane();
      _selectedDiffPath = path;
      _diffLoading = true;
      _diffError = null;
    });
    final r = await getFileDiff(repo, path);
    if (!mounted || _selectedDiffPath != path) {
      return;
    }
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

  void _inspectSingleDiff(String repo, String path) {
    setState(() {
      _hideReviewPane();
      _inspectionDiffPath = path;
    });
    unawaited(_loadDiff(repo, path));
  }

  String _buildMultiDiffScopeKey(List<RepositoryStatusFile> files) {
    return files
        .map((file) => '${file.path}|${file.staged}|${file.unstaged}')
        .join('||');
  }

  Future<void> _loadMultiDiff(
    String repo,
    List<RepositoryStatusFile> files,
  ) async {
    final requestFiles = List<RepositoryStatusFile>.from(files);
    final scopeKey = _buildMultiDiffScopeKey(requestFiles);
    setState(() {
      _multiDiffScopeKey = scopeKey;
      _multiDiffLoading = true;
      _multiDiffError = null;
      _multiDiffSections = const [];
      _multiDiffCurrentPath =
          requestFiles.isEmpty ? null : requestFiles.first.path;
    });

    final result = await getSelectionDiff(repo, requestFiles);
    if (!mounted || _multiDiffScopeKey != scopeKey) {
      return;
    }

    setState(() {
      _multiDiffLoading = false;
      if (result.ok) {
        _multiDiffContent = result.data;
        _multiDiffError = null;
        _multiDiffSections = _parseCombinedDiffSections(result.data ?? '');
        _multiDiffCurrentPath = _multiDiffSections.isNotEmpty
            ? _multiDiffSections.first.path
            : (requestFiles.isEmpty ? null : requestFiles.first.path);
        _multiDiffJumpLineIndex = _multiDiffSections.isNotEmpty
            ? _multiDiffSections.first.startLine
            : 0;
        _multiDiffJumpRequestId++;
      } else {
        _multiDiffContent = null;
        _multiDiffError = result.error;
        _multiDiffSections = const [];
        _multiDiffCurrentPath = null;
        _multiDiffJumpLineIndex = null;
      }
    });
  }

  void _primeMultiDiff(
    String repo,
    List<RepositoryStatusFile> files,
  ) {
    final scopeKey = _buildMultiDiffScopeKey(files);
    if (_multiDiffLoading && _multiDiffScopeKey == scopeKey) {
      return;
    }
    if (_multiDiffScopeKey == scopeKey &&
        (_multiDiffContent != null || _multiDiffError != null)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_loadMultiDiff(repo, files));
    });
  }

  void _handleMultiDiffScroll(ScrollMetrics metrics) {
    if (_multiDiffSections.isEmpty) {
      return;
    }
    final probeOffset = metrics.pixels + (metrics.viewportDimension * 0.2);
    final lineIndex = (probeOffset / 18).floor().clamp(0, 1 << 20);
    var current = _multiDiffSections.first;
    for (final section in _multiDiffSections) {
      if (section.startLine <= lineIndex) {
        current = section;
      } else {
        break;
      }
    }
    if (current.path == _multiDiffCurrentPath) {
      return;
    }
    setState(() {
      _multiDiffCurrentPath = current.path;
    });
  }

  void _jumpToMultiDiffPath(String path, {int? fallbackStartLine}) {
    final targetSection =
        _multiDiffSections.where((section) => section.path == path).firstOrNull;
    setState(() {
      _hideReviewPane();
      _inspectionDiffPath = null;
      _selectedDiffPath = null;
      _multiDiffCurrentPath = path;
      final jumpLine = targetSection?.startLine ?? fallbackStartLine;
      if (jumpLine != null) {
        _multiDiffJumpLineIndex = jumpLine;
        _multiDiffJumpRequestId++;
      }
    });
  }

  void _toggleIncluded(String path, bool include) {
    setState(() {
      _clearReviewState();
      if (include) {
        _includedPaths.add(path);
      } else {
        _includedPaths.remove(path);
      }
      _actionError = null;
      _actionMessage = null;
    });
  }

  /// Show the per-file right-click menu, anchored at [globalPos]. Four
  /// sections: discard, ignore, copy, reveal. Click outside or
  /// right-click elsewhere to dismiss.
  void _showFileContextMenu(
    BuildContext context,
    Offset globalPos,
    RepositoryStatusFile file,
    String repoPath,
  ) {
    final isUntracked = file.staged.isEmpty && file.unstaged == '?';
    final ext = _fileExtension(file.path);
    final sections = <List<AppContextMenuItem>>[
      [
        AppContextMenuItem(
          icon: isUntracked
              ? Icons.delete_outline
              : Icons.history_outlined,
          label: isUntracked ? 'Delete file…' : 'Discard changes…',
          destructive: true,
          onTap: () => _confirmDiscardFile(context, file, repoPath),
        ),
      ],
      [
        AppContextMenuItem(
          icon: Icons.block_outlined,
          label: 'Ignore file (add to .gitignore)',
          onTap: () => _ignorePattern(context, repoPath, file.path),
        ),
        if (ext != null)
          AppContextMenuItem(
            icon: Icons.block_outlined,
            label: 'Ignore all .$ext files (add to .gitignore)',
            onTap: () => _ignorePattern(context, repoPath, '*.$ext'),
          ),
      ],
      [
        AppContextMenuItem(
          icon: Icons.content_copy_outlined,
          label: 'Copy file path',
          onTap: () => _copyToClipboard(file.path),
        ),
      ],
      [
        AppContextMenuItem(
          icon: Icons.folder_open_outlined,
          label: 'Show in Explorer',
          onTap: () => _revealInExplorer(repoPath, file.path),
        ),
      ],
    ];
    showAppContextMenu(context, globalPos, sections);
  }

  /// File extension *without* the leading dot, or null when the path
  /// has none (e.g. `Makefile`, `.env`). Used to decide whether the
  /// "Ignore all .ext files" row is meaningful.
  String? _fileExtension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return null;
    return name.substring(i + 1);
  }

  /// Append [pattern] to the repo's `.gitignore` then refresh the
  /// changes list (an untracked file matched by the pattern will
  /// disappear immediately). Errors surface via [_actionError].
  Future<void> _ignorePattern(
    BuildContext context,
    String repoPath,
    String pattern,
  ) async {
    final repoState = context.read<RepositoryState>();
    final result = await addToGitignore(repoPath, pattern);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _actionError = result.error ?? 'Failed to update .gitignore.';
        _actionMessage = null;
      });
      return;
    }
    await repoState.refreshStatus();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Open the OS file explorer with the file selected. Windows: invoke
  /// `explorer.exe /select,<path>`. macOS: `open -R <path>`. Linux:
  /// `xdg-open <dir>` (no per-file selection in standard xdg-open).
  Future<void> _revealInExplorer(String repoPath, String relPath) async {
    final absPath = '$repoPath${Platform.pathSeparator}'
        '${relPath.replaceAll('/', Platform.pathSeparator)}';
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', ['/select,$absPath']);
      } else if (Platform.isMacOS) {
        await Process.start('open', ['-R', absPath]);
      } else {
        // Linux best-effort: open the containing folder.
        final dir =
            absPath.substring(0, absPath.lastIndexOf(Platform.pathSeparator));
        await Process.start('xdg-open', [dir]);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionError = 'Failed to open file explorer: $e';
        _actionMessage = null;
      });
    }
  }

  /// Centred confirm dialog before invoking [discardFile]. Two
  /// outcomes: cancel (no-op) or confirm (runs the git op + refreshes
  /// the status panel; surfaces errors via [_actionError]).
  Future<void> _confirmDiscardFile(
    BuildContext context,
    RepositoryStatusFile file,
    String repoPath,
  ) async {
    // Capture the RepositoryState reference before any await so we
    // don't have to revisit `context` after async gaps. The `mounted`
    // checks below still gate the setState calls.
    final repoState = context.read<RepositoryState>();
    final isUntracked = file.staged.isEmpty && file.unstaged == '?';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = ctx.tokens;
        return AlertDialog(
          backgroundColor: t.surface1,
          title: Text(
            isUntracked ? 'Delete file?' : 'Discard changes?',
            style: TextStyle(color: t.textStrong, fontSize: 14),
          ),
          content: Text(
            isUntracked
                ? '${file.path} will be removed from disk. '
                    'This cannot be undone from inside the app.'
                : 'All changes to ${file.path} will be reverted to '
                    'their state in HEAD. This cannot be undone.',
            style: TextStyle(color: t.textNormal, fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: t.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                isUntracked ? 'Delete' : 'Discard',
                style: TextStyle(color: t.stateDeleted),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final result = await discardFile(repoPath, file);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _actionError = result.error ?? 'Failed to discard changes.';
        _actionMessage = null;
      });
      return;
    }
    setState(() {
      _includedPaths.remove(file.path);
      _actionError = null;
      _actionMessage = null;
    });
    await repoState.refreshStatus();
  }

  void _includeAll(RepositoryStatus status) {
    setState(() {
      _clearReviewState();
      _includedPaths
        ..clear()
        ..addAll(status.files.map((file) => file.path));
      _actionError = null;
      _actionMessage = null;
    });
  }

  void _includeOnlyStaged(RepositoryStatus status) {
    final staged = status.files
        .where((file) => _isDirty(file.staged))
        .map((file) => file.path)
        .toSet();
    setState(() {
      _clearReviewState();
      _includedPaths
        ..clear()
        ..addAll(staged);
      _actionError = null;
      _actionMessage = null;
    });
  }

  Future<RepositoryStatus?> _refreshAndReadStatus() async {
    final repo = context.read<RepositoryState>();
    await repo.refreshStatus();
    return repo.status;
  }

  bool _hasCommitAiSelection(AiSettingsState aiSettings) {
    for (final category in _commitAiCategories) {
      if (category.models.isEmpty) {
        continue;
      }
      if (category.id == aiSettings.commitMessageModelCategoryId) {
        return true;
      }
    }
    return _commitAiCategories.any((category) => category.models.isNotEmpty);
  }

  bool _hasReviewAiSelection(AiSettingsState aiSettings) {
    for (final category in _commitAiCategories) {
      if (category.models.isEmpty) {
        continue;
      }
      if (category.id == aiSettings.reviewCommitModelCategoryId) {
        return true;
      }
    }
    return _commitAiCategories.any((category) => category.models.isNotEmpty);
  }

  String _commitAiTooltip(AiSettingsState aiSettings, int includedCount) {
    if (_generateRunning) {
      return 'Generating commit message...';
    }
    if (_commitAiLoading) {
      return 'Preparing commit-message AI...';
    }
    if (includedCount == 0) {
      return 'Select at least one file to generate a commit message.';
    }
    if (!_hasCommitAiSelection(aiSettings)) {
      return _commitAiError ??
          'Configure commit-message AI in Settings > Behavioural Dynamics > Commit Messages.';
    }
    // The second category is "Fast" — the typical default for commit gen.
    final commitLabel = aiSettings.labelForCategory(
      aiSettings.commitMessageModelCategoryId,
      _commitAiCategories.length > 1 ? _commitAiCategories[1].label : 'fast',
    ).toLowerCase();
    return 'generate commit message with $commitLabel model';
  }

  String _museTooltip(AiSettingsState aiSettings, int includedCount) {
    if (_museRunning) return _museActive ? 'consulting the muse...' : 'show muse';
    if (includedCount == 0) return 'select at least one file for the muse.';
    if (_museResult != null) return 'show muse';
    if (_museError != null) return 'show muse error';
    // Resolve the actual slots the pipeline will use and render their
    // current display labels — if the user renamed "Fast" to "Cheapo
    // Spew", the tooltip follows. Routing keys off the tag id under the
    // hood; what we show here is the human-facing name. Fallbacks are
    // positional, not name-based, so any custom categories scale in.
    String? labelOf(String preferredId) {
      final cat = _commitAiCategories
              .where((c) => c.id == preferredId && c.models.isNotEmpty)
              .firstOrNull ??
          _commitAiCategories
              .where((c) => c.models.isNotEmpty)
              .firstOrNull;
      if (cat == null) return null;
      return aiSettings.labelForCategory(cat.id, cat.label).toLowerCase();
    }

    final brainstormLabel =
        labelOf(aiSettings.museBrainstormModelCategoryId);
    final synthesisLabel =
        labelOf(aiSettings.museSynthesisModelCategoryId);
    if (brainstormLabel == null || synthesisLabel == null) {
      return 'ask the muse for direction';
    }
    return 'ask the muse for direction\n$brainstormLabel → $synthesisLabel';
  }

  String _reviewAiTooltip(AiSettingsState aiSettings, int includedCount, int guardrailStage) {
    final hasPersistentReview = _hasReviewStateForCurrentSelection();
    // The first category is "Quality" — the typical default for review.
    final reviewLabel = aiSettings.labelForCategory(
      aiSettings.reviewCommitModelCategoryId,
      _commitAiCategories.isNotEmpty ? _commitAiCategories.first.label : 'quality',
    ).toLowerCase();
    final guardrail = _guardrailLabelForStage(guardrailStage).toLowerCase();
    if (_reviewRunning) {
      return _reviewActive ? 'reviewing...' : 'show review';
    }
    if (_commitAiLoading) {
      return 'preparing commit review...';
    }
    if (includedCount == 0) {
      return 'select at least one file to review.';
    }
    if (!_hasReviewAiSelection(aiSettings)) {
      return _commitAiError ??
          'configure review AI in settings.';
    }
    if (hasPersistentReview) {
      if (_reviewActive) {
        final verdict = _reviewResult?.verdict;
        return verdict != null ? verdict.toLowerCase() : 'viewing review';
      }
      return 'show review';
    }
    return '$guardrail review with $reviewLabel model';
  }

  bool _hasReviewStateForCurrentSelection() {
    final scopeKey = _currentReviewScopeKey();
    if (scopeKey == null || _reviewScopeKey != scopeKey) {
      return false;
    }
    return _reviewRunning || _reviewResult != null || _reviewError != null;
  }

  String? _currentReviewScopeKey() {
    final repo = context.read<RepositoryState>();
    final status = repo.status;
    if (status == null) {
      return null;
    }
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      return null;
    }
    return _buildMultiDiffScopeKey(included);
  }

  void _showExistingReview() {
    if (!_hasReviewStateForCurrentSelection()) {
      return;
    }
    setState(() {
      _reviewActive = true;
    });
  }

  String _reviewModelLabel(AiSettingsState aiSettings) {
    final selectedCategory = _commitAiCategories
            .where(
              (category) =>
                  category.id == aiSettings.reviewCommitModelCategoryId &&
                  category.models.isNotEmpty,
            )
            .firstOrNull ??
        _commitAiCategories.where((category) => category.models.isNotEmpty).firstOrNull;
    if (selectedCategory == null) {
      return 'No model';
    }
    final selectedModel = selectedCategory.models
            .where(
              (model) =>
                  model.value ==
                  aiSettings.modelSelections[selectedCategory.id],
            )
            .firstOrNull ??
        selectedCategory.models.first;
    return '${selectedModel.providerLabel} | ${selectedModel.modelId}';
  }

  Future<void> _refreshCommitAiConfig({bool forceRefresh = false}) async {
    final aiSettings = context.read<AiSettingsState>();
    if (!forceRefresh && aiSettings.runtimeModelCategories.isNotEmpty) {
      setState(() {
        _commitAiCategories = aiSettings.runtimeModelCategories;
        _commitAiLoading = false;
        _commitAiError = aiSettings.runtimeModelCategoriesError;
      });
      return;
    }
    setState(() {
      _commitAiLoading =
          forceRefresh || aiSettings.runtimeModelCategories.isEmpty;
      _commitAiError = aiSettings.runtimeModelCategoriesError;
    });
    await aiSettings.refreshModelCategories(forceRefresh: forceRefresh);
    if (!mounted) {
      return;
    }
    setState(() {
      _commitAiLoading = false;
      if (aiSettings.runtimeModelCategories.isNotEmpty) {
        _commitAiCategories = aiSettings.runtimeModelCategories;
        _commitAiError = null;
      } else {
        _commitAiError = aiSettings.runtimeModelCategoriesError;
      }
    });
  }

  Future<List<AiModelCategoryData>?> _resolveCommitAiCategories({
    bool forceRefresh = false,
  }) async {
    final aiSettings = context.read<AiSettingsState>();
    if (!forceRefresh && aiSettings.runtimeModelCategories.isNotEmpty) {
      if (_commitAiCategories != aiSettings.runtimeModelCategories) {
        setState(() {
          _commitAiCategories = aiSettings.runtimeModelCategories;
          _commitAiError = aiSettings.runtimeModelCategoriesError;
        });
      }
      return aiSettings.runtimeModelCategories;
    }
    if (!forceRefresh &&
        _commitAiCategories.any((category) => category.models.isNotEmpty)) {
      return _commitAiCategories;
    }

    final ok = await aiSettings.refreshModelCategories(forceRefresh: forceRefresh);
    if (!mounted) {
      return null;
    }
    if (!ok) {
      setState(() {
        _commitAiError = aiSettings.runtimeModelCategoriesError;
      });
      return null;
    }

    setState(() {
      _commitAiCategories = aiSettings.runtimeModelCategories;
      _commitAiError = null;
    });
    return aiSettings.runtimeModelCategories;
  }

  /// Builds the merge-resolution prompt + context and invokes the AI
  /// with the chosen model category. Reads every conflicted file's
  /// current on-disk contents (markers included) so the model sees the
  /// FULL picture in one shot — resolving file A sometimes requires
  /// knowing what the resolution in file B will be (rename coherence,
  /// callsite updates). One call, one patch, verified via `apply --check`.
  ///
  /// [categoryId] picks which model slot to use ('fast' by default; the
  /// chevron lets the user override to 'quality' etc.). On success the
  /// returned patch goes straight into [showPatchPreviewDialog] — same
  /// surface as the PR lens uses for imported patches. On failure the
  /// working tree is untouched; the user sees a snackbar.
  Future<void> _resolveMergeConflicts(
    String repoPath,
    String categoryId,
  ) async {
    if (_mergeResolving) return;
    final status = context.read<RepositoryState>().status;
    if (status == null) return;
    final conflicted = status.files
        .where((f) => f.staged == 'U' || f.unstaged == 'U')
        .map((f) => f.path)
        .toList();
    if (conflicted.isEmpty) return;

    final aiSettings = context.read<AiSettingsState>();
    final modelValue = aiSettings.modelSelections[categoryId] ?? '';
    if (modelValue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No model configured for "${aiSettings.labelForCategory(categoryId, categoryId)}". '
              'Set one in Settings → AI.'),
        ),
      );
      return;
    }

    setState(() => _mergeResolving = true);
    try {
      final snapshots = <({String path, String content})>[];
      var skippedSensitive = 0;
      for (final p in conflicted) {
        // Hard default: never send credentials-shaped paths to a
        // provider. User still sees them as UU in the file list and
        // resolves by hand. No config, no toggle — this is a floor
        // the feature respects automatically.
        if (isSensitivePath(p)) {
          skippedSensitive++;
          continue;
        }
        try {
          final text = await File(p.startsWith('/') || p.contains(':')
                  ? p
                  : '$repoPath${Platform.pathSeparator}$p')
              .readAsString();
          snapshots.add((path: p, content: text));
        } catch (_) {
          // Skip unreadable files; the prompt will just not include them.
        }
      }
      if (snapshots.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(skippedSensitive > 0
                  ? '$skippedSensitive sensitive file${skippedSensitive == 1 ? '' : 's'} skipped — resolve by hand.'
                  : 'Could not read any conflicted files.')),
        );
        return;
      }

      final prompt = _buildMergeResolutionPrompt(snapshots);
      // Second-pass guardrail: even if the path wasn't sensitive, the
      // contents might be (API key pasted into a normal file). Refuse
      // before the transport layer sees it.
      final secretHit = detectLikelySecretInPrompt(prompt);
      if (secretHit != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Blocked — a conflicted file looks like it contains a $secretHit. Resolve by hand.'),
          ),
        );
        return;
      }
      final r = await generatePatch(
        repositoryPath: repoPath,
        modelValue: modelValue,
        prompt: prompt,
        commandLabelPrefix: 'ai.merge_resolve',
      );
      if (!mounted) return;
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resolution failed: ${r.error}')),
        );
        return;
      }
      // Parse the returned patch up-front so we can reconcile against
      // the UU set the user was shown. The preview will do this too,
      // but we need the path list here to gate stagePaths correctly —
      // otherwise a partial resolution silently `git add`'s files that
      // still have markers in them. That's the #1 failure-mode flagged
      // by maintainers ("I trusted the green badge and shipped UU
      // markers").
      final resolvedLines = parseUnifiedDiff(r.data!.patch);
      final resolvedPaths = <String>{
        for (final l in resolvedLines)
          if (l.filePath != null) l.filePath!,
      };
      final expectedPaths = snapshots.map((s) => s.path).toSet();
      final intersect = expectedPaths.intersection(resolvedPaths);
      await showPatchPreviewDialog(
        context,
        repoPath: repoPath,
        rawPatch: r.data!.patch,
        sourceLabel:
            '◇ merge resolution · ${intersect.length}/${expectedPaths.length} files · ${aiSettings.labelForCategory(categoryId, categoryId)}',
        expectedPaths: expectedPaths,
        onApplied: () async {
          // Only stage the files the patch ACTUALLY touched. Any UU
          // file the AI skipped must stay UU so the user sees it on
          // the next refresh and can resolve it manually. `git add`
          // on a file with markers is the silent-drop footgun.
          if (intersect.isNotEmpty) {
            await stagePaths(repoPath, intersect.toList());
          }
          if (mounted) {
            await context.read<RepositoryState>().refreshStatus();
          }
        },
      );
    } finally {
      if (mounted) setState(() => _mergeResolving = false);
    }
  }

  /// Natural-language partial staging. Takes the user's English
  /// sentence + the full working-tree diff and asks the AI for a
  /// subset patch containing ONLY the hunks the sentence describes.
  /// That patch goes through the existing preview surface (stage
  /// mode → `git apply --cached`) so the user sees exactly what will
  /// be staged before it happens. Working tree stays untouched either
  /// way; if the AI returns garbage, `apply --check` catches it and
  /// the index is never mutated.
  Future<void> _runShape(
    String repoPath,
    RepositoryStatus status,
    String sentence,
    String categoryId,
  ) async {
    if (_shaping) return;
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return;
    if (status.files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to shape.')),
      );
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final modelValue = aiSettings.modelSelections[categoryId] ?? '';
    if (modelValue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No model configured for "${aiSettings.labelForCategory(categoryId, categoryId)}".'),
        ),
      );
      return;
    }

    setState(() => _shaping = true);
    try {
      // Grab the full working-tree diff (staged + unstaged, over every
      // dirty file). The AI needs to see everything to decide what to
      // include and what to exclude.
      final diffResult = await getSelectionDiff(repoPath, status.files);
      if (!diffResult.ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read diff: ${diffResult.error}')),
        );
        return;
      }
      final fullDiffRaw = (diffResult.data ?? '').trim();
      if (fullDiffRaw.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to shape — diff is empty.')),
        );
        return;
      }
      // Silently drop sections for sensitive paths before the AI ever
      // sees them. If shape ends up empty after filtering, the user
      // gets a clean "only sensitive files dirty" message rather than
      // a leak. No config, no toggle.
      final fullDiff = _stripSensitivePathsFromDiff(fullDiffRaw);
      if (fullDiff.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Only sensitive files are dirty — skipped, resolve by hand.')),
        );
        return;
      }

      final prompt = _buildShapePrompt(trimmed, fullDiff);
      final secretHit = detectLikelySecretInPrompt(prompt);
      if (secretHit != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Blocked — dirty files look like they contain a $secretHit. Stage by hand.'),
          ),
        );
        return;
      }
      final r = await generatePatch(
        repositoryPath: repoPath,
        modelValue: modelValue,
        prompt: prompt,
        commandLabelPrefix: 'ai.shape_stage',
      );
      if (!mounted) return;
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shape failed: ${r.error}')),
        );
        return;
      }
      await showPatchPreviewDialog(
        context,
        repoPath: repoPath,
        rawPatch: r.data!.patch,
        sourceLabel: '◈ shape → index · "$trimmed"',
        stageMode: true,
        onApplied: () {
          // Successful stage → exit shape-mode, clear the sentence,
          // move focus to the commit message field so the user can
          // immediately write the commit for what was just staged.
          // Without this the user is stranded in an empty (or stale)
          // shape field and has to click ◈ again, which is ~15 wasted
          // clicks over a 15-commit marathon session.
          if (!mounted) return;
          _shapeCtrl.clear();
          if (_shapeMode) {
            setState(() => _shapeMode = false);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _commitMsgFocusNode.requestFocus();
          });
        },
        onRefine: (refinement) async {
          // Stack refinement onto the original sentence so the AI sees
          // the cumulative intent. Keeps the UX of "one refinement at
          // a time" while the prompt itself gets the whole story.
          if (!mounted) return;
          final combined = '$trimmed. $refinement';
          await _runShape(repoPath, status, combined, categoryId);
        },
      );
    } finally {
      if (mounted) setState(() => _shaping = false);
    }
  }

  /// Shape-staging prompt. Very strict: output must be a SUBSET of the
  /// supplied diff. The model is explicitly forbidden from inventing
  /// hunks — that's the invariant that lets `apply --check` act as a
  /// hard safety gate. Ambiguity defaults to exclusion.
  String _buildShapePrompt(String sentence, String fullDiff) {
    final buf = StringBuffer();
    buf.writeln(
        'You are shaping a git commit by staging a subset of the working tree.');
    buf.writeln(
        'The user will describe what to include, in plain English. Your job is');
    buf.writeln(
        'to return a unified diff that is a strict SUBSET of the diff below —');
    buf.writeln(
        'include only the hunks matching the description, omit the rest.');
    buf.writeln();
    buf.writeln('Rules:');
    buf.writeln(
        '  1. Output ONLY a unified diff. No fences, no prose, no explanation.');
    buf.writeln(
        '  2. Every hunk you emit MUST exist in the diff below — never invent.');
    buf.writeln(
        '  3. You may omit hunks; you may NOT reorder, merge, split, or edit them.');
    buf.writeln(
        '  4. Preserve hunk headers exactly (line numbers, @@ markers).');
    buf.writeln(
        '  5. If the user\'s sentence is ambiguous about a hunk, OMIT it.');
    buf.writeln(
        '  6. File headers (--- a/ +++ b/) are required for each file you emit.');
    buf.writeln(
        '  7. Edge-case files: for a NEW file keep its full "new file mode"');
    buf.writeln(
        '     preamble verbatim; for a RENAME keep the "rename from/to"');
    buf.writeln(
        '     lines; for a BINARY file ("GIT binary patch" marker) emit the');
    buf.writeln(
        '     entire binary hunk UNCHANGED or omit the file — never try to');
    buf.writeln(
        '     partial-stage a binary blob.');
    buf.writeln();
    buf.writeln('<user_intent>');
    buf.writeln(sentence);
    buf.writeln('</user_intent>');
    buf.writeln();
    buf.writeln('<working_tree_diff>');
    buf.writeln(fullDiff);
    buf.writeln('</working_tree_diff>');
    buf.writeln();
    buf.writeln(
        'Emit the subset unified diff now. Remember: strict subset only.');
    return buf.toString();
  }

  /// Walks a unified diff and drops every per-file section whose path
  /// matches [isSensitivePath]. Works at the `diff --git` boundary so
  /// we never split a hunk — either a file is fully included or fully
  /// excluded. Robust against diffs that start with either `diff --git`
  /// headers (the standard) or bare `--- a/path` pairs (rare but git
  /// does emit these for some merge-base outputs).
  String _stripSensitivePathsFromDiff(String fullDiff) {
    final lines = fullDiff.split('\n');
    final out = <String>[];
    var skip = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('diff --git ')) {
        // `diff --git a/path b/path` — extract the `b/` side and check.
        final m = RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(line);
        final path = m?.group(2) ?? '';
        skip = path.isNotEmpty && isSensitivePath(path);
      } else if (line.startsWith('--- ') &&
          i + 1 < lines.length &&
          lines[i + 1].startsWith('+++ ')) {
        // Bare `--- a/path` pair fallback (no `diff --git` header).
        final path = lines[i + 1].startsWith('+++ b/')
            ? lines[i + 1].substring('+++ b/'.length)
            : lines[i + 1].substring('+++ '.length);
        skip = path.isNotEmpty && isSensitivePath(path);
      }
      if (!skip) out.add(line);
    }
    return out.join('\n').trim();
  }

  /// Builds the merge-resolution prompt. Strict about output shape so
  /// the one-shot round-trip works: unified diff only, no prose, no
  /// fences. [_extractPatchFromModelOutput] in ai.dart also defends us
  /// if the model ignores the format instruction.
  String _buildMergeResolutionPrompt(
    List<({String path, String content})> files,
  ) {
    final buf = StringBuffer();
    buf.writeln(
        'You are resolving git merge conflicts in a working tree. For each file');
    buf.writeln(
        'below, the text contains unresolved conflict markers (<<<<<<<, =======, >>>>>>>).');
    buf.writeln();
    buf.writeln('Rules:');
    buf.writeln(
        '  1. Produce ONE unified diff that applies with `git apply` over the current tree.');
    buf.writeln(
        '  2. Every conflict marker must be removed — no <<<<<<<, =======, or >>>>>>> lines in the output.');
    buf.writeln(
        '  3. Preserve the MEANING of both sides. Rename/callsite changes on one side should propagate to the other side\'s callsites if both sides edit the same symbol.');
    buf.writeln(
        '  4. Do NOT introduce new functionality the conflict didn\'t already introduce.');
    buf.writeln(
        '  5. Output format: unified diff only. No code fences, no prose, no explanations.');
    buf.writeln();
    buf.writeln(
        'Files (each shown with current on-disk contents, markers included):');
    buf.writeln();
    for (final f in files) {
      buf.writeln('--- file: ${f.path} ---');
      buf.writeln(f.content);
      buf.writeln('--- end: ${f.path} ---');
      buf.writeln();
    }
    buf.writeln(
        'Output the unified diff that resolves every conflict across all files above.');
    return buf.toString();
  }

  Future<void> _generateCommitMessage(
    String repoPath,
    RepositoryStatus status,
  ) async {
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      setState(() {
        _actionError = 'Choose at least one file before generating.';
        _actionMessage = null;
      });
      return;
    }

    setState(() {
      _generateRunning = true;
      _actionError = null;
      _actionMessage = null;
    });

    final categories = await _resolveCommitAiCategories();
    if (!mounted) {
      return;
    }
    if (categories == null) {
      setState(() {
        _generateRunning = false;
        _actionError =
            _commitAiError ?? 'Commit-message AI is not available yet.';
      });
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final preferences = context.read<PreferencesState>();
    final selectedCategory = categories
            .where(
              (category) =>
                  category.id == aiSettings.commitMessageModelCategoryId &&
                  category.models.isNotEmpty,
            )
            .firstOrNull ??
        categories.where((category) => category.models.isNotEmpty).firstOrNull;

    if (selectedCategory == null) {
      setState(() {
        _generateRunning = false;
        _actionError =
            'No runtime-discovered models are available for commit messages.';
      });
      return;
    }

    final selectedModel = selectedCategory.models
            .where(
              (model) =>
                  model.value ==
                  aiSettings.modelSelections[selectedCategory.id],
            )
            .firstOrNull ??
        selectedCategory.models.first;

    final includeStaged = included.any((file) => _isDirty(file.staged));
    final includeUnstaged = included.any((file) => _isDirty(file.unstaged));
    final scopeLabel = included.length == status.files.length
        ? 'all included files'
        : '${included.length} included file${included.length == 1 ? '' : 's'}';

    final result = await generateCommitMessage(
      repositoryPath: repoPath,
      modelValue: selectedModel.value,
      modelCategoryLabel: aiSettings.labelForCategory(
        selectedCategory.id,
        selectedCategory.label,
      ),
      scopeLabel: scopeLabel,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: included.map((file) => file.path).toList(),
      customPrompt: aiSettings.commitMessagePrompt,
      existingMessage: _commitMsgCtrl.text.trim(),
      readOnly: preferences.aiReadOnlyDefault,
      structure: preferences.commitStructure,
      voice: preferences.commitVoice,
      coverage: preferences.commitCoverage,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _generateRunning = false;
      _generateSuccess = result.ok;
      if (_generateSuccess) {
        // Auto-clear success after a beat so the icon returns to idle.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _generateSuccess = false);
        });
      }
      if (result.ok) {
        _commitMsgCtrl.text = result.data!.message;
        _commitMsgCtrl.selection = TextSelection.collapsed(
          offset: _commitMsgCtrl.text.length,
        );
        _actionMessage = null;
      } else {
        _actionError = result.error;
      }
    });
  }

  Future<void> _reviewCommit(
    String repoPath,
    RepositoryStatus status,
  ) async {
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      setState(() {
        _actionError = 'Choose at least one file before reviewing.';
        _actionMessage = null;
      });
      return;
    }

    final scopeKey = _buildMultiDiffScopeKey(included);
    if (_reviewScopeKey == scopeKey &&
        (_reviewRunning || _reviewResult != null || _reviewError != null)) {
      setState(() {
        _reviewActive = true;
      });
      return;
    }

    setState(() {
      _reviewRunning = true;
      _reviewActive = true;
      _reviewScopeKey = scopeKey;
      _reviewError = null;
      _reviewResult = null;
      _reviewTraceExpanded = false;
      _reviewReasoningExpanded = false;
      _actionError = null;
      _actionMessage = null;
    });

    final categories = await _resolveCommitAiCategories();
    if (!mounted) {
      return;
    }
    if (categories == null) {
      setState(() {
        _reviewRunning = false;
        _reviewError = _commitAiError ?? 'Review AI is not available yet.';
      });
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final preferences = context.read<PreferencesState>();
    final selectedCategory = categories
            .where(
              (category) =>
                  category.id == aiSettings.reviewCommitModelCategoryId &&
                  category.models.isNotEmpty,
            )
            .firstOrNull ??
        categories.where((category) => category.models.isNotEmpty).firstOrNull;

    if (selectedCategory == null) {
      setState(() {
        _reviewRunning = false;
        _reviewError =
            'No runtime-discovered models are available for commit review.';
      });
      return;
    }

    final selectedModel = selectedCategory.models
            .where(
              (model) =>
                  model.value ==
                  aiSettings.modelSelections[selectedCategory.id],
            )
            .firstOrNull ??
        selectedCategory.models.first;

    final includeStaged = included.any((file) => _isDirty(file.staged));
    final includeUnstaged = included.any((file) => _isDirty(file.unstaged));
    final scopeLabel = included.length == status.files.length
        ? 'all included files'
        : '${included.length} included file${included.length == 1 ? '' : 's'}';

    final result = await reviewCommit(
      repositoryPath: repoPath,
      modelValue: selectedModel.value,
      modelCategoryLabel: aiSettings.labelForCategory(
        selectedCategory.id,
        selectedCategory.label,
      ),
      scopeLabel: scopeLabel,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: included.map((file) => file.path).toList(),
      customPrompt: aiSettings.reviewCommitPrompt,
      commitDraft: _commitMsgCtrl.text.trim(),
      guardrailStage: preferences.guardrailStage,
      doubleCheckEnabled: aiSettings.reviewCommitDoubleCheckEnabled,
      readOnly: preferences.aiReadOnlyDefault,
    );
    if (!mounted) {
      return;
    }
    if (_reviewScopeKey != scopeKey) {
      // Scope changed while this review was in flight — discard result but
      // still clear the running flag so UI doesn't get stuck.
      setState(() {
        _reviewRunning = false;
      });
      return;
    }

    setState(() {
      _reviewRunning = false;
      _reviewSuccess = result.ok;
      if (result.ok) {
        _reviewResult = result.data;
        _reviewError = null;
        _reviewActive = true;
        _reviewReasoningExpanded = result.data!.findings.isEmpty;
      } else {
        _reviewError = result.error;
        _reviewActive = true;
      }
    });
  }

  Future<void> _runMuse(
    String repoPath,
    RepositoryStatus status,
  ) async {
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();
    if (included.isEmpty) {
      setState(() {
        _actionError = 'Choose at least one file before invoking the muse.';
        _actionMessage = null;
      });
      return;
    }

    final scopeKey = _buildMultiDiffScopeKey(included);
    if (_museScopeKey == scopeKey &&
        (_museRunning || _museResult != null || _museError != null)) {
      setState(() => _museActive = true);
      return;
    }

    setState(() {
      _museRunning = true;
      _museActive = true;
      _museScopeKey = scopeKey;
      _museError = null;
      _museResult = null;
      _actionError = null;
      _actionMessage = null;
    });

    final categories = await _resolveCommitAiCategories();
    if (!mounted) return;
    if (categories == null) {
      setState(() {
        _museRunning = false;
        _museError = _commitAiError ?? 'Muse AI is not available yet.';
      });
      return;
    }

    final aiSettings = context.read<AiSettingsState>();
    final preferences = context.read<PreferencesState>();

    // Resolve two distinct slots for the muse:
    //   - brainstorm slot = "fast" if the user has a model assigned to
    //     it (cheap, divergent, looses the wild ideas)
    //   - synthesis slot = the review category (rigorous, grounding-aware)
    // Either falls back to whichever non-empty category is available, so
    // single-slot configurations still work — both phases just route to
    // the same model.
    AiModelCategoryData? pickCategory(String preferredId) {
      return categories
              .where((c) => c.id == preferredId && c.models.isNotEmpty)
              .firstOrNull ??
          categories.where((c) => c.models.isNotEmpty).firstOrNull;
    }

    AiModelOptionData? pickModel(AiModelCategoryData category) {
      return category.models
              .where((m) =>
                  m.value == aiSettings.modelSelections[category.id])
              .firstOrNull ??
          category.models.firstOrNull;
    }

    final synthesisCategory =
        pickCategory(aiSettings.museSynthesisModelCategoryId);
    final brainstormCategory =
        pickCategory(aiSettings.museBrainstormModelCategoryId) ??
            synthesisCategory;

    if (synthesisCategory == null || brainstormCategory == null) {
      setState(() {
        _museRunning = false;
        _museError =
            'No runtime-discovered models are available for the muse.';
      });
      return;
    }
    final synthesisModel = pickModel(synthesisCategory);
    final brainstormModel = pickModel(brainstormCategory);
    if (synthesisModel == null || brainstormModel == null) {
      setState(() {
        _museRunning = false;
        _museError = 'Muse needs at least one configured model.';
      });
      return;
    }

    final includeStaged = included.any((file) => _isDirty(file.staged));
    final includeUnstaged = included.any((file) => _isDirty(file.unstaged));
    final scopeLabel = included.length == status.files.length
        ? 'all included files'
        : '${included.length} included file${included.length == 1 ? '' : 's'}';

    final result = await runMuse(
      repositoryPath: repoPath,
      brainstormModelValue: brainstormModel.value,
      synthesisModelValue: synthesisModel.value,
      scopeLabel: scopeLabel,
      includeStaged: includeStaged,
      includeUnstaged: includeUnstaged,
      scopedPaths: included.map((file) => file.path).toList(),
      customPrompt: aiSettings.musePrompt,
      commitDraft: _commitMsgCtrl.text.trim(),
      guardrailStage: preferences.guardrailStage,
      readOnly: preferences.aiReadOnlyDefault,
    );
    if (!mounted) return;
    if (_museScopeKey != scopeKey) {
      setState(() => _museRunning = false);
      return;
    }

    setState(() {
      _museRunning = false;
      _museSuccess = result.ok;
      if (result.ok) {
        _museResult = result.data;
        _museError = null;
        _museActive = true;
      } else {
        _museError = result.error;
        _museActive = true;
      }
    });
  }

  void _openReviewFinding(
    String repoPath,
    String path,
    RepositoryStatus status, {
    String? hunkLabel,
  }) {
    final startLine = _parseHunkStartLine(hunkLabel);
    final includedCount = _includedDirtyCount(status);
    if (_includedPaths.contains(path) && includedCount > 1) {
      _jumpToMultiDiffPath(path, fallbackStartLine: startLine);
      return;
    }
    _inspectSingleDiff(repoPath, path);
  }

  /// Parses a git hunk label like "@@ -14,6 +14,7 @@" and returns the
  /// new-file start line, which can be used to jump the diff viewer.
  static int? _parseHunkStartLine(String? hunkLabel) {
    if (hunkLabel == null) return null;
    final match = RegExp(r'\+(\d+)').firstMatch(hunkLabel);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  Future<void> _copyReviewReport(AiCommitReviewData review) async {
    final buffer = StringBuffer()
      ..writeln('${review.verdict} | ${review.score}')
      ..writeln(review.summary);
    // Skip the RR section entirely when the model didn't return
    // reasoning — avoids dumping a stray "RR" header with no body
    // into the user's clipboard.
    if (review.reasoningReport.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('RR')
        ..writeln(review.reasoningReport);
    }
    if (review.findings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Findings');
      for (final finding in review.findings) {
        buffer.writeln('- ${finding.title}');
        if (finding.filePath != null || finding.hunkLabel != null) {
          final meta = [
            if (finding.filePath != null) finding.filePath!,
            if (finding.hunkLabel != null) finding.hunkLabel!,
          ].join(' | ');
          buffer.writeln('  $meta');
        }
        if (finding.evidence.trim().isNotEmpty) {
          buffer.writeln('  Evidence: ${finding.evidence}');
        }
        if (finding.whyItMatters.trim().isNotEmpty) {
          buffer.writeln('  Why: ${finding.whyItMatters}');
        }
      }
    }
    if (review.observations.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Observations');
      for (final obs in review.observations) {
        buffer.writeln('- ${obs.title}');
        if (obs.detail.trim().isNotEmpty) {
          buffer.writeln('  ${obs.detail}');
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) {
      return;
    }
    setState(() {
      _actionError = null;
      _actionMessage = 'Copied review report.';
    });
  }

  Future<void> _commit(
    String repoPath,
    RepositoryStatus status, {
    required _CommitRunMode mode,
  }) async {
    final message = _commitMsgCtrl.text.trim();
    final included = status.files
        .where((file) => _includedPaths.contains(file.path))
        .map((file) => file.path)
        .toList();

    if (included.isEmpty) {
      setState(
          () => _actionError = 'Choose at least one file for the next commit.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _actionError = 'Write a commit message first.');
      return;
    }

    setState(() {
      _actionRunning = true;
      _actionError = null;
      _actionMessage = null;
    });

    final stageResult = await stagePaths(repoPath, included);
    if (!mounted) {
      return;
    }
    if (!stageResult.ok) {
      setState(() {
        _actionRunning = false;
        _actionError = stageResult.error;
      });
      return;
    }

    final stagedExcluded = _stagedExcludedPaths(status);
    if (stagedExcluded.isNotEmpty) {
      final unstageResult = await unstagePaths(repoPath, stagedExcluded);
      if (!mounted) {
        return;
      }
      if (!unstageResult.ok) {
        setState(() {
          _actionRunning = false;
          _actionError = unstageResult.error;
        });
        return;
      }
    }

    final commitResult = await createCommit(repoPath, message);
    if (!mounted) {
      return;
    }
    if (!commitResult.ok) {
      setState(() {
        _actionRunning = false;
        _actionError = commitResult.error;
      });
      await _refreshAndReadStatus();
      return;
    }

    final committed = commitResult.data!;
    final shortHash = committed.commitHash.length >= 8
        ? committed.commitHash.substring(0, 8)
        : committed.commitHash;
    var successMessage = 'Committed ${committed.summary} ($shortHash).';
    String? syncError;

    final refreshed = await _refreshAndReadStatus();
    if (!mounted) {
      return;
    }

    if (mode == _CommitRunMode.commitAndSync && refreshed != null) {
      final syncResult = await syncRemote(repoPath, refreshed);
      if (!mounted) {
        return;
      }
      if (syncResult.ok) {
        final operation = syncResult.data!.operation;
        successMessage =
            'Committed ${committed.summary} ($shortHash) and ran $operation.';
      } else {
        syncError = 'Commit succeeded, but sync failed: ${syncResult.error}';
      }
      await _refreshAndReadStatus();
      if (!mounted) {
        return;
      }
    }

    setState(() {
      _actionRunning = false;
      _commitMsgCtrl.clear();
      unawaited(_clearCommitDraft());
      _actionMessage = successMessage;
      _actionError = syncError;
    });
  }

  // ── Filing cabinet (stash) operations ─────────────────────────────────────

  Future<void> _loadStashes(String repo) async {
    setState(() => _stashesLoading = true);
    final result = await listStashes(repo);
    if (!mounted) return;
    setState(() {
      _stashesLoading = false;
      _stashes = result.ok ? result.data! : const [];
      // Invalidate per-stash caches — indices and contents may have shifted
      // after pop/drop/push.
      _stashFiles.clear();
      _stashFilesLoading.clear();
      // Drop open-state entries whose index no longer exists so reopening
      // a new stash at the same slot doesn't surprise the user.
      final validIndices = _stashes.map((s) => s.index).toSet();
      _stashOpenIndices.removeWhere((i) => !validIndices.contains(i));
    });
  }

  Future<void> _loadStashFiles(String repo, int index) async {
    if (_stashFiles.containsKey(index) ||
        _stashFilesLoading.contains(index)) return;
    setState(() => _stashFilesLoading.add(index));
    final r = await stashFiles(repo, index: index);
    if (!mounted) return;
    setState(() {
      _stashFilesLoading.remove(index);
      if (r.ok) _stashFiles[index] = r.data!;
    });
  }

  void _toggleStashOpen(String repo, int index) {
    setState(() {
      if (_stashOpenIndices.contains(index)) {
        _stashOpenIndices.remove(index);
      } else {
        _stashOpenIndices.add(index);
      }
    });
    if (_stashOpenIndices.contains(index)) {
      unawaited(_loadStashFiles(repo, index));
    }
  }

  Future<void> _shelveFiles(String repo, List<String> paths, {String? label}) async {
    final result = await stashPush(repo, message: label, paths: paths);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    await _refreshAndReadStatus();
    if (mounted) _loadStashes(repo);
  }

  Future<void> _shelveAll(String repo, {String? label}) async {
    final result = await stashPush(repo, message: label);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    await _refreshAndReadStatus();
    if (mounted) _loadStashes(repo);
  }

  Future<void> _pickUpStash(String repo, int index) async {
    final result = await stashPop(repo, index: index);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    setState(() {
      _stashPeekDiff = null;
      _stashPeekIndex = null;
    });
    await _refreshAndReadStatus();
    if (mounted) _loadStashes(repo);
  }

  Future<void> _tossStash(String repo, int index) async {
    final result = await stashDrop(repo, index: index);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _actionError = result.error);
      return;
    }
    setState(() {
      if (_stashPeekIndex == index) {
        _stashPeekDiff = null;
        _stashPeekIndex = null;
      }
    });
    if (mounted) _loadStashes(repo);
  }

  Future<void> _peekStash(String repo, int index) async {
    if (_stashPeekIndex == index) {
      setState(() {
        _stashPeekDiff = null;
        _stashPeekIndex = null;
      });
      return;
    }
    final result = await stashShow(repo, index: index);
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _stashPeekDiff = result.data;
        _stashPeekIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final aiSettings = context.watch<AiSettingsState>();
    final preferences = context.watch<PreferencesState>();
    final repo = context.watch<RepositoryState>();
    final coupling = context.watch<FileCouplingState>();
    final repoPath = repo.activePath;
    final status = repo.status;

    // Seed the stash drawer from the user's "default expanded" preference
    // once per session, as soon as we actually have shelves to show. After
    // that the user's manual toggles take over.
    if (!_stashExpandedInitialized && _stashes.isNotEmpty) {
      _stashExpandedInitialized = true;
      if (preferences.stashCabinetDefaultExpanded && !_stashesExpanded) {
        _stashesExpanded = true;
      }
    }

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }

    // Kick off a coupling-matrix compute whenever the observable repo state
    // changes (new repo, new commit, branch switch, ahead/behind moved).
    // The FileCouplingState does its own HEAD-check before recomputing, so
    // calling it on state changes is cheap. Fire-and-forget — the list
    // renders without cluster stripes until notifyListeners brings us back.
    final couplingStateKey =
        '$repoPath|${status?.branch ?? ''}|${status?.files.length ?? 0}|'
        '${status?.ahead ?? 0}|${status?.behind ?? 0}';
    if (_couplingKickedOffFor != couplingStateKey) {
      _couplingKickedOffFor = couplingStateKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final couplingState = context.read<FileCouplingState>();
        await couplingState.loadForRepo(repoPath);
        if (!mounted) return;
        // Chain: once the coupling matrix is warm, immediately warm the
        // LogosGit engine too — it needs the matrix for the CC axis and
        // reusing the cached one saves a second 1000-commit log walk.
        final matrix = couplingState.matrixFor(repoPath);
        if (matrix != null) {
          // ignore: use_build_context_synchronously
          context
              .read<LogosGitState>()
              .loadForRepo(repoPath, coupling: matrix);
        }
      });
    }
    // Refresh per-file impact weights whenever the status signature
    // changes. One numstat call per refresh; results feed the "by impact"
    // sort. Fire-and-forget — the list uses whatever's cached until the
    // new fetch lands, then rebuilds.
    if (_weightsFetchedForKey != couplingStateKey) {
      _weightsFetchedForKey = couplingStateKey;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final r = await fileChangeWeights(repoPath);
        if (!mounted || _weightsFetchedForKey != couplingStateKey) return;
        if (r.ok) {
          setState(() => _changeWeights = r.data!);
        }
      });
    }
    // Detect repo or branch switch — cancel any pending saves,
    // then load the correct draft.
    final currentBranch = status?.branch;
    if (_lastDraftRepoPath != repoPath || _lastDraftBranch != currentBranch) {
      _commitDraftSaveDebounce?.cancel();
      // Flush the current draft to the OLD repo/branch before switching.
      final oldRepo = _lastDraftRepoPath;
      final oldBranch = _lastDraftBranch;
      final textToSave = _commitMsgCtrl.text;
      _lastDraftRepoPath = repoPath;
      _lastDraftBranch = currentBranch;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Save outgoing draft, then load incoming.
        if (oldRepo != null && textToSave.trim().isNotEmpty) {
          await _flushDraft(oldRepo, oldBranch, textToSave);
        }
        _loadCommitDraftForRepo(repoPath, branch: currentBranch, force: true);
        _loadStashes(repoPath);
      });
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

    _syncDraftFromStatus(status);

    if (status.files.isEmpty && _stashes.isEmpty && !_stashesLoading) {
      return _CleanTreeDashboard(
        tokens: t,
        status: status,
        repoPath: repoPath,
        onRefresh: () => repo.refreshStatus(),
      );
    }

    final stagedCount =
        status.files.where((file) => _isDirty(file.staged)).length;
    final includedCount = _includedDirtyCount(status);
    final includedFiles = status.files
        .where((file) => _includedPaths.contains(file.path))
        .toList();

    // Coupling clusters for the current change set. Computed once per build;
    // falls back to "all isolated" when the matrix isn't ready yet.
    final couplingMatrix = coupling.matrixFor(repoPath);
    final _currentPaths = status.files.map((f) => f.path).toList();

    // Universal: gather merge-conflict paths. Any file with 'U' on either
    // side is conflicted and must float to the top regardless of sort.
    final conflictedPaths = <String>{};
    for (final f in status.files) {
      if (f.staged == 'U' || f.unstaged == 'U') {
        conflictedPaths.add(f.path);
      }
    }

    // "By impact" weighting — cognitive weight, not raw line count:
    //   * Binary files get a baseline so they don't sink to 0.
    //   * Deletions count 1.2× additions (intentional removal is usually
    //     more deliberate than piling on code).
    //   * New files get a small bonus — adding a file is conceptually
    //     heavy even when small.
    //   * Untracked files with no numstat entry still get the new-file
    //     bonus so they don't all bucket at 0.
    const double binaryBaseline = 20.0;
    const double newFileBonus = 10.0;
    const double delWeight = 1.2;
    final impactScores = <String, double>{};
    for (final f in status.files) {
      final isNew =
          f.staged == 'A' || f.staged == '?' || f.unstaged == '?';
      final w = _changeWeights[f.path];
      double score;
      if (w == null) {
        score = isNew ? newFileBonus : 0.0;
      } else if (w.binary) {
        score = binaryBaseline + (isNew ? newFileBonus : 0.0);
      } else {
        score = w.adds + w.dels * delWeight;
        if (isNew) score += newFileBonus;
      }
      impactScores[f.path] = score;
    }

    final clusters = couplingMatrix != null && _currentPaths.isNotEmpty
        ? clusterFiles(
            _currentPaths,
            couplingMatrix,
            sortGuide: preferences.fileSortGuide,
            impactScores: impactScores,
            conflictedPaths: conflictedPaths,
            includedPaths: _includedPaths,
            inverted: preferences.fileSortInverted,
          )
        : FileClusters.empty(_currentPaths);

    // Within-cluster φ re-ranking. When the 'related' sort guide is
    // active and the Logos engine is warm, sort cluster members by the
    // diffusion pull from currently-included files. Cluster grouping
    // (which files belong to which cluster) stays intact — the cluster
    // stripe rendering still works — but members within each cluster
    // are re-ordered by relevance to the user's staging intent.
    //
    // At t=0.5 the diffusion is tight (1-hop-ish), so "related" here
    // means "historically moves with what you just staged," not the
    // broader architectural orbit.
    final logosEngine = preferences.fileSortGuide == 'related'
        ? context.watch<LogosGitState>().engineFor(repoPath)
        : null;
    final orderedPaths = (logosEngine != null && _includedPaths.isNotEmpty)
        ? _logosRerankedOrder(
            clusters: clusters,
            engine: logosEngine,
            sources: _includedPaths,
            inverted: preferences.fileSortInverted,
          )
        : clusters.orderedPaths;

    final inspectionOverridePath = _inspectionDiffPath;
    final inspectingSingleDiff = includedFiles.length > 1 &&
        inspectionOverridePath != null &&
        !_includedPaths.contains(inspectionOverridePath);
    final showMultiDiff = includedFiles.length > 1 && !inspectingSingleDiff;
    final activeMultiDiffPath = _multiDiffCurrentPath;
    final activeDiffPath = inspectingSingleDiff
        ? inspectionOverridePath
        : showMultiDiff
            ? activeMultiDiffPath
            : (_visibleDiffPath ?? _selectedDiffPath);
    final primaryAction = _primaryActionFor(status);
    final hasCommitAiSelection = _hasCommitAiSelection(aiSettings);
    final hasReviewAiSelection = _hasReviewAiSelection(aiSettings);
    final hasPersistentReview = _hasReviewStateForCurrentSelection();
    final canCommit = !_actionRunning &&
        !_generateRunning &&
        !_reviewRunning &&
        _commitMsgCtrl.text.trim().isNotEmpty &&
        includedCount > 0;
    final canGenerate = !_actionRunning &&
        !_generateRunning &&
        !_reviewRunning &&
        !_commitAiLoading &&
        includedCount > 0 &&
        hasCommitAiSelection;
    // Allow clicking the review button when a review is running (to navigate
    // back to the spinner view) or when a persistent review exists.
    // Enable when: not busy with other actions AND either there's a review
    // to show or we can start one. When a review is running AND we're already
    // viewing it (_reviewActive), disable — we're already there.
    final canReview = !_actionRunning &&
        !_generateRunning &&
        !_commitAiLoading &&
        !(_reviewRunning && _reviewActive) &&
        includedCount > 0 &&
        (_reviewRunning || hasReviewAiSelection || hasPersistentReview);

    return Stack(
      children: [
        Row(
          children: [
            MaterialSurface(
              tone: AppMaterialTone.surface1,
              radius: 0,
              border: Border(
                right:
                    BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
              ),
              elevated: false,
              width: _leftPanelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            includedCount == 0
                                ? 'No files selected'
                                : includedCount == status.files.length
                                    ? 'All ${status.files.length} file${status.files.length == 1 ? "" : "s"}'
                                    : '$includedCount of ${status.files.length} files',
                            style: TextStyle(
                              color: includedCount == 0
                                  ? t.textMuted.withValues(alpha: 0.55)
                                  : t.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        _SmartSelectBtn(
                          allSelected: status.files.isNotEmpty &&
                              includedCount == status.files.length,
                          noneSelected: includedCount == 0,
                          enabled: !_actionRunning && status.files.isNotEmpty,
                          tokens: t,
                          onSelectAll: () => _includeAll(status),
                          onDeselectAll: () => setState(() {
                            _includedPaths.clear();
                            _actionError = null;
                            _actionMessage = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        if (conflictedPaths.isNotEmpty)
                          _MergeResolveStrip(
                            conflictedPaths: conflictedPaths,
                            totalHunks: null,
                            busy: _mergeResolving,
                            onResolve: (categoryId) =>
                                _resolveMergeConflicts(repoPath, categoryId),
                          ),
                        Expanded(
                          child: Builder(builder: (context) {
                            // `clusters` hoisted at build-method scope so the
                            // header + list share the same clustering.
                            final fileByPath = {
                              for (final f in status.files) f.path: f
                            };
                            final ordered = <RepositoryStatusFile>[
                              for (final p in orderedPaths)
                                if (fileByPath[p] != null) fileByPath[p]!,
                            ];
                            // Defensive: any file that didn't land in ordered.
                            final orderedSet = orderedPaths.toSet();
                            for (final f in status.files) {
                              if (!orderedSet.contains(f.path)) ordered.add(f);
                            }
                            return ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: ordered.length,
                              itemBuilder: (ctx, i) {
                                final file = ordered[i];
                                final cid = clusters.byPath[file.path] ??
                                    FileClusters.clusterIdIsolated;
                                final prevCid = i > 0
                                    ? (clusters.byPath[ordered[i - 1].path] ??
                                        FileClusters.clusterIdIsolated)
                                    : null;
                                final nextCid = i < ordered.length - 1
                                    ? (clusters.byPath[ordered[i + 1].path] ??
                                        FileClusters.clusterIdIsolated)
                                    : null;
                                final showGap =
                                    prevCid != null && prevCid != cid;
                                final inRealCluster =
                                    cid != FileClusters.clusterIdIsolated;
                                // Stripe fuses with neighbour's stripe iff
                                // same real cluster AND no gap boundary.
                                final connectTop = inRealCluster &&
                                    prevCid == cid &&
                                    !showGap;
                                final connectBottom = inRealCluster &&
                                    nextCid != null &&
                                    nextCid == cid;
                                // Peer emphasis: when the mouse is on
                                // another row's stripe in the same cluster,
                                // look up the coupling score between this
                                // file and the subject. Null = not in the
                                // hovered cluster (leave row unchanged).
                                final subjectPath = _railHoverPath;
                                final subjectCid = subjectPath == null
                                    ? null
                                    : clusters.byPath[subjectPath];
                                double? peerScore;
                                bool isRailSubject = false;
                                if (subjectPath != null &&
                                    subjectCid != null &&
                                    subjectCid ==
                                        FileClusters.clusterIdIsolated) {
                                  // Hovered row is isolated — no peers to light up.
                                } else if (subjectPath != null &&
                                    subjectCid == cid &&
                                    inRealCluster) {
                                  if (subjectPath == file.path) {
                                    isRailSubject = true;
                                    peerScore = 1.0;
                                  } else if (couplingMatrix != null) {
                                    peerScore = combinedCouplingScore(
                                        subjectPath,
                                        file.path,
                                        couplingMatrix);
                                  }
                                }
                                final row = _FileRow(
                                  file: file,
                                  tokens: t,
                                  clusterColor:
                                      t.clusterStripeColor(cid),
                                  stripeConnectTop: connectTop,
                                  stripeConnectBottom: connectBottom,
                                  isDiffSelected:
                                      activeDiffPath == file.path,
                                  included:
                                      _includedPaths.contains(file.path),
                                  inRealCluster: inRealCluster,
                                  peerScore: peerScore,
                                  isRailSubject: isRailSubject,
                                  onRailEnter: inRealCluster
                                      ? () {
                                          if (_railHoverPath != file.path) {
                                            setState(() =>
                                                _railHoverPath = file.path);
                                          }
                                        }
                                      : null,
                                  onRailExit: () {
                                    if (_railHoverPath == file.path) {
                                      setState(() => _railHoverPath = null);
                                    }
                                  },
                                  onTap: includedFiles.length > 1
                                      ? () {
                                          if (_includedPaths
                                              .contains(file.path)) {
                                            _jumpToMultiDiffPath(file.path);
                                          } else {
                                            _inspectSingleDiff(
                                                repoPath, file.path);
                                          }
                                        }
                                      : () =>
                                          _loadDiff(repoPath, file.path),
                                  onIncludeChanged: (value) =>
                                      _toggleIncluded(file.path, value),
                                  onSecondaryTap: (pos) =>
                                      _showFileContextMenu(
                                          context, pos, file, repoPath),
                                );
                                if (showGap) {
                                  return Column(children: [
                                    const SizedBox(height: 4),
                                    row,
                                  ]);
                                }
                                return row;
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  MaterialSurface(
                    tone: AppMaterialTone.surface0,
                    radius: 0,
                    border: Border(
                      top: BorderSide(
                        color: t.chromeBorder.withValues(alpha: 0.15),
                      ),
                    ),
                    elevated: false,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ThemeMorphText(
                                includedCount == 0
                                    ? (stagedCount > 0
                                        ? 'Nothing selected · $stagedCount staged'
                                        : 'Nothing selected')
                                    : (stagedCount > 0
                                        ? '$includedCount file${includedCount == 1 ? '' : 's'} selected · $stagedCount staged'
                                        : '$includedCount file${includedCount == 1 ? '' : 's'} selected'),
                                style: TextStyle(
                                  color:
                                      includedCount == 0 ? t.textMuted : t.textNormal,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            _ShelfControl(
                              tokens: t,
                              count: _stashes.length,
                              loading: _stashesLoading,
                              expanded: _stashesExpanded,
                              canShelve: status.files.isNotEmpty,
                              onShelve: status.files.isNotEmpty
                                  ? () => _shelveAll(repoPath)
                                  : null,
                              onToggleExpanded: _stashes.isEmpty
                                  ? null
                                  : () => setState(() =>
                                      _stashesExpanded = !_stashesExpanded),
                            ),
                          ],
                        ),
                        // ── Filing cabinet drawers (inline) ────────
                        if (_stashesExpanded && _stashes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 2),
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 360),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _stashes.length,
                                itemBuilder: (ctx, i) {
                                  final stash = _stashes[i];
                                  final isPeeking =
                                      _stashPeekIndex == stash.index;
                                  final isOpen = _stashOpenIndices
                                      .contains(stash.index);
                                  return _StashDrawerCard(
                                    tokens: t,
                                    stash: stash,
                                    isPeeking: isPeeking,
                                    isOpen: isOpen,
                                    files: _stashFiles[stash.index],
                                    filesLoading: _stashFilesLoading
                                        .contains(stash.index),
                                    onToggleOpen: () => _toggleStashOpen(
                                        repoPath, stash.index),
                                    onPickUp: () =>
                                        _pickUpStash(repoPath, stash.index),
                                    onPeek: () =>
                                        _peekStash(repoPath, stash.index),
                                    onToss: () =>
                                        _tossStash(repoPath, stash.index),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Focus(
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            // Esc: in shape-mode, exit back to the commit
                            // draft. Sentence is preserved in _shapeCtrl;
                            // toggling back later restores it.
                            if (event.logicalKey ==
                                    LogicalKeyboardKey.escape &&
                                _shapeMode) {
                              _toggleShapeMode();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey !=
                                LogicalKeyboardKey.enter) {
                              return KeyEventResult.ignored;
                            }
                            final ctrlOrMeta =
                                HardwareKeyboard.instance.isControlPressed ||
                                    HardwareKeyboard.instance.isMetaPressed;
                            if (!ctrlOrMeta) return KeyEventResult.ignored;
                            // Ctrl/Cmd+Enter routing depends on mode:
                            //   - shape-mode: fire the shape ask (not
                            //     commit — that would fire _commit on a
                            //     stale draft, an incident-class footgun).
                            //   - commit-mode: run the commit.
                            if (_shapeMode) {
                              final text = _shapeCtrl.text.trim();
                              if (text.isEmpty || _shaping) {
                                return KeyEventResult.handled;
                              }
                              final cats = _shapeCategories(aiSettings);
                              if (cats.isEmpty) return KeyEventResult.handled;
                              final cat = cats[_shapeCategoryIndex
                                  .clamp(0, cats.length - 1)];
                              // Fire-and-forget — the dialog is modal, the
                              // key handler returns immediately.
                              _runShape(repoPath, status, text, cat);
                              return KeyEventResult.handled;
                            }
                            _commit(
                              repoPath,
                              status,
                              mode: primaryAction.syncAfterCommit
                                  ? _CommitRunMode.commitAndSync
                                  : _CommitRunMode.commitOnly,
                            );
                            return KeyEventResult.handled;
                          },
                          child: _CommitComposerField(
                            tokens: t,
                            // Bind the active controller based on mode.
                            // The unbound controller keeps its text so
                            // exiting shape-mode restores the commit
                            // draft that was being composed.
                            controller: _shapeMode
                                ? _shapeCtrl
                                : _commitMsgCtrl,
                            focusNode: _shapeMode
                                ? _shapeFocus
                                : _commitMsgFocusNode,
                            hintText: _shapeMode
                                ? 'describe what to stage  ·  e.g. "only the test changes"  ·  ⌘↵ to ask  ·  Esc to exit'
                                : 'Commit message...',
                            shapeMode: _shapeMode,
                            enabled: !_actionRunning,
                            onChanged: (value) {
                              if (!_shapeMode) {
                                _saveCommitDraft(value);
                              }
                              setState(() {});
                            },
                            aiEnabled: canGenerate,
                            aiLoading: _generateRunning || _commitAiLoading,
                            aiSuccess: _generateSuccess,
                            aiTooltip:
                                _commitAiTooltip(aiSettings, includedCount),
                            reviewEnabled: canReview,
                            reviewLoading: _reviewRunning,
                            reviewSuccess: _reviewSuccess,
                            reviewVerdict: _reviewResult?.verdict,
                            reviewTooltip:
                                _reviewAiTooltip(aiSettings, includedCount, preferences.guardrailStage),
                            onGenerate: () => _generateCommitMessage(
                              repoPath,
                              status,
                            ),
                            onReview: () {
                              if (hasPersistentReview) {
                                _showExistingReview();
                                return;
                              }
                              _reviewCommit(repoPath, status);
                            },
                            museEnabled: canReview,
                            museLoading: _museRunning,
                            museSuccess: _museSuccess,
                            museTooltip: _museTooltip(aiSettings, includedCount),
                            onMuse: () {
                              if (_museResult != null || _museError != null) {
                                setState(() => _museActive = true);
                                return;
                              }
                              _runMuse(repoPath, status);
                            },
                            // ◈ shape: now toggles inline shape-mode
                            // instead of opening a floating popover.
                            // The composer field morphs in place; the
                            // bottom split-button morphs too.
                            shapeEnabled: status.files.isNotEmpty &&
                                !_actionRunning &&
                                !_shaping,
                            shapeLoading: _shaping,
                            shapeTooltip: _shapeMode
                                ? 'exit · restore your commit draft'
                                : 'stage files by describing them',
                            onToggleShape: status.files.isEmpty
                                ? null
                                : _toggleShapeMode,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_shapeMode)
                          _ShapeAskButton(
                            tokens: t,
                            categories: _shapeCategories(aiSettings),
                            categoryIndex: _shapeCategoryIndex,
                            busy: _shaping,
                            enabled: !_actionRunning &&
                                _shapeCtrl.text.trim().isNotEmpty,
                            onCycle: () {
                              final cats = _shapeCategories(aiSettings);
                              if (cats.isEmpty) return;
                              setState(() => _shapeCategoryIndex =
                                  (_shapeCategoryIndex + 1) % cats.length);
                            },
                            onCycleBack: () {
                              final cats = _shapeCategories(aiSettings);
                              if (cats.length < 2) return;
                              setState(() => _shapeCategoryIndex =
                                  (_shapeCategoryIndex - 1 + cats.length) %
                                      cats.length);
                            },
                            onAsk: () async {
                              final text = _shapeCtrl.text.trim();
                              if (text.isEmpty) return;
                              final cats = _shapeCategories(aiSettings);
                              if (cats.isEmpty) return;
                              final cat = cats[
                                  _shapeCategoryIndex.clamp(0, cats.length - 1)];
                              await _runShape(repoPath, status, text, cat);
                            },
                          )
                        else _SplitCommitBtn(
                          label: _actionRunning
                              ? 'Working…'
                              : (_commitOnlyMode
                                  ? 'Commit only'
                                  : primaryAction.label),
                          alternateLabel: _commitOnlyMode
                              ? primaryAction.label
                              : 'Commit only',
                          commitOnlyMode: _commitOnlyMode,
                          t: t,
                          enabled: canCommit,
                          aiGenerating: _generateRunning || _commitAiLoading,
                          actionRunning: _actionRunning,
                          onCommit: () => _commit(
                            repoPath,
                            status,
                            mode: _commitOnlyMode
                                ? _CommitRunMode.commitOnly
                                : (primaryAction.syncAfterCommit
                                    ? _CommitRunMode.commitAndSync
                                    : _CommitRunMode.commitOnly),
                          ),
                          onToggleMode: () => setState(
                              () => _commitOnlyMode = !_commitOnlyMode),
                        ),
                        if (_actionError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 80),
                              child: SingleChildScrollView(
                                child: Text(
                                  _actionError!,
                                  style: TextStyle(
                                    color: t.stateConflicted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _PanelDivider(
              tokens: t,
              onDrag: (dx) => setState(() {
                _leftPanelWidth = (_leftPanelWidth + dx)
                    .clamp(_minLeftPanelWidth, _maxLeftPanelWidth);
              }),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  // Stash peek view
                  if (_stashPeekIndex != null && _stashPeekDiff != null) {
                    final peekStash = _stashes.where((s) => s.index == _stashPeekIndex).firstOrNull;
                    final peekLabel = peekStash?.message ?? 'stash@{$_stashPeekIndex}';
                    return DiffShell(
                      key: ValueKey('stash-peek-$_stashPeekIndex'),
                      filePath: 'filed: $peekLabel',
                      diffContent: _stashPeekDiff,
                      loading: false,
                      error: null,
                      tokens: t,
                      repositoryPath: repoPath,
                    );
                  }
                  if (_museActive) {
                    return MaterialSurface(
                      tone: AppMaterialTone.surface0,
                      radius: 0,
                      borderAlpha: 0,
                      elevated: false,
                      child: _MusePane(
                        tokens: t,
                        loading: _museRunning,
                        error: _museError,
                        result: _museResult,
                        guardrailLabel:
                            _guardrailLabelForStage(preferences.guardrailStage),
                        onBack: () => setState(() {
                          _museActive = false;
                        }),
                        onRerun: () {
                          setState(() {
                            _museRunning = false;
                            _museSuccess = false;
                            _museScopeKey = null;
                            _museResult = null;
                            _museError = null;
                          });
                          _runMuse(repoPath, status);
                        },
                      ),
                    );
                  }
                  if (_reviewActive) {
                    final contentForStats = showMultiDiff ? _multiDiffContent : _diffContent;
                    final stats = contentForStats != null
                        ? DiffStats.fromRawDiff(contentForStats)
                        : const DiffStats();

                    return MaterialSurface(
                      tone: AppMaterialTone.surface0,
                      radius: 0,
                      borderAlpha: 0,
                      elevated: false,
                      child: _CommitReviewPane(
                        tokens: t,
                        includedCount: includedCount,
                        diffAdds: stats.adds,
                        diffDels: stats.dels,
                        diffHunks: stats.hunks,
                        modelLabel: _reviewModelLabel(aiSettings),
                        guardrailLabel:
                            _guardrailLabelForStage(preferences.guardrailStage),
                        guardrailStage: preferences.guardrailStage,
                        loading: _reviewRunning,
                        error: _reviewError,
                        result: _reviewResult,
                        traceExpanded: _reviewTraceExpanded,
                        reasoningExpanded: _reviewReasoningExpanded,
                        onToggleTrace: () => setState(
                          () => _reviewTraceExpanded = !_reviewTraceExpanded,
                        ),
                        onToggleReasoning: () => setState(
                          () => _reviewReasoningExpanded =
                              !_reviewReasoningExpanded,
                        ),
                        onCancel: _cancelReviewRequest,
                        onBack: () => setState(() {
                          _clearReviewState();
                        }),
                        onRerun: () {
                          _clearReviewState();
                          _reviewCommit(repoPath, status);
                        },
                        onCopy: _reviewResult == null
                            ? null
                            : () => _copyReviewReport(_reviewResult!),
                        onOpenFinding: (path, hunkLabel) =>
                            _openReviewFinding(repoPath, path, status, hunkLabel: hunkLabel),
                      ),
                    );
                  }
                  if (showMultiDiff) {
                    _primeMultiDiff(repoPath, includedFiles);
                    final timelineSections = _buildTimelineSections(
                        includedFiles, _multiDiffSections);
                    return MaterialSurface(
                      tone: AppMaterialTone.surface0,
                      radius: 0,
                      borderAlpha: 0,
                      elevated: false,
                      child: Column(
                        children: [
                          _MultiDiffTimelineStrip(
                            tokens: t,
                            sections: timelineSections,
                            currentPath: _multiDiffCurrentPath,
                            onSelectPath: (section) => _jumpToMultiDiffPath(
                              section.path,
                              fallbackStartLine: section.startLine,
                            ),
                          ),
                          Expanded(
                            // Track vertical scroll to sync the timeline strip.
                            // Intentionally omits depth==0: the DiffShell's ListView
                            // is nested inside a horizontal SingleChildScrollView,
                            // so its events arrive at depth>0.
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification.metrics.axis !=
                                    Axis.vertical) {
                                  return false;
                                }
                                // UserScrollNotification flags the start and
                                // end of user-initiated scrolling. Programmatic
                                // animateTo never fires it — which is exactly
                                // the signal we need to ignore jump-induced
                                // intermediate offsets.
                                if (notification is UserScrollNotification) {
                                  if (notification.direction !=
                                      ScrollDirection.idle) {
                                    _multiDiffUserDriving = true;
                                  }
                                  return false;
                                }
                                // On scroll end (both user-driven and
                                // programmatic), finalize currentPath against
                                // the settled offset so we reflect where we
                                // actually landed.
                                if (notification is ScrollEndNotification) {
                                  _handleMultiDiffScroll(
                                    notification.metrics,
                                  );
                                  _multiDiffUserDriving = false;
                                  return false;
                                }
                                // Live updates only while the user is
                                // driving — animation frames from a jump
                                // are skipped, eliminating the flicker.
                                if (notification
                                        is ScrollUpdateNotification &&
                                    _multiDiffUserDriving) {
                                  _handleMultiDiffScroll(
                                    notification.metrics,
                                  );
                                }
                                return false;
                              },
                              child: DiffShell(
                                key: ValueKey(
                                  _multiDiffScopeKey ?? 'multi-diff',
                                ),
                                filePath:
                                    '${includedFiles.length} selected files',
                                diffContent: _multiDiffContent,
                                loading: _multiDiffLoading,
                                error: _multiDiffError,
                                tokens: t,
                                repositoryPath: repoPath,
                                jumpToLineIndex: _multiDiffJumpLineIndex,
                                jumpToLineRequestId: _multiDiffJumpRequestId,
                                showFileHeader: false,
                                enableStaging: true,
                                onStagingApplied: () {
                                  unawaited(_loadMultiDiff(
                                    repoPath,
                                    includedFiles,
                                  ));
                                  unawaited(repo.refreshStatus());
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return MaterialSurface(
                    tone: AppMaterialTone.surface0,
                    radius: 0,
                    borderAlpha: 0,
                    elevated: false,
                    child: _selectedDiffPath == null
                        ? const AppStatusView(
                            title: 'No file selected',
                            message:
                                'Select a changed file to inspect its diff.',
                            compact: true,
                          )
                        : DiffShell(
                            key: ValueKey(
                              _visibleDiffPath ?? _selectedDiffPath!,
                            ),
                            filePath: _visibleDiffPath ?? _selectedDiffPath!,
                            diffContent: _diffContent,
                            loading: _diffLoading,
                            error: _diffError,
                            tokens: t,
                            repositoryPath: repoPath,
                            enableStaging: true,
                            onStagingApplied: () {
                              final path =
                                  _visibleDiffPath ?? _selectedDiffPath;
                              if (path != null) {
                                unawaited(_loadDiff(repoPath, path));
                              }
                              unawaited(repo.refreshStatus());
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
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
      ],
    );
  }
}

bool _samePathSet(Set<String> a, Set<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}

class _CombinedDiffSection {
  final String path;
  final String displayName;
  final int index;
  final int startLine;

  const _CombinedDiffSection({
    required this.path,
    required this.displayName,
    required this.index,
    required this.startLine,
  });
}

/// Re-rank `clusters.orderedPaths` within each cluster by diffusion pull
/// from the currently-staged file set. Cluster boundaries are preserved
/// so the visual grouping (cluster stripes) stays intact; only the
/// member order inside each cluster changes.
///
/// Sources (files already included) float to the top of their cluster.
/// Remaining members sort by φ descending — the file most strongly
/// coupled to what's staged comes next.
///
/// Temperature t=0.5: tight, 1-hop-ish. "Files that historically move
/// with what you just staged," not the broader architectural orbit.
List<String> _logosRerankedOrder({
  required FileClusters clusters,
  required LogosGit engine,
  required Set<String> sources,
  bool inverted = false,
}) {
  if (sources.isEmpty) return clusters.orderedPaths;
  final scores = engine.diffuse(sources, t: 0.5);
  if (scores.isEmpty) return clusters.orderedPaths;
  final phiByPath = <String, double>{
    for (final s in scores) s.path: s.phi,
  };

  // Walk the original ordering once, collecting cluster runs on first
  // encounter of each cluster ID. Sort each run by (isSource desc, φ desc
  // with `inverted` flipping the φ direction).
  final seen = <int>{};
  final result = <String>[];
  for (final p in clusters.orderedPaths) {
    final cid = clusters.byPath[p] ?? FileClusters.clusterIdIsolated;
    if (seen.contains(cid)) continue;
    seen.add(cid);
    final members = [
      for (final q in clusters.orderedPaths)
        if ((clusters.byPath[q] ?? FileClusters.clusterIdIsolated) == cid)
          q,
    ]..sort((a, b) {
        final aIsSource = sources.contains(a);
        final bIsSource = sources.contains(b);
        if (aIsSource != bIsSource) return aIsSource ? -1 : 1;
        final pa = phiByPath[a] ?? 0.0;
        final pb = phiByPath[b] ?? 0.0;
        return inverted ? pa.compareTo(pb) : pb.compareTo(pa);
      });
    result.addAll(members);
  }
  return result;
}

List<_CombinedDiffSection> _parseCombinedDiffSections(String diffContent) {
  if (diffContent.trim().isEmpty) {
    return const [];
  }

  final sections = <_CombinedDiffSection>[];
  final lines = diffContent.split('\n');
  var renderedLineIndex = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final match = RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(line);
    if (match == null) {
      if (!_isHiddenCombinedDiffPreamble(line)) {
        renderedLineIndex++;
      }
      continue;
    }
    final path = match.group(2) ?? match.group(1) ?? '';
    final normalized = path.trim();
    if (normalized.isEmpty) {
      if (!_isHiddenCombinedDiffPreamble(line)) {
        renderedLineIndex++;
      }
      continue;
    }
    final displayName = normalized.split('/').last;
    sections.add(
      _CombinedDiffSection(
        path: normalized,
        displayName: displayName,
        index: sections.length,
        startLine: renderedLineIndex,
      ),
    );
    if (!_isHiddenCombinedDiffPreamble(line)) {
      renderedLineIndex++;
    }
  }

  return sections;
}

bool _isHiddenCombinedDiffPreamble(String line) =>
    line.startsWith('diff ') || line.startsWith('index ');

List<_CombinedDiffSection> _buildTimelineSections(
  List<RepositoryStatusFile> files,
  List<_CombinedDiffSection> diffSections,
) {
  final seenPaths = <String>{};
  final sections = <_CombinedDiffSection>[];

  for (final section in diffSections) {
    if (!seenPaths.add(section.path)) {
      continue;
    }
    sections.add(
      _CombinedDiffSection(
        path: section.path,
        displayName: section.displayName,
        index: sections.length,
        startLine: section.startLine,
      ),
    );
  }

  for (final file in files) {
    if (!seenPaths.add(file.path)) {
      continue;
    }
    sections.add(
      _CombinedDiffSection(
        path: file.path,
        displayName: file.path.split('/').last,
        index: sections.length,
        startLine: sections.isEmpty ? 0 : sections.last.startLine,
      ),
    );
  }
  return sections;
}

class _MultiDiffTimelineStrip extends StatelessWidget {
  final AppTokens tokens;
  final List<_CombinedDiffSection> sections;
  final String? currentPath;
  final ValueChanged<_CombinedDiffSection>? onSelectPath;

  const _MultiDiffTimelineStrip({
    required this.tokens,
    required this.sections,
    required this.currentPath,
    this.onSelectPath,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = sections.isEmpty
        ? 0
        : sections.indexWhere((section) => section.path == currentPath);
    final effectiveIndex = currentIndex < 0 ? 0 : currentIndex;
    final currentSection = sections.isEmpty ? null : sections[effectiveIndex];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.chromeBorder.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: currentSection?.path,
            child: Text(
              currentSection == null
                  ? '${sections.length} selected files'
                  : '${currentSection.displayName} | ${effectiveIndex + 1} of ${sections.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textStrong,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 7),
          _MultiDiffProgressRail(
            tokens: tokens,
            sections: sections,
            currentIndex: effectiveIndex,
            onSelectPath: onSelectPath,
          ),
        ],
      ),
    );
  }
}

class _MultiDiffProgressRail extends StatelessWidget {
  final AppTokens tokens;
  final List<_CombinedDiffSection> sections;
  final int currentIndex;
  final ValueChanged<_CombinedDiffSection>? onSelectPath;

  const _MultiDiffProgressRail({
    required this.tokens,
    required this.sections,
    required this.currentIndex,
    this.onSelectPath,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return MouseRegion(
          cursor: onSelectPath == null || sections.isEmpty
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onSelectPath == null || sections.isEmpty
                ? null
                : (details) => _selectFromOffset(
                      details.localPosition.dx,
                      width,
                    ),
            onHorizontalDragStart: onSelectPath == null || sections.isEmpty
                ? null
                : (details) => _selectFromOffset(
                      details.localPosition.dx,
                      width,
                    ),
            onHorizontalDragUpdate: onSelectPath == null || sections.isEmpty
                ? null
                : (details) => _selectFromOffset(
                      details.localPosition.dx,
                      width,
                    ),
            child: SizedBox(
              width: width,
              height: 28,
              child: CustomPaint(
                size: Size(width, 28),
                painter: _MultiDiffProgressRailPainter(
                  tokens: tokens,
                  count: sections.length,
                  currentIndex: currentIndex,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _nearestTimelineIndex({
    required double localDx,
    required double width,
    required int count,
  }) {
    if (count <= 1) {
      return 0;
    }
    const horizontalInset = 6.0;
    final clampedWidth =
        width <= horizontalInset * 2 ? horizontalInset * 2 + 1 : width;
    final usableWidth = clampedWidth - (horizontalInset * 2);
    final ratio = ((localDx - horizontalInset) / usableWidth).clamp(0.0, 1.0);
    return (ratio * (count - 1)).round();
  }

  void _selectFromOffset(double localDx, double width) {
    if (onSelectPath == null || sections.isEmpty) {
      return;
    }
    final index = _nearestTimelineIndex(
      localDx: localDx,
      width: width,
      count: sections.length,
    );
    onSelectPath!(sections[index]);
  }
}

class _MultiDiffProgressRailPainter extends CustomPainter {
  final AppTokens tokens;
  final int count;
  final int currentIndex;

  const _MultiDiffProgressRailPainter({
    required this.tokens,
    required this.count,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) {
      return;
    }

    const horizontalInset = 6.0;
    final left = horizontalInset;
    final right = size.width - horizontalInset;
    final centerY = size.height / 2;
    final usableWidth = right - left;
    final progress = count == 1 ? 1.0 : currentIndex / (count - 1);
    final markerX = left + usableWidth * progress.clamp(0.0, 1.0);

    final baseRail = Paint()
      ..color = tokens.chromeBorderStrong
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), baseRail);

    final sampleCount = count < 2
        ? 1
        : count > 44
            ? 44
            : count;

    for (var i = 0; i < sampleCount; i++) {
      final ratio = sampleCount == 1 ? 0.0 : i / (sampleCount - 1);
      final representedIndex =
          sampleCount == 1 ? currentIndex : (ratio * (count - 1)).round();
      final x = left + usableWidth * ratio;
      final isCurrent = representedIndex == currentIndex;
      final radius = isCurrent ? 4.5 : 2.4;
      final fill = Paint()
        ..color = isCurrent
            ? tokens.accentBright
            : tokens.textMuted.withValues(alpha: 0.24);
      canvas.drawCircle(Offset(x, centerY), radius, fill);
    }

    final halo = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(markerX, centerY), 7.5, halo);
    canvas.drawCircle(Offset(markerX, centerY), 6.2, ring);
  }

  @override
  bool shouldRepaint(covariant _MultiDiffProgressRailPainter oldDelegate) {
    return oldDelegate.count != count ||
        oldDelegate.currentIndex != currentIndex ||
        oldDelegate.tokens != tokens;
  }
}

class _MusePane extends StatefulWidget {
  final AppTokens tokens;
  final bool loading;
  final String? error;
  final AiMuseData? result;
  final String guardrailLabel;
  final VoidCallback onBack;
  final VoidCallback onRerun;

  const _MusePane({
    required this.tokens,
    required this.loading,
    required this.error,
    required this.result,
    required this.guardrailLabel,
    required this.onBack,
    required this.onRerun,
  });

  @override
  State<_MusePane> createState() => _MusePaneState();
}

class _MusePaneState extends State<_MusePane> {
  bool _brainstormExpanded = false;
  int? _highlightedIdeaIndex;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _museHeader(t),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: _museBody(t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _museHeader(AppTokens t) {
    final result = widget.result;
    final keptLine = result != null && result.totalIdeaCount > 0
        ? 'considered ${result.totalIdeaCount}, kept ${result.keptIdeaCount} with grounding'
        : '';
    return Row(
      children: [
        Icon(Icons.bubble_chart_outlined,
            size: 16, color: t.textFaint),
        const SizedBox(width: 8),
        Text('Muse', style: TextStyle(
          color: t.textStrong,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        )),
        const SizedBox(width: 8),
        Text('· ${widget.guardrailLabel.toLowerCase()}',
            style: TextStyle(color: t.textFaint, fontSize: 11)),
        if (keptLine.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text('· $keptLine',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textFaint, fontSize: 11)),
          ),
        ],
        if (result != null && result.droppedMoves > 0) ...[
          const SizedBox(width: 6),
          Text(
            '· ${result.droppedMoves} dropped',
            style: TextStyle(
              color: AppSeverityPalette.caution.withValues(alpha: 0.85),
              fontSize: 11,
            ),
          ),
        ],
        const Spacer(),
        _GhostActionChip(
            tokens: t, label: 'rerun', onTap: widget.onRerun),
        const SizedBox(width: 6),
        _GhostActionChip(
            tokens: t, label: 'back to diff', onTap: widget.onBack),
      ],
    );
  }

  Widget _museBody(AppTokens t) {
    if (widget.loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text('the muse is dreaming...',
              style: TextStyle(color: t.textFaint, fontSize: 12)),
        ),
      );
    }
    final err = widget.error;
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(err,
            style: TextStyle(
              color: AppSeverityPalette.caution,
              fontSize: 12,
            )),
      );
    }
    final r = widget.result;
    if (r == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.intent.isNotEmpty) _section(t, 'intent', r.intent, prose: true),
        if (r.drift.isNotEmpty)
          _movesSection(t, 'drift', r.drift, r.brainstormIdeas),
        if (r.wiringBroken.isNotEmpty)
          _movesSection(t, 'wiring · broken', r.wiringBroken, r.brainstormIdeas),
        if (r.wiringMissing.isNotEmpty)
          _movesSection(t, 'wiring · missing', r.wiringMissing, r.brainstormIdeas),
        if (r.ideaFlaws.isNotEmpty)
          _movesSection(t, 'idea flaws', r.ideaFlaws, r.brainstormIdeas),
        if (r.trajectory.isNotEmpty)
          _section(t, 'trajectory', r.trajectory, prose: true),
        if (r.brainstormIdeas.isNotEmpty) _brainstormReveal(t, r),
        if (r.droppedMoves > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${r.droppedMoves} move${r.droppedMoves == 1 ? '' : 's'} '
              'could not be parsed from model output.',
              style: TextStyle(
                color: t.textFaint.withValues(alpha: 0.6),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(AppTokens t, String label, String body,
      {bool prose = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                color: t.textFaint,
                fontSize: 10,
                letterSpacing: 1.2,
              )),
          const SizedBox(height: 6),
          SelectableText(body,
              style: TextStyle(
                color: t.textStrong,
                fontSize: 12.5,
                height: 1.5,
              )),
        ],
      ),
    );
  }

  Widget _movesSection(AppTokens t, String label, List<AiMuseMove> moves,
      List<AiMuseIdea> ideas) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                color: t.textFaint,
                fontSize: 10,
                letterSpacing: 1.2,
              )),
          const SizedBox(height: 6),
          for (final m in moves) _moveCard(t, m, ideas),
        ],
      ),
    );
  }

  Widget _moveCard(AppTokens t, AiMuseMove m, List<AiMuseIdea> ideas) {
    // final so Dart 3 flow analysis promotes the null-check across closure
    // boundaries — removes the need for idea! inside onTap.
    final idea = m.originatingIdeaIndex == null
        ? null
        : ideas.where((i) => i.index == m.originatingIdeaIndex).firstOrNull;
    final highlighted =
        idea != null && _highlightedIdeaIndex == idea.index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: highlighted
              ? t.textStrong.withValues(alpha: 0.04)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: t.textFaint.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(m.body,
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12.5,
                  height: 1.5,
                )),
            if (m.citations.isNotEmpty || idea != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in m.citations)
                    Text(c,
                        style: TextStyle(
                          color: t.textFaint,
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                        )),
                  if (idea != null)
                    GestureDetector(
                      onTap: () => setState(() {
                        _highlightedIdeaIndex =
                            _highlightedIdeaIndex == idea.index
                                ? null
                                : idea.index;
                        _brainstormExpanded = true;
                      }),
                      child: Text('from idea: "${idea.text}"',
                          style: TextStyle(
                            color: t.textFaint.withValues(alpha: 0.85),
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                          )),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _brainstormReveal(AppTokens t, AiMuseData r) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                setState(() => _brainstormExpanded = !_brainstormExpanded),
            child: Row(
              children: [
                Icon(
                  _brainstormExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: t.textFaint,
                ),
                const SizedBox(width: 4),
                Text('brainstorm spew',
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    )),
              ],
            ),
          ),
          if (_brainstormExpanded) ...[
            const SizedBox(height: 8),
            for (final idea in r.brainstormIdeas)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${idea.kept ? '◉' : '·'} ${idea.text}',
                  style: TextStyle(
                    color: idea.kept
                        ? t.textStrong
                        : t.textFaint.withValues(alpha: 0.6),
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: idea.index == _highlightedIdeaIndex
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommitReviewPane extends StatelessWidget {
  final AppTokens tokens;
  final int includedCount;
  final int? diffAdds;
  final int? diffDels;
  final int? diffHunks;
  final String modelLabel;
  final String guardrailLabel;
  final int guardrailStage;
  final bool loading;
  final String? error;
  final AiCommitReviewData? result;
  final bool traceExpanded;
  final bool reasoningExpanded;
  final VoidCallback onToggleTrace;
  final VoidCallback onToggleReasoning;
  final VoidCallback onCancel;
  final VoidCallback onBack;
  final VoidCallback onRerun;
  final VoidCallback? onCopy;
  final void Function(String path, String? hunkLabel) onOpenFinding;

  const _CommitReviewPane({
    required this.tokens,
    required this.includedCount,
    this.diffAdds,
    this.diffDels,
    this.diffHunks,
    required this.modelLabel,
    required this.guardrailLabel,
    required this.guardrailStage,
    required this.loading,
    required this.error,
    required this.result,
    required this.traceExpanded,
    required this.reasoningExpanded,
    required this.onToggleTrace,
    required this.onToggleReasoning,
    required this.onCancel,
    required this.onBack,
    required this.onRerun,
    required this.onCopy,
    required this.onOpenFinding,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _reviewShell(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tokens.chromeBorder.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review commit',
                    style: TextStyle(
                      color: tokens.textStrong,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$includedCount included file${includedCount == 1 ? '' : 's'}'),
                        if (diffAdds != null && diffDels != null && diffHunks != null) ...[
                          const TextSpan(text: ' • '),
                          TextSpan(text: '+$diffAdds', style: TextStyle(color: tokens.stateAdded, fontWeight: FontWeight.w600)),
                          TextSpan(text: ' -$diffDels', style: TextStyle(color: tokens.stateDeleted, fontWeight: FontWeight.w600)),
                          const TextSpan(text: ' • '),
                          TextSpan(text: '$diffHunks hunk${diffHunks == 1 ? '' : 's'}', style: TextStyle(color: tokens.accentBright, fontWeight: FontWeight.w600)),
                        ],
                      ],
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$guardrailLabel | $modelLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: Column(
                  children: [
                    const Spacer(),
                    Text(
                      'Checking these changes...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.textStrong,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Looking for issues before you commit.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.center,
                      child: _GhostActionChip(
                        tokens: tokens,
                        label: 'Cancel',
                        onTap: onCancel,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (error != null && result == null) {
      return _reviewShell(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Review unavailable',
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _GhostActionChip(
                  tokens: tokens,
                  label: 'Back to diff',
                  onTap: onBack,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final review = result;
    if (review == null) {
      return _reviewShell(
        child: const SizedBox.shrink(),
      );
    }

    return _reviewShell(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: tokens.chromeBorder.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Review commit',
                            style: TextStyle(
                              color: tokens.textStrong,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '$includedCount included file${includedCount == 1 ? '' : 's'}'),
                                if (diffAdds != null && diffDels != null && diffHunks != null) ...[
                                  const TextSpan(text: ' • '),
                                  TextSpan(text: '+$diffAdds', style: TextStyle(color: tokens.stateAdded, fontWeight: FontWeight.w600)),
                                  TextSpan(text: ' -$diffDels', style: TextStyle(color: tokens.stateDeleted, fontWeight: FontWeight.w600)),
                                  const TextSpan(text: ' • '),
                                  TextSpan(text: '$diffHunks hunk${diffHunks == 1 ? '' : 's'}', style: TextStyle(color: tokens.accentBright, fontWeight: FontWeight.w600)),
                                ],
                              ],
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ReviewVerdictChip(tokens: tokens, verdict: review.verdict),
                    const SizedBox(width: 6),
                    _ReviewScorePill(
                      tokens: tokens,
                      score: review.score,
                      verdict: review.verdict,
                      guardrailStage: review.guardrailStage,
                    ),
                    if (review.hasVerificationTrace) ...[
                      const SizedBox(width: 6),
                      _ReviewMetaChip(
                        tokens: tokens,
                        label: 'Verified',
                        color: tokens.stateAdded,
                      ),
                    ] else if (review.twoStepEnabled &&
                        review.verificationFailed) ...[
                      const SizedBox(width: 6),
                      _ReviewMetaChip(
                        tokens: tokens,
                        label: 'Draft only',
                        color: tokens.stateModified,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10.5,
                          ),
                          children: [
                            TextSpan(text: review.guardrailStage >= 0
                                ? _guardrailLabelForStage(review.guardrailStage)
                                : guardrailLabel),
                            TextSpan(
                              text: '  ·  ',
                              style: TextStyle(color: tokens.textFaint),
                            ),
                            TextSpan(text: modelLabel),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _GhostActionChip(
                      tokens: tokens,
                      label: 'Back to diff',
                      onTap: onBack,
                    ),
                    if (onCopy != null) ...[
                      const SizedBox(width: 8),
                      _GhostActionChip(
                        tokens: tokens,
                        label: 'Copy',
                        onTap: onCopy!,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _GhostActionChip(
                      tokens: tokens,
                      label: 'Run again',
                      onTap: onRerun,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
              children: [
                if (review.verificationFailed &&
                    review.verificationError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.stateConflicted.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                          context.surfaceShader.geometry.radius),
                      border: Border.all(
                        color: tokens.stateConflicted.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${review.verificationError} Draft review is shown below.',
                            style: TextStyle(
                              color: tokens.textStrong,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _GhostActionChip(
                          tokens: tokens,
                          label: traceExpanded ? 'Hide trace' : 'Show trace',
                          onTap: onToggleTrace,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!review.verificationFailed &&
                    review.hasVerificationTrace &&
                    !traceExpanded) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _GhostActionChip(
                      tokens: tokens,
                      label: 'Show verification trace',
                      onTap: onToggleTrace,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                resonanceText(
                  review.summary,
                  tokens,
                  baseStyle: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                // Reasoning is soft-required at the parser layer (some
                // models omit `<summary_reasoning>`). Hide the whole
                // disclosure when there's nothing to disclose.
                if (review.reasoningReport.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ReviewDisclosureCard(
                    tokens: tokens,
                    label: 'Why this review landed here',
                    expanded: reasoningExpanded,
                    preview: review.reasoningReport,
                    onToggle: onToggleReasoning,
                    child: resonanceText(
                      review.reasoningReport,
                      tokens,
                      baseStyle: TextStyle(
                        color: tokens.textNormal,
                        fontSize: 11.2,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  review.findings.isEmpty ? 'No findings' : 'Findings',
                  style: TextStyle(
                    color: tokens.textStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (review.findings.isEmpty)
                  Text(
                    'No evidence-backed issues were surfaced for this commit scope.',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  )
                else
                  ...review.findings.map(
                    (finding) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ReviewFindingCard(
                        tokens: tokens,
                        finding: finding,
                        onOpenDiff: finding.filePath == null
                            ? null
                            : () => onOpenFinding(finding.filePath!, finding.hunkLabel),
                      ),
                    ),
                  ),
                if (review.observations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Observations',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...review.observations.map(
                    (obs) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.rowBg,
                          borderRadius: BorderRadius.circular(
                              context.surfaceShader.geometry.radius),
                          border: Border.all(
                            color: tokens.chromeBorderFaint,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              obs.title,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (obs.detail.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              resonanceText(
                                obs.detail,
                                tokens,
                                baseStyle: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 10.5,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (review.twoStepEnabled &&
                    (review.hasVerificationTrace ||
                        review.verificationFailed ||
                        review.draftFindings.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  _TracePanel(
                    tokens: tokens,
                    expanded: traceExpanded,
                    onToggle: onToggleTrace,
                    verificationNotes: review.verificationNotes,
                    draftSummary: review.draftSummary,
                    draftReasoningReport: review.draftReasoningReport,
                    draftFindings: review.draftFindings,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewShell({required Widget child}) {
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 0,
      borderAlpha: 0,
      elevated: false,
      child: child,
    );
  }
}

class _ReviewVerdictChip extends StatelessWidget {
  final AppTokens tokens;
  final String verdict;

  const _ReviewVerdictChip({
    required this.tokens,
    required this.verdict,
  });

  @override
  Widget build(BuildContext context) {
    final color = _reviewVerdictColor(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        verdict,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _reviewVerdictColor(String verdict) => AppSeverityPalette.fromVerdict(verdict);

class _ReviewScorePill extends StatelessWidget {
  final AppTokens tokens;
  final int score;
  final String verdict;
  final int guardrailStage; // 0=loose, 1=balanced, 2=strict, 3=paranoid

  const _ReviewScorePill({
    required this.tokens,
    required this.score,
    required this.verdict,
    required this.guardrailStage,
  });

  @override
  Widget build(BuildContext context) {
    final verdictColor = _reviewVerdictColor(verdict);
    const size = 32.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          score: score,
          verdictColor: verdictColor,
          guardrailStage: guardrailStage,
          bgColor: tokens.chromeBorder.withValues(alpha: 0.1),
        ),
        child: Center(
          child: Text(
            '$score',
            style: TextStyle(
              color: verdictColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final int score;
  final Color verdictColor;
  final int guardrailStage;
  final Color bgColor;

  const _ScoreRingPainter({
    required this.score,
    required this.verdictColor,
    required this.guardrailStage,
    required this.bgColor,
  });

  /// Build the outline path for the guardrail shape.
  /// 0 = circle, 1 = squished diamond, 2 = shield, 3 = fortress.
  Path _shapePath(Offset center, double r) {
    final cx = center.dx;
    final cy = center.dy;
    switch (guardrailStage.clamp(0, 3)) {
      case 0:
        // ── Loose: plain circle ──
        return Path()..addOval(Rect.fromCircle(center: center, radius: r));

      case 1:
        // ── Balanced: rounded square ──
        final rect = Rect.fromCircle(center: center, radius: r);
        final cornerR = r * 0.38;
        return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(cornerR)));

      case 2:
        // ── Strict: shield ──
        final w = r * 0.92;
        final top = cy - r;
        return Path()
          ..moveTo(cx, top)                                   // crown
          ..lineTo(cx + w, cy - r * 0.5)                      // right shoulder
          ..lineTo(cx + w, cy + r * 0.15)                     // right waist
          ..quadraticBezierTo(cx, cy + r * 1.05, cx, cy + r)  // right curve → bottom point
          ..quadraticBezierTo(cx, cy + r * 1.05, cx - w, cy + r * 0.15) // bottom point → left curve
          ..lineTo(cx - w, cy - r * 0.5)                      // left shoulder
          ..close();

      default:
        // ── Paranoid: fortress / crenellated octagon ──
        // Octagon with notched battlements at the cardinal points.
        final pts = <Offset>[];
        final notchDepth = r * 0.15;
        for (int i = 0; i < 8; i++) {
          final angle = -math.pi / 2 + (i / 8) * 2 * math.pi;
          final nextAngle = -math.pi / 2 + ((i + 1) / 8) * 2 * math.pi;
          // Outer vertex
          pts.add(Offset(
            cx + r * math.cos(angle),
            cy + r * math.sin(angle),
          ));
          // Battlement notch at midpoint of each edge (inward)
          final midAngle = (angle + nextAngle) / 2;
          final notchR = r - notchDepth;
          pts.add(Offset(
            cx + notchR * math.cos(midAngle - 0.08),
            cy + notchR * math.sin(midAngle - 0.08),
          ));
          pts.add(Offset(
            cx + notchR * math.cos(midAngle + 0.08),
            cy + notchR * math.sin(midAngle + 0.08),
          ));
        }
        final path = Path()..moveTo(pts[0].dx, pts[0].dy);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        path.close();
        return path;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 1.5;
    const strokeWidth = 2.5;

    final shape = _shapePath(center, radius);

    // Background shape outline.
    canvas.drawPath(
      shape,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );

    // Score progress — draw a portion of the shape's perimeter.
    final scoreFraction = (score / 100).clamp(0.0, 1.0);
    final metrics = shape.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
      final drawLength = totalLength * scoreFraction;

      final scorePaint = Paint()
        ..color = verdictColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      double drawn = 0;
      for (final metric in metrics) {
        if (drawn >= drawLength) break;
        final segLen = (drawLength - drawn).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(0, segLen), scorePaint);
        drawn += metric.length;
      }
    }
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.score != score ||
      old.verdictColor != verdictColor ||
      old.guardrailStage != guardrailStage;
}

class _ReviewMetaChip extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final Color color;

  const _ReviewMetaChip({
    required this.tokens,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReviewDisclosureCard extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final bool expanded;
  final String preview;
  final VoidCallback onToggle;
  final Widget child;

  const _ReviewDisclosureCard({
    required this.tokens,
    required this.label,
    required this.expanded,
    required this.preview,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.rowBg,
        borderRadius:
            BorderRadius.circular(context.surfaceShader.geometry.radius),
        border: Border.all(color: tokens.chromeBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!expanded) ...[
                          const SizedBox(height: 5),
                          Text(
                            _oneLinePreview(preview),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textNormal,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: tokens.textMuted,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: child,
            ),
        ],
      ),
    );
  }

  String _oneLinePreview(String value) {
    final normalized = value.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}...';
  }
}

class _ReviewFindingCard extends StatelessWidget {
  final AppTokens tokens;
  final AiCommitReviewFindingData finding;
  final VoidCallback? onOpenDiff;

  const _ReviewFindingCard({
    required this.tokens,
    required this.finding,
    this.onOpenDiff,
  });

  @override
  Widget build(BuildContext context) {
    final accent = switch (finding.severity) {
      'block' => AppSeverityPalette.critical,
      'risk' => AppSeverityPalette.risk,
      'warn' => AppSeverityPalette.caution,
      'note' => AppSeverityPalette.info,
      _ => AppSeverityPalette.neutral,
    };
    final meta = [
      if (finding.filePath != null) finding.filePath!,
      if (finding.hunkLabel != null) finding.hunkLabel!,
    ].join(' | ');
    return IntrinsicHeight(
      child: Container(
      decoration: BoxDecoration(
        color: tokens.rowBg,
        borderRadius:
            BorderRadius.circular(context.surfaceShader.geometry.radius),
        border: Border.all(color: tokens.chromeBorderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Accent left edge — communicates severity at a glance.
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          finding.title,
                          style: TextStyle(
                            color: tokens.textStrong,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (onOpenDiff != null) ...[
                        const SizedBox(width: 8),
                        _InlineActionLink(
                          tokens: tokens,
                          label: 'Open diff',
                          onTap: onOpenDiff!,
                        ),
                      ],
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      meta,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10.5,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ],
                  if (finding.evidence.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    resonanceText(
                      finding.evidence,
                      tokens,
                      baseStyle: TextStyle(
                        color: tokens.textNormal,
                        fontSize: 11.2,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (finding.whyItMatters.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: tokens.textMuted.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                      ),
                      child: resonanceText(
                        finding.whyItMatters,
                        tokens,
                        baseStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _TracePanel extends StatelessWidget {
  final AppTokens tokens;
  final bool expanded;
  final VoidCallback onToggle;
  final String? verificationNotes;
  final String? draftSummary;
  final String? draftReasoningReport;
  final List<AiCommitReviewFindingData> draftFindings;

  const _TracePanel({
    required this.tokens,
    required this.expanded,
    required this.onToggle,
    required this.verificationNotes,
    required this.draftSummary,
    required this.draftReasoningReport,
    required this.draftFindings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.rowBg,
        borderRadius:
            BorderRadius.circular(context.surfaceShader.geometry.radius),
        border: Border.all(color: tokens.chromeBorderSubtle),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Verification trace',
                      style: TextStyle(
                        color: tokens.textStrong,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: tokens.textMuted,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (verificationNotes != null &&
                      verificationNotes!.trim().isNotEmpty) ...[
                    Text(
                      verificationNotes!,
                      style: TextStyle(
                        color: tokens.textNormal,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (draftSummary != null && draftSummary!.trim().isNotEmpty) ...[
                    Text(
                      'Draft review',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      draftSummary!,
                      style: TextStyle(
                        color: tokens.textStrong,
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (draftReasoningReport != null &&
                      draftReasoningReport!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      draftReasoningReport!,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (draftFindings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final finding in draftFindings.take(5))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• ${finding.title}',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10.8,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CleanTreeDashboard extends StatefulWidget {
  final AppTokens tokens;
  final RepositoryStatus status;
  final String repoPath;
  final VoidCallback onRefresh;

  const _CleanTreeDashboard({
    required this.tokens,
    required this.status,
    required this.repoPath,
    required this.onRefresh,
  });

  @override
  State<_CleanTreeDashboard> createState() => _CleanTreeDashboardState();
}

class _CleanTreeDashboardState extends State<_CleanTreeDashboard> {
  bool _fetching = false;

  Future<void> _fetch() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    try {
      await fetchRemote(widget.repoPath, prune: true);
      widget.onRefresh();
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final s = widget.status;
    final aheadColor = s.ahead > 0 ? AppSeverityPalette.caution : AppSeverityPalette.safe;
    final behindColor = s.behind > 0 ? AppSeverityPalette.caution : AppSeverityPalette.safe;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Working tree clean',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No staged or unstaged changes detected.',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            // Branch → upstream
            Text.rich(
              TextSpan(
                style: TextStyle(color: t.textMuted, fontSize: 11),
                children: [
                  TextSpan(
                    text: s.branch,
                    style: TextStyle(
                      color: t.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (s.upstream != null) ...[
                    TextSpan(
                      text: '  →  ',
                      style: TextStyle(color: t.textFaint),
                    ),
                    TextSpan(text: s.upstream),
                  ] else
                    const TextSpan(
                      text: '  ·  no upstream',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Ahead · Behind
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '↑ ${s.ahead}',
                  style: TextStyle(
                    color: aheadColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
                Text(
                  ' ahead',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
                Text(
                  '  ·  ',
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
                Text(
                  '↓ ${s.behind}',
                  style: TextStyle(
                    color: behindColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
                Text(
                  ' behind',
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GhostActionChip(
              tokens: t,
              label: _fetching ? 'Checking...' : 'Check remote',
              fetching: _fetching,
              onTap: _fetch,
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostActionChip extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final bool fetching;
  final VoidCallback onTap;

  const _GhostActionChip({
    required this.tokens,
    required this.label,
    this.fetching = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GhostActionChipButton(
      tokens: tokens,
      label: label,
      fetching: fetching,
      onTap: onTap,
    );
  }
}

class _GhostActionChipButton extends StatefulWidget {
  final AppTokens tokens;
  final String label;
  final bool fetching;
  final VoidCallback onTap;

  const _GhostActionChipButton({
    required this.tokens,
    required this.label,
    this.fetching = false,
    required this.onTap,
  });

  @override
  State<_GhostActionChipButton> createState() => _GhostActionChipButtonState();
}

class _GhostActionChipButtonState extends State<_GhostActionChipButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ghostButtonChrome(
      widget.tokens,
      hovered: _hovered,
      pressed: _pressed,
      enabled: true,
      baseBorderColor: widget.tokens.chromeBorder.withValues(alpha: 0.16),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 80),
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: chrome.background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.tokens.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineActionLink extends StatefulWidget {
  final AppTokens tokens;
  final String label;
  final VoidCallback onTap;

  const _InlineActionLink({
    required this.tokens,
    required this.label,
    required this.onTap,
  });

  @override
  State<_InlineActionLink> createState() => _InlineActionLinkState();
}

class _InlineActionLinkState extends State<_InlineActionLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? widget.tokens.textStrong : widget.tokens.accentBright;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            color: color,
            fontSize: 10.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.t,
    required this.enabled,
    required this.onTap,
    this.primary = true,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = widget.primary
        ? primaryButtonChrome(
            t,
            hovered: _hovered,
            pressed: _pressed,
            enabled: widget.enabled,
          )
        : ghostButtonChrome(
            t,
            hovered: _hovered,
            pressed: _pressed,
            enabled: widget.enabled,
            baseBorderColor: t.secondaryBtnBorder,
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
          duration: context.motion(const Duration(milliseconds: 100)),
          height: 28,
          decoration: BoxDecoration(
            color: chrome.background,
            gradient: chrome.gradient,
            borderRadius:
                BorderRadius.circular(context.surfaceShader.geometry.radius),
            border: Border.all(color: chrome.borderColor),
            boxShadow: chrome.shadows,
          ),
          child: Transform.translate(
            offset: chrome.offset,
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.primary
                      ? (widget.enabled ? t.btnText : t.textMuted)
                      : (widget.enabled ? t.textNormal : t.textMuted),
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

// ── Split commit button ───────────────────────────────────────────────────────

class _SplitCommitBtn extends StatefulWidget {
  final String label;
  final String alternateLabel;
  final bool commitOnlyMode;
  final AppTokens t;
  final bool enabled;
  final bool aiGenerating;
  final bool actionRunning;
  final VoidCallback onCommit;
  final VoidCallback onToggleMode;

  const _SplitCommitBtn({
    required this.label,
    required this.alternateLabel,
    required this.commitOnlyMode,
    required this.t,
    required this.enabled,
    required this.aiGenerating,
    this.actionRunning = false,
    required this.onCommit,
    required this.onToggleMode,
  });

  @override
  State<_SplitCommitBtn> createState() => _SplitCommitBtnState();
}

class _SplitCommitBtnState extends State<_SplitCommitBtn> {
  bool _mainHovered = false;
  bool _mainPressed = false;
  bool _chevronHovered = false;
  bool _chevronPressed = false;

  bool get _anyHovered => _mainHovered || _chevronHovered;
  bool get _anyPressed => _mainPressed && !_chevronPressed;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = primaryButtonChrome(
      t,
      hovered: _anyHovered,
      pressed: _anyPressed,
      enabled: widget.enabled,
    );

    return AnimatedOpacity(
      duration: context.motion(const Duration(milliseconds: 180)),
      opacity: widget.aiGenerating && !_anyHovered ? 0.45 : 1.0,
      child: Transform.translate(
      offset: chrome.offset,
      child: Transform.scale(
        scale: chrome.scale,
        child: SizedBox(
          height: 36,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 100)),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius:
                  BorderRadius.circular(context.surfaceShader.geometry.radius),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  (context.surfaceShader.geometry.radius - 1)
                      .clamp(0, double.infinity)),
              child: Row(
                children: [
                  // ── Main action area ──────────────────────────────────────
                  Expanded(
                    child: MouseRegion(
                      cursor: widget.enabled
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onEnter: (_) => setState(() => _mainHovered = true),
                      onExit: (_) => setState(() => _mainHovered = false),
                      child: GestureDetector(
                        onTap: widget.enabled ? widget.onCommit : null,
                        onTapDown: widget.enabled
                            ? (_) => setState(() => _mainPressed = true)
                            : null,
                        onTapCancel: () =>
                            setState(() => _mainPressed = false),
                        onTapUp: (_) =>
                            setState(() => _mainPressed = false),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedPushIcon(
                                state: widget.actionRunning
                                    ? IconAnimState.loading
                                    : _mainHovered
                                        ? IconAnimState.hovered
                                        : IconAnimState.idle,
                                color: widget.enabled
                                    ? t.btnText
                                    : t.textMuted,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                widget.label,
                                style: TextStyle(
                                  color: widget.enabled
                                      ? t.btnText
                                      : t.textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── Divider ───────────────────────────────────────────────
                  Container(
                    width: 1,
                    height: 18,
                    color: t.chromeBorder
                        .withValues(alpha: _anyHovered ? 0.35 : 0.22),
                  ),
                  // ── Mode toggle ───────────────────────────────────────────
                  Tooltip(
                    message: 'Switch to: ${widget.alternateLabel}',
                    waitDuration: const Duration(milliseconds: 600),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) =>
                          setState(() => _chevronHovered = true),
                      onExit: (_) =>
                          setState(() => _chevronHovered = false),
                      child: GestureDetector(
                        onTap: widget.onToggleMode,
                        onTapDown: (_) =>
                            setState(() => _chevronPressed = true),
                        onTapCancel: () =>
                            setState(() => _chevronPressed = false),
                        onTapUp: (_) =>
                            setState(() => _chevronPressed = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          width: 32,
                          color: widget.commitOnlyMode
                              ? t.accentBright.withValues(alpha:
                                  _chevronHovered ? 0.18 : 0.10)
                              : Colors.white.withValues(
                                  alpha: _chevronHovered ? 0.10 : 0.0),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration:
                                  context.motion(const Duration(milliseconds: 250)),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, anim) {
                                return FadeTransition(
                                  opacity: anim,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.6,
                                      end: 1.0,
                                    ).animate(anim),
                                    child: child,
                                  ),
                                );
                              },
                              child: widget.commitOnlyMode
                                  ? AnimatedSyncIcon(
                                      key: const ValueKey('sync'),
                                      state: _chevronHovered
                                          ? IconAnimState.hovered
                                          : IconAnimState.idle,
                                      color: t.accentBright
                                          .withValues(alpha: 0.80),
                                      size: 14,
                                    )
                                  : AnimatedCommitIcon(
                                      key: const ValueKey('commit'),
                                      state: _chevronHovered
                                          ? IconAnimState.hovered
                                          : IconAnimState.idle,
                                      color: t.btnText
                                          .withValues(alpha: 0.80),
                                      size: 14,
                                    ),
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
      ),
    );
  }
}

// ── Shape-ask split button ───────────────────────────────────────────────
//
// Inline replacement for `_SplitCommitBtn` while the composer is in
// shape mode. Same chrome (primaryButtonChrome, same height/radius/border)
// so the morph from commit-button to shape-ask-button reads as the SAME
// button changing identity, not a different control. Main area asks the
// AI for a subset patch; the chevron CYCLES through configured AI
// categories on each click (instead of opening a menu).
class _ShapeAskButton extends StatefulWidget {
  final AppTokens tokens;
  final List<String> categories;
  final int categoryIndex;
  final bool busy;
  final bool enabled;
  /// Forward cycle (click or Space). Chevron.
  final VoidCallback onCycle;
  /// Backward cycle (shift-click on chevron). Optional — dropped when
  /// only 1 or 2 categories are configured (backward == forward).
  final VoidCallback? onCycleBack;
  final VoidCallback onAsk;

  const _ShapeAskButton({
    required this.tokens,
    required this.categories,
    required this.categoryIndex,
    required this.busy,
    required this.enabled,
    required this.onCycle,
    this.onCycleBack,
    required this.onAsk,
  });

  @override
  State<_ShapeAskButton> createState() => _ShapeAskButtonState();
}

class _ShapeAskButtonState extends State<_ShapeAskButton> {
  bool _mainHovered = false;
  bool _mainPressed = false;
  bool _chevronHovered = false;
  bool _chevronPressed = false;

  bool get _anyHovered => _mainHovered || _chevronHovered;
  bool get _anyPressed => _mainPressed && !_chevronPressed;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hasCats = widget.categories.isNotEmpty;
    final activeCat = hasCats
        ? widget.categories[
            widget.categoryIndex.clamp(0, widget.categories.length - 1)]
        : '';
    final chrome = primaryButtonChrome(
      t,
      hovered: _anyHovered,
      pressed: _anyPressed,
      enabled: widget.enabled && hasCats,
    );

    final mainEnabled = widget.enabled && hasCats && !widget.busy;
    final chevEnabled = hasCats && widget.categories.length > 1;

    // Two-layer split: the VISUAL sits inside Transform.translate/scale
    // so chrome (offset + scale on hover/press) reads as depth. The
    // HIT-TEST layer is a Stack sibling that stays at a fixed size so
    // MouseRegion/GestureDetector bounds never shift mid-interaction.
    // This fixes the "needs to be spammed" oscillation caused by the
    // transform moving the target out from under the pointer near edges.
    final visual = IgnorePointer(
      child: Transform.translate(
        offset: chrome.offset,
        child: Transform.scale(
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 100)),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(
                  context.surfaceShader.geometry.radius),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  (context.surfaceShader.geometry.radius - 1)
                      .clamp(0, double.infinity)),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '↵',
                            style: TextStyle(
                              color: mainEnabled ? t.btnText : t.textMuted,
                              fontSize: 12,
                              fontFamily: 'JetBrainsMono',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedSwitcher(
                            duration: context.motion(
                                const Duration(milliseconds: 140)),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: Text(
                              hasCats
                                  ? widget.busy
                                      ? 'asking with $activeCat…'
                                      : 'ask with $activeCat'
                                  : 'no AI model configured',
                              key: ValueKey('${widget.busy}|$activeCat'),
                              style: TextStyle(
                                color: mainEnabled ? t.btnText : t.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 18,
                    color: t.chromeBorder
                        .withValues(alpha: _anyHovered ? 0.35 : 0.22),
                  ),
                  SizedBox(
                    width: 32,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      color: Colors.white.withValues(
                          alpha: _chevronHovered ? 0.10 : 0.0),
                      child: Center(
                        child: Text(
                          '▾',
                          style: TextStyle(
                            color: t.btnText.withValues(alpha: 0.80),
                            fontSize: 12,
                            fontFamily: 'JetBrainsMono',
                            fontWeight: FontWeight.w800,
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

    // Hit-test layer — fixed-size, outside any transform, so bounds are
    // stable across hover/press state changes.
    final hitTest = Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: mainEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _mainHovered = true),
            onExit: (_) => setState(() => _mainHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: mainEnabled ? widget.onAsk : null,
              onTapDown: mainEnabled
                  ? (_) => setState(() => _mainPressed = true)
                  : null,
              onTapCancel: () => setState(() => _mainPressed = false),
              onTapUp: (_) => setState(() => _mainPressed = false),
            ),
          ),
        ),
        const SizedBox(width: 1), // divider slot — no hit target
        Tooltip(
          message: chevEnabled
              ? 'next: ${widget.categories[(widget.categoryIndex + 1) % widget.categories.length]}  ·  shift-click for previous'
              : 'only one AI category configured',
          waitDuration: const Duration(milliseconds: 600),
          child: SizedBox(
            width: 32,
            child: MouseRegion(
              cursor: chevEnabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onEnter: (_) => setState(() => _chevronHovered = true),
              onExit: (_) => setState(() => _chevronHovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: chevEnabled
                    ? () {
                        final shift =
                            HardwareKeyboard.instance.isShiftPressed;
                        if (shift && widget.onCycleBack != null) {
                          widget.onCycleBack!();
                        } else {
                          widget.onCycle();
                        }
                      }
                    : null,
                onTapDown: (_) => setState(() => _chevronPressed = true),
                onTapCancel: () => setState(() => _chevronPressed = false),
                onTapUp: (_) => setState(() => _chevronPressed = false),
              ),
            ),
          ),
        ),
      ],
    );

    return AnimatedOpacity(
      duration: context.motion(const Duration(milliseconds: 180)),
      opacity: widget.busy && !_anyHovered ? 0.45 : 1.0,
      child: SizedBox(
        height: 36,
        child: Stack(
          children: [
            Positioned.fill(child: visual),
            Positioned.fill(child: hitTest),
          ],
        ),
      ),
    );
  }
}

// ── Shelf control (merged shelve + expand button) ─────────────────────────
//
// One unified pill that replaces the former split "↓ shelve" vs "N shelved ▾"
// buttons. When shelves exist the pill shows both segments — left toggles the
// cabinet open/closed, right adds another shelf — with a hairline divider
// between them so the two actions read as one artifact.

class _ShelfControl extends StatefulWidget {
  final AppTokens tokens;
  final int count;
  final bool loading;
  final bool expanded;
  final bool canShelve;
  final VoidCallback? onShelve;
  final VoidCallback? onToggleExpanded;

  const _ShelfControl({
    required this.tokens,
    required this.count,
    required this.loading,
    required this.expanded,
    required this.canShelve,
    required this.onShelve,
    required this.onToggleExpanded,
  });

  @override
  State<_ShelfControl> createState() => _ShelfControlState();
}

class _ShelfControlState extends State<_ShelfControl> {
  int _hoverSegment = 0; // 0 none, 1 toggle, 2 shelve

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hasShelves = widget.count > 0;
    final borderColor = t.chromeBorder.withValues(alpha: 0.25);

    Widget segment({
      required String text,
      required VoidCallback? onTap,
      required int id,
      required Color baseColor,
      BorderRadius? radius,
    }) {
      final hovered = _hoverSegment == id && onTap != null;
      return MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hoverSegment = id),
        onExit: (_) => setState(
            () => _hoverSegment = _hoverSegment == id ? 0 : _hoverSegment),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hovered
                  ? t.chromeAccent.withValues(alpha: 0.08)
                  : t.chromeAccent.withValues(alpha: 0),
              borderRadius: radius,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: onTap == null
                    ? baseColor.withValues(alpha: 0.35)
                    : baseColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    if (!hasShelves && !widget.loading) {
      // Single-purpose pill: just shelve.
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: segment(
          text: '↓ shelve',
          onTap: widget.canShelve ? widget.onShelve : null,
          id: 2,
          baseColor: t.textMuted,
          radius: BorderRadius.circular(4),
        ),
      );
    }

    // Two-segment pill with hairline divider.
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              text: widget.loading
                  ? '…'
                  : '${widget.count} shelved ${widget.expanded ? '▾' : '▸'}',
              onTap: widget.onToggleExpanded,
              id: 1,
              baseColor: t.chromeAccent.withValues(alpha: 0.85),
              radius: const BorderRadius.horizontal(left: Radius.circular(4)),
            ),
            Container(width: 1, color: borderColor),
            segment(
              text: '↓',
              onTap: widget.canShelve ? widget.onShelve : null,
              id: 2,
              baseColor: t.textMuted,
              radius:
                  const BorderRadius.horizontal(right: Radius.circular(4)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stash drawer card ─────────────────────────────────────────────────────
//
// Filing-cabinet divider. Header shows label + age + file count and toggles
// open/closed on click. When open, the card reveals the file list with
// per-file add/del counts and exposes the action strip (pick up, peek, toss).

class _StashDrawerCard extends StatefulWidget {
  final AppTokens tokens;
  final StashEntryData stash;
  final bool isPeeking;
  final bool isOpen;
  final List<StashFileStat>? files;
  final bool filesLoading;
  final VoidCallback onToggleOpen;
  final VoidCallback onPickUp;
  final VoidCallback onPeek;
  final VoidCallback onToss;

  const _StashDrawerCard({
    required this.tokens,
    required this.stash,
    required this.isPeeking,
    required this.isOpen,
    required this.files,
    required this.filesLoading,
    required this.onToggleOpen,
    required this.onPickUp,
    required this.onPeek,
    required this.onToss,
  });

  @override
  State<_StashDrawerCard> createState() => _StashDrawerCardState();
}

class _StashDrawerCardState extends State<_StashDrawerCard> {
  bool _hovered = false;

  /// Strips git's auto-generated `WIP on <branch>: <shorthash> <msg>` /
  /// `On <branch>: <msg>` prefixes, but ONLY when they match the strict
  /// autogen shape — user-supplied labels that happen to start with "WIP"
  /// are left alone.
  static String _displayLabel(String raw) {
    // Strict WIP form: branch token has no colon; hash is 7-40 hex; tail non-empty.
    final wip = RegExp(r'^WIP on ([^:\s]+): ([0-9a-f]{7,40}) (.+)$')
        .firstMatch(raw);
    if (wip != null) return wip.group(3)!;
    final on = RegExp(r'^On ([^:\s]+): (.+)$').firstMatch(raw);
    if (on != null) return on.group(2)!;
    return raw;
  }

  static String _relativeAge(String iso) {
    try {
      final t = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(t);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
      return '${(diff.inDays / 365).floor()}y ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final stash = widget.stash;
    final label = _displayLabel(stash.message);
    final age = _relativeAge(stash.createdAt);

    final Color surfaceColor = widget.isPeeking
        ? t.itemActiveBg
        : (widget.isOpen
            ? t.surface1.withValues(alpha: 0.6)
            : (_hovered
                ? t.secondaryBtnHoverBg
                : t.secondaryBtnHoverBg.withValues(alpha: 0)));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(5),
          border: widget.isPeeking
              ? Border.all(color: t.chromeAccent.withValues(alpha: 0.35))
              : (widget.isOpen
                  ? Border.all(
                      color: t.chromeBorder.withValues(alpha: 0.25))
                  : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Divider header ────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggleOpen,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    // Chevron — rotates via AnimatedRotation.
                    AnimatedRotation(
                      turns: widget.isOpen ? 0.25 : 0,
                      duration: context.motion(
                          const Duration(milliseconds: 120)),
                      child: Text(
                        '▸',
                        style: TextStyle(
                          color: t.textMuted.withValues(alpha: 0.8),
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: t.textNormal,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${stash.fileCount} file${stash.fileCount == 1 ? '' : 's'}'
                            '${age.isEmpty ? '' : ' · $age'}',
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Quick actions (hover-revealed on collapsed rows to
                    // stay uncluttered; always visible when open).
                    if (_hovered ||
                        widget.isPeeking ||
                        widget.isOpen) ...[
                      _StashAction(
                        icon: '↑',
                        tooltip: 'pick up',
                        color: t.accentBright,
                        onTap: widget.onPickUp,
                      ),
                      const SizedBox(width: 6),
                      _StashAction(
                        icon: widget.isPeeking ? '◉' : '◎',
                        tooltip: 'peek',
                        color: t.chromeAccent,
                        onTap: widget.onPeek,
                      ),
                      const SizedBox(width: 6),
                      _StashAction(
                        icon: '×',
                        tooltip: 'toss',
                        color: t.textMuted,
                        onTap: widget.onToss,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ── Drawer contents ───────────────────────────────────────
            if (widget.isOpen)
              _StashDrawerContents(
                tokens: t,
                files: widget.files,
                loading: widget.filesLoading,
              ),
          ],
        ),
      ),
    );
  }
}

class _StashDrawerContents extends StatelessWidget {
  final AppTokens tokens;
  final List<StashFileStat>? files;
  final bool loading;

  const _StashDrawerContents({
    required this.tokens,
    required this.files,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final divider = Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: t.chromeBorder.withValues(alpha: 0.18),
    );

    Widget body;
    if (loading && (files == null || files!.isEmpty)) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 12, 10),
        child: Text(
          'reading shelf…',
          style: TextStyle(color: t.textMuted, fontSize: 10),
        ),
      );
    } else if (files == null || files!.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 12, 10),
        child: Text(
          'empty shelf',
          style: TextStyle(color: t.textMuted, fontSize: 10),
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in files!) _StashFileRow(tokens: t, file: f),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [divider, body],
    );
  }
}

class _StashFileRow extends StatelessWidget {
  final AppTokens tokens;
  final StashFileStat file;

  const _StashFileRow({required this.tokens, required this.file});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              file.path,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 10.5,
                fontFamily: 'JetBrainsMono',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (file.binary)
            Text(
              'bin',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 9,
                fontFamily: 'JetBrainsMono',
              ),
            )
          else ...[
            Text(
              '+${file.adds}',
              style: TextStyle(
                color: t.stateAdded,
                fontSize: 9.5,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '−${file.dels}',
              style: TextStyle(
                color: t.stateDeleted,
                fontSize: 9.5,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StashAction extends StatelessWidget {
  final String icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _StashAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          icon,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}


class _FileRow extends StatefulWidget {
  final RepositoryStatusFile file;
  final AppTokens tokens;
  final bool isDiffSelected;
  final bool included;
  final VoidCallback onTap;
  final ValueChanged<bool> onIncludeChanged;
  /// Cluster stripe color. Null = no coupling signal / matrix not ready.
  final Color? clusterColor;
  /// When true, stripe extends to the very top of the row (no inset, no
  /// rounded top) so it fuses with the previous row's stripe in the same
  /// cluster. Caller computes this from adjacent cluster ids.
  final bool stripeConnectTop;
  /// Same contract for the bottom edge.
  final bool stripeConnectBottom;
  /// Whether this file is part of a real coupling cluster (i.e., stripe
  /// is colored). Rail hover only activates on clustered rows.
  final bool inRealCluster;
  /// Coupling score between this row and the currently rail-hovered file.
  /// Null when nothing is hovered OR this row isn't in the hovered cluster.
  /// 1.0 iff this row IS the hover subject.
  final double? peerScore;
  /// True iff the mouse is over this row's own stripe.
  final bool isRailSubject;
  /// Called when the mouse enters this row's stripe. Null for non-clustered
  /// rows (no meaningful hover target).
  final VoidCallback? onRailEnter;
  /// Called when the mouse leaves this row's stripe.
  final VoidCallback? onRailExit;
  /// Right-click handler. Fires with the screen-space position of the
  /// pointer down event so the caller can position a context menu
  /// against it. Caller decides what menu items to show; the row is
  /// agnostic.
  final ValueChanged<Offset>? onSecondaryTap;

  const _FileRow({
    required this.file,
    required this.tokens,
    required this.isDiffSelected,
    required this.included,
    required this.onTap,
    required this.onIncludeChanged,
    this.clusterColor,
    this.stripeConnectTop = false,
    this.stripeConnectBottom = false,
    this.inRealCluster = false,
    this.peerScore,
    this.isRailSubject = false,
    this.onRailEnter,
    this.onRailExit,
    this.onSecondaryTap,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  List<_ChangeBadgeSpec> _buildBadges(AppTokens t, RepositoryStatusFile file) {
    final badges = <_ChangeBadgeSpec>[];
    final staged = _describeGitChange(file.staged, staged: true, tokens: t);
    final unstaged =
        _describeGitChange(file.unstaged, staged: false, tokens: t);

    if (staged != null) {
      badges.add(staged);
    }
    if (unstaged != null &&
        !badges.any(
          (badge) =>
              badge.label == unstaged.label && badge.color == unstaged.color,
        )) {
      badges.add(unstaged);
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final file = widget.file;
    final filename = file.path.split('/').last;
    final dir = file.path.contains('/')
        ? file.path.substring(0, file.path.lastIndexOf('/'))
        : '';
    final badges = _buildBadges(t, file);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onRailEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onRailExit?.call();
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cluster stripe — only rendered for files that belong to a
              // real coupling cluster. Isolated / standalone files get no
              // stripe or spacer at all, so the presence of a stripe is
              // itself the at-a-glance "coupled" signal. When consecutive
              // rows share a cluster the stripe runs edge-to-edge (no inset
              // / no rounding) so it visually fuses into one continuous
              // capsule spanning the group.
              // Stripe slot is ALWAYS reserved (3px stripe + 5px spacer)
              // so the checkbox / card column stays in the same x position
              // for every row, whether or not it's in a cluster. The
              // stripe's *color* is what changes: a theme-derived tint for
              // coupled files, transparent for isolated. Clustered rows in
              // sequence fuse edge-to-edge (no inset / no rounding) into a
              // continuous capsule spanning the group.
              // Rail — pure visual widget; hover is handled by the card's
              // outer MouseRegion so hovering anywhere on the card drives
              // the coupling visualization. Width pulses by coupling strength,
              // brightness fades by peer score.
              _RailStripe(
                tokens: t,
                clusterColor: widget.clusterColor,
                inRealCluster: widget.inRealCluster,
                peerScore: widget.peerScore,
                isRailSubject: widget.isRailSubject,
                connectTop: widget.stripeConnectTop,
                connectBottom: widget.stripeConnectBottom,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: widget.isDiffSelected
                        ? t.chromeBorder.withValues(alpha: 0.1)
                        : (widget.included
                            ? t.stateAdded.withValues(alpha: 0.05)
                            : (_hovered
                                ? t.itemHoverBg
                                : t.itemHoverBg.withValues(alpha: 0))),
                    borderRadius: BorderRadius.circular(
                        context.surfaceShader.geometry.radius),
                    border: Border.all(
                      color: widget.included
                          ? t.stateAdded.withValues(alpha: 0.18)
                          : t.stateAdded.withValues(alpha: 0),
                    ),
                  ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: widget.included,
                  onChanged: (value) => widget.onIncludeChanged(value ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: t.accentBright,
                  checkColor: t.bg0,
                  side:
                      BorderSide(color: t.chromeBorder.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      style: TextStyle(color: t.textNormal, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dir.isEmpty ? 'Repository root' : dir,
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 10,
                              fontFamily: 'JetBrainsMono',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (badges.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final badge in badges)
                      _StateBadge(label: badge.label, color: badge.color),
                  ],
                ),
            ],
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

class _ChangeBadgeSpec {
  final String label;
  final Color color;

  const _ChangeBadgeSpec({required this.label, required this.color});
}

/// Cluster stripe color derived from the active theme. Returns null for
/// isolated / standalone files — those render with no stripe at all, so the
/// visible stripes read purely as "here is a coupled group".
///
/// For real clusters we cycle through four semantic accents the theme
/// already defines and step the alpha down for the 5th+ cluster so distant
/// clusters fade rather than flash.
/// One vertical segment of the coupling rail. The stripe is the *only*
/// visualization layer — its width and alpha both modulate by coupling
/// score to the hovered subject, so moving the cursor along a long rail
/// produces a live gradient of stripe thickness + glow across the cluster.
/// Nothing else shifts; no labels enter the row's layout flow.
class _RailStripe extends StatelessWidget {
  final AppTokens tokens;
  final Color? clusterColor;
  final bool inRealCluster;
  final double? peerScore;
  final bool isRailSubject;
  final bool connectTop;
  final bool connectBottom;

  const _RailStripe({
    required this.tokens,
    required this.clusterColor,
    required this.inRealCluster,
    required this.peerScore,
    required this.isRailSubject,
    required this.connectTop,
    required this.connectBottom,
  });

  @override
  Widget build(BuildContext context) {
    final shader = themeDefinitionFor(tokens.id).shader;
    final reduceMotion = context.watch<PreferencesState>().reduceMotion;
    // Width: 3 at rest, 5 when this row is the subject, 2.5..4.5 for peers
    // proportional to score. Creates a physical "bulge" toward strong
    // peers, fading toward weak ones.
    final width = isRailSubject
        ? 5.0
        : peerScore == null
            ? 3.0
            : (2.5 + peerScore! * 2.0).clamp(2.5, 4.5);

    // Color: subject stays full cluster color; peers fade alpha by score;
    // unsubjected rails render steady.
    final base = clusterColor ?? Colors.transparent;
    final Color color;
    if (peerScore == null || isRailSubject) {
      color = base;
    } else {
      final scale = (0.15 + peerScore! * 0.95).clamp(0.15, 1.0);
      color = base.withValues(alpha: base.a * scale);
    }

    // Reserve the max rail width (5) so adjacent rows don't jitter when
    // one of them becomes the subject and widens. Stripe sizes inside
    // this slot; nothing in the row re-lays out.
    return SizedBox(
        width: 5,
        child: Padding(
          padding: EdgeInsets.only(
            top: connectTop ? 0 : 4,
            bottom: connectBottom ? 0 : 4,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : shader.duration,
              curve: shader.safeCurve,
              width: width,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.only(
                  topLeft: connectTop
                      ? Radius.zero
                      : const Radius.circular(1.5),
                  topRight: connectTop
                      ? Radius.zero
                      : const Radius.circular(1.5),
                  bottomLeft: connectBottom
                      ? Radius.zero
                      : const Radius.circular(1.5),
                  bottomRight: connectBottom
                      ? Radius.zero
                      : const Radius.circular(1.5),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

// `_clusterStripeColor` was promoted to `AppTokens.clusterStripeColor`
// in `lib/ui/tokens.dart` so the branches lens (PR file pills) and any
// future surface visualizing coupling share the exact same palette.
// Call sites updated to `t.clusterStripeColor(cid)` directly.

_ChangeBadgeSpec? _describeGitChange(
  String code, {
  required bool staged,
  required AppTokens tokens,
}) {
  switch (code.trim()) {
    case 'M':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged edit' : 'Edited',
        color: staged ? tokens.stateStaged : tokens.stateModified,
      );
    case 'A':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged add' : 'Added',
        color: tokens.stateAdded,
      );
    case 'D':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged delete' : 'Deleted',
        color: tokens.stateDeleted,
      );
    case 'R':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged rename' : 'Renamed',
        color: tokens.accentBright,
      );
    case 'C':
      return _ChangeBadgeSpec(
        label: staged ? 'Staged copy' : 'Copied',
        color: tokens.accentBright,
      );
    case 'U':
      return _ChangeBadgeSpec(
        label: 'Conflict',
        color: tokens.stateConflicted,
      );
    case '?':
      return _ChangeBadgeSpec(
        label: 'Untracked',
        color: tokens.stateAdded,
      );
    default:
      return null;
  }
}

class _StateBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StateBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CommitComposerField extends StatefulWidget {
  final AppTokens tokens;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  /// Hint shown when the bound `controller` is empty. Parent picks based
  /// on mode (commit message vs shape input).
  final String hintText;
  final bool aiEnabled;
  final bool aiLoading;
  final bool aiSuccess;
  final String aiTooltip;
  final bool reviewEnabled;
  final bool reviewLoading;
  final bool reviewSuccess;
  final String? reviewVerdict;
  final String reviewTooltip;
  final VoidCallback onGenerate;
  final VoidCallback onReview;
  final bool museEnabled;
  final bool museLoading;
  final bool museSuccess;
  final String museTooltip;
  final VoidCallback onMuse;
  /// Inline shape-commit mode. When true, the field binds the shape
  /// controller (parent swaps which controller is passed in based on
  /// this flag) and the ◈ button reads as a "exit shape" toggle.
  final bool shapeMode;
  final bool shapeEnabled;
  final bool shapeLoading;
  final String shapeTooltip;
  /// Toggles inline shape mode. Was previously `onShape` which opened
  /// a floating popover; now the parent owns the mode flag and the
  /// composer just morphs in place.
  final VoidCallback? onToggleShape;

  const _CommitComposerField({
    required this.tokens,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    this.hintText = 'Commit message...',
    required this.aiEnabled,
    required this.aiLoading,
    this.aiSuccess = false,
    required this.aiTooltip,
    required this.reviewEnabled,
    required this.reviewLoading,
    this.reviewSuccess = false,
    this.reviewVerdict,
    required this.reviewTooltip,
    required this.onGenerate,
    required this.onReview,
    this.museEnabled = false,
    this.museLoading = false,
    this.museSuccess = false,
    this.museTooltip = '',
    required this.onMuse,
    this.shapeMode = false,
    this.shapeEnabled = false,
    this.shapeLoading = false,
    this.shapeTooltip = '',
    this.onToggleShape,
  });

  @override
  State<_CommitComposerField> createState() => _CommitComposerFieldState();
}

class _CommitComposerFieldState extends State<_CommitComposerField>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _doneCtrl;
  final ScrollController _scrollCtrl = ScrollController();
  /// Cached merged listenable for the AnimatedBuilder. Was being
  /// reallocated every build (string-keyed text input fires per
  /// keystroke → 60+ rebuilds/sec → 60+ Listenable.merge allocs/sec).
  /// Rebuilt only when the parent swaps the controller/focus refs
  /// (mode switch).
  Listenable? _composerSignal;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _doneCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rebuildComposerSignal();
    // _pulseCtrl is gated via didChangeDependencies so Reduce Motion
    // silences the border pulse; _doneCtrl forwards only when motion is
    // allowed.
  }

  void _rebuildComposerSignal() {
    _composerSignal = Listenable.merge([
      _pulseCtrl,
      _doneCtrl,
      widget.focusNode,
      widget.controller,
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = context.reduceMotion;
    if (widget.aiLoading) {
      if (reduce) {
        if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
        _pulseCtrl.value = 0;
      } else if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(_CommitComposerField old) {
    super.didUpdateWidget(old);
    // Refresh the cached merged listenable only when the parent
    // swaps the controller or focus node (mode change). Avoids the
    // per-build reallocation of `Listenable.merge`.
    if (!identical(old.controller, widget.controller) ||
        !identical(old.focusNode, widget.focusNode)) {
      _rebuildComposerSignal();
    }
    final reduce = context.reduceMotionRead;
    if (widget.aiLoading && !old.aiLoading) {
      _doneCtrl.stop();
      if (!reduce) _pulseCtrl.repeat(reverse: true);
    } else if (!widget.aiLoading && old.aiLoading) {
      _pulseCtrl.stop();
      if (reduce) {
        _doneCtrl.value = 1; // land at the bloomed end-state without animating
      } else {
        _doneCtrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _doneCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final radius = themeDefinitionFor(tokens.id)
        .shader
        .geometry
        .radius
        .clamp(0, 18)
        .toDouble();
    final effectiveRadius = (radius * 0.75).clamp(0.0, 14.0);

    return AnimatedBuilder(
      animation: _composerSignal!,
      builder: (context, child) {
        final hasText = widget.controller.text.trim().isNotEmpty;
        final isFocused = widget.focusNode.hasFocus;
        final innerRadius = math.max(0.0, effectiveRadius - 1.5);

        // ── Border color + width ─────────────────────────────────
        final Color baseBorder = isFocused
            ? tokens.inputFocusBorder.withValues(alpha: 0.70)
            : tokens.inputBorder;

        Color borderColor;
        double borderWidth;

        if (widget.aiLoading) {
          // Pulse: width 1→1.5px + accent breathes 40%→100% alpha
          final pulse = _pulseCtrl.value;
          borderColor = tokens.accentBright.withValues(alpha: 0.40 + pulse * 0.60);
          borderWidth = 1.0 + pulse * 0.5;
        } else if (_doneCtrl.value > 0) {
          // Bloom: width 1→2→1px + accent at full alpha fading out
          final t = _doneCtrl.value;
          final sine = math.sin(math.pi * t);
          borderWidth = 1.0 + sine * 1.0;
          borderColor = tokens.accentBright.withValues(alpha: 0.70 + sine * 0.30);
        } else {
          borderColor =
              baseBorder.withValues(alpha: widget.enabled ? 1 : 0.45);
          borderWidth = 1.0;
        }

        return Container(
          height: 118,
          decoration: BoxDecoration(
            color: tokens.inputBg,
            borderRadius: BorderRadius.circular(effectiveRadius),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: Stack(
              children: [
                // ── Text fills the full field ──────────────────
                Positioned.fill(
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbColor: WidgetStateProperty.all(
                        tokens.textMuted.withValues(alpha: 0.28),
                      ),
                      thickness: WidgetStateProperty.all(3),
                      radius: const Radius.circular(2),
                      // Hug the right edge — no inset margin
                      crossAxisMargin: 2,
                      mainAxisMargin: 4,
                    ),
                    child: Scrollbar(
                      controller: _scrollCtrl,
                      child: ScrollbarTheme(
                        data: ScrollbarThemeData(
                          thickness: WidgetStateProperty.all(0),
                        ),
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          scrollController: _scrollCtrl,
                          enabled: widget.enabled,
                          minLines: null,
                          maxLines: null,
                          expands: true,
                          onChanged: widget.onChanged,
                          cursorColor: tokens.accentBright,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            color: tokens.textStrong,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: widget.hintText,
                            hintStyle: TextStyle(
                              color: tokens.textMuted.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontStyle: widget.shapeMode
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Floating AI button ─────────────────────────
                Positioned(
                  right: 7,
                  bottom: 7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onToggleShape != null) ...[
                        // Plain mode-toggle button — was an OverlayPortal-
                        // hosted popover; the inline shape-mode now
                        // morphs the same TextField + bottom button in
                        // place, so no overlay machinery needed.
                        _CommitAiToolbarBtn(
                          tokens: tokens,
                          enabled: widget.shapeEnabled || widget.shapeMode,
                          loading: widget.shapeLoading,
                          // When already in shape mode, treat as the
                          // active state so the button reads as armed
                          // (the next tap exits).
                          success: widget.shapeMode,
                          tooltip: widget.shapeTooltip,
                          hasText: hasText,
                          fieldRadius: effectiveRadius,
                          iconKind: _AiToolbarIconKind.shape,
                          onTap: widget.onToggleShape!,
                        ),
                        const SizedBox(width: 4),
                      ],
                      _CommitAiToolbarBtn(
                        tokens: tokens,
                        enabled: widget.museEnabled,
                        loading: widget.museLoading,
                        success: widget.museSuccess,
                        tooltip: widget.museTooltip,
                        hasText: hasText,
                        fieldRadius: effectiveRadius,
                        iconKind: _AiToolbarIconKind.oracle,
                        onTap: widget.onMuse,
                      ),
                      const SizedBox(width: 4),
                      _CommitAiToolbarBtn(
                        tokens: tokens,
                        enabled: widget.reviewEnabled,
                        loading: widget.reviewLoading,
                        success: widget.reviewSuccess,
                        verdict: widget.reviewVerdict,
                        tooltip: widget.reviewTooltip,
                        hasText: hasText,
                        fieldRadius: effectiveRadius,
                        iconKind: _AiToolbarIconKind.search,
                        onTap: widget.onReview,
                      ),
                      const SizedBox(width: 4),
                      _CommitAiToolbarBtn(
                        tokens: tokens,
                        enabled: widget.aiEnabled,
                        loading: widget.aiLoading,
                        success: widget.aiSuccess,
                        tooltip: widget.aiTooltip,
                        hasText: hasText,
                        fieldRadius: effectiveRadius,
                        iconKind: _AiToolbarIconKind.sparkle,
                        onTap: widget.onGenerate,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── AI toolbar button (lives inside the commit composer's bottom toolbar) ──────

enum _AiToolbarIconKind { search, sparkle, shape, oracle }

/// Shape glyph (`◈`) with state-aware motion. Idle is a still diamond.
/// Hover gently scales it up. The "active" state — used while inline
/// shape-mode is engaged — slowly rotates the diamond and emits a
/// periodic glint (a brief scale + brightness pulse) so the toolbar
/// reads as live without being noisy. Loading rotates faster, no glint
/// (the brightness-pulse would compete with the loading affordance).
class _AnimatedShapeIcon extends StatefulWidget {
  final IconAnimState state;
  final Color color;
  final double size;
  const _AnimatedShapeIcon({
    required this.state,
    required this.color,
    required this.size,
  });

  @override
  State<_AnimatedShapeIcon> createState() => _AnimatedShapeIconState();
}

class _AnimatedShapeIconState extends State<_AnimatedShapeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // 3.6s gives one revolution slow enough to feel ambient (not
    // distracting), with two glint pulses per cycle.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _syncTickerToState();
  }

  @override
  void didUpdateWidget(_AnimatedShapeIcon old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncTickerToState();
  }

  void _syncTickerToState() {
    final shouldAnimate = widget.state == IconAnimState.success ||
        widget.state == IconAnimState.loading;
    if (shouldAnimate) {
      // Loading runs at 1.6× the active cadence — visibly busier,
      // not just "kinda spinning."
      _ctrl.duration = widget.state == IconAnimState.loading
          ? const Duration(milliseconds: 2200)
          : const Duration(milliseconds: 3600);
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.state == IconAnimState.success;
    final isHovered = widget.state == IconAnimState.hovered;

    // RepaintBoundary isolates the rotating glyph's per-frame paint
    // from the surrounding toolbar button — without it, the parent
    // `_CommitAiToolbarBtn` decoration repaints every animation tick.
    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value; // 0..1
        // Two glint pulses per revolution. `pow(sin, 6)` makes each
        // pulse a sharp brief peak rather than a smooth sine — reads
        // as a "flash" instead of a slow brightness wave.
        final glintPhase = (t * 2.0) % 1.0;
        final raw = math.sin(glintPhase * math.pi);
        final glint = isActive ? math.pow(raw.abs(), 6).toDouble() : 0.0;

        // Slow continuous rotation when active; faster on loading.
        final rotation = (isActive || widget.state == IconAnimState.loading)
            ? t * 2 * math.pi
            : 0.0;

        // Scale: hover bumps slightly; active glints add a brief peak
        // on top of the base; loading just rotates without scaling.
        final base = isHovered ? 1.08 : 1.0;
        final scale = base + glint * 0.18;

        // Color: brighten on glint peak. Cap alpha at 1.
        final glintColor = Color.lerp(
          widget.color,
          widget.color.withValues(alpha: 1.0),
          glint,
        )!;

        return Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: Text(
              '◈',
              style: TextStyle(
                color: glintColor,
                fontSize: widget.size,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w800,
                height: 1.0,
                shadows: glint > 0.4
                    ? [
                        Shadow(
                          color: widget.color.withValues(alpha: glint * 0.6),
                          blurRadius: 4 + glint * 4,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      },
    ),
    );
  }
}

class _CommitAiToolbarBtn extends StatefulWidget {
  final AppTokens tokens;
  final bool enabled;
  final bool loading;
  final bool success;
  final String? verdict; // review verdict for search icon morph
  final String tooltip;
  final bool hasText; // de-emphasise when the user already typed something
  final double fieldRadius;
  final _AiToolbarIconKind iconKind;
  final VoidCallback onTap;

  const _CommitAiToolbarBtn({
    required this.tokens,
    required this.enabled,
    required this.loading,
    this.success = false,
    this.verdict,
    required this.tooltip,
    required this.hasText,
    required this.fieldRadius,
    required this.iconKind,
    required this.onTap,
  });

  @override
  State<_CommitAiToolbarBtn> createState() => _CommitAiToolbarBtnState();
}

class _CommitAiToolbarBtnState extends State<_CommitAiToolbarBtn> {
  bool _hovered = false;
  bool _pressed = false;

  IconAnimState get _iconState {
    if (widget.success) return IconAnimState.success;
    if (widget.loading) return IconAnimState.loading;
    if (_hovered && widget.enabled) return IconAnimState.hovered;
    return IconAnimState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final btnRadius = (widget.fieldRadius * 0.65).clamp(5.0, 8.0);

    // Icon colour: full accent when empty & enabled, dimmed when there's
    // already text (de-emphasise without hiding), muted when disabled.
    final iconOpacity = !widget.enabled
        ? 0.30
        : widget.hasText && !_hovered
            ? 0.50
            : 1.0;

    // Background: transparent normally, subtle tint on hover/press.
    final bgAlpha = _pressed
        ? 0.16
        : _hovered
            ? 0.10
            : 0.0;

    final iconColor = t.accentBright.withValues(alpha: iconOpacity);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel:
              widget.enabled ? () => setState(() => _pressed = false) : null,
          onTapUp:
              widget.enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: t.accentBright.withValues(alpha: bgAlpha),
              borderRadius: BorderRadius.circular(btnRadius),
            ),
            child: Center(
              child: switch (widget.iconKind) {
                _AiToolbarIconKind.search => AnimatedSearchIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 14,
                    verdict: widget.verdict,
                  ),
                _AiToolbarIconKind.sparkle => AnimatedSparkleIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 14,
                  ),
                _AiToolbarIconKind.shape => _AnimatedShapeIcon(
                    state: _iconState,
                    color: iconColor,
                    size: 13,
                  ),
                _AiToolbarIconKind.oracle => Icon(
                    Icons.bubble_chart_outlined,
                    color: iconColor,
                    size: 14,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Smart select toggle (file list header) ────────────────────────────────────

class _SmartSelectBtn extends StatefulWidget {
  final bool allSelected;
  final bool noneSelected;
  final bool enabled;
  final AppTokens tokens;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;

  const _SmartSelectBtn({
    required this.allSelected,
    required this.noneSelected,
    required this.enabled,
    required this.tokens,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  bool get isPartial => !allSelected && !noneSelected;

  @override
  State<_SmartSelectBtn> createState() => _SmartSelectBtnState();
}

class _SmartSelectBtnState extends State<_SmartSelectBtn> {
  // hover state for the single-button mode
  bool _hoveredSingle = false;
  // hover state for each half of the split mode
  bool _hoveredDeselect = false;
  bool _hoveredSelectAll = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final borderColor =
        t.secondaryBtnBorder.withValues(alpha: widget.enabled ? 0.72 : 0.28);

    Widget child;
    if (widget.isPartial) {
      // ── Split: [☐ deselect] | [☑ select all] ──────────────────────────
      child = KeyedSubtree(
        key: const ValueKey('partial'),
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _splitHalf(
                  t,
                  icon: Icons.check_box_outline_blank_rounded,
                  tooltip: 'Deselect all',
                  hovered: _hoveredDeselect,
                  onEnter: () => setState(() => _hoveredDeselect = true),
                  onExit: () => setState(() => _hoveredDeselect = false),
                  onTap: widget.onDeselectAll,
                ),
                Container(
                  width: 1,
                  color: borderColor,
                ),
                _splitHalf(
                  t,
                  icon: Icons.check_box_rounded,
                  tooltip: 'Select all',
                  hovered: _hoveredSelectAll,
                  onEnter: () => setState(() => _hoveredSelectAll = true),
                  onExit: () => setState(() => _hoveredSelectAll = false),
                  onTap: widget.onSelectAll,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // ── Single button: text + icon ──────────────────────────────────────
      final isSelectAll = widget.noneSelected;
      child = KeyedSubtree(
        key: ValueKey(isSelectAll),
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hoveredSingle = true),
          onExit: (_) => setState(() => _hoveredSingle = false),
          child: GestureDetector(
            onTap: widget.enabled
                ? (isSelectAll ? widget.onSelectAll : widget.onDeselectAll)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _hoveredSingle && widget.enabled
                    ? t.secondaryBtnHoverBg
                    : t.secondaryBtnHoverBg.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelectAll
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 12,
                    color: widget.enabled
                        ? t.textNormal.withValues(alpha: 0.80)
                        : t.textMuted.withValues(alpha: 0.40),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isSelectAll ? 'Select all' : 'Deselect all',
                    style: TextStyle(
                      color: widget.enabled ? t.textNormal : t.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }

  Widget _splitHalf(
    AppTokens t, {
    required IconData icon,
    required String tooltip,
    required bool hovered,
    required VoidCallback onEnter,
    required VoidCallback onExit,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: GestureDetector(
          onTap: widget.enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 28,
            color: hovered && widget.enabled
                ? t.secondaryBtnHoverBg
                : t.secondaryBtnHoverBg.withValues(alpha: 0),
            child: Center(
              child: Icon(
                icon,
                size: 13,
                color: widget.enabled
                    ? t.textNormal.withValues(alpha: hovered ? 1.0 : 0.65)
                    : t.textMuted.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Panel divider ─────────────────────────────────────────────────────────────

class _PanelDivider extends StatefulWidget {
  final AppTokens tokens;
  final ValueChanged<double> onDrag;

  const _PanelDivider({required this.tokens, required this.onDrag});

  @override
  State<_PanelDivider> createState() => _PanelDividerState();
}

class _PanelDividerState extends State<_PanelDivider> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final isActive = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        // don't clear _dragging here — pointer can leave during drag
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        onPanUpdate: (details) => widget.onDrag(details.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: _dragging ? 2.0 : 1.0,
              color: isActive
                  ? t.accentBright.withValues(alpha: _dragging ? 0.55 : 0.30)
                  : t.chromeBorder.withValues(alpha: 0.18),
            ),
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ────────────────────────────────────────────────────────────────────────
// Merge resolve strip — only visible when the working tree has UU files.
// Sits above the file list. One click resolves ALL conflicts across ALL
// files in a single AI call (tokens amortized, semantic coherence
// preserved). Chevron on the button's right edge offers to override the
// default model category — default is 'fast' (low-latency resolution)
// but pros can pick 'quality' for sticky refactor-heavy conflicts.
// ────────────────────────────────────────────────────────────────────────

class _MergeResolveStrip extends StatelessWidget {
  final Set<String> conflictedPaths;
  final int? totalHunks;
  final bool busy;
  final ValueChanged<String> onResolve;

  const _MergeResolveStrip({
    required this.conflictedPaths,
    required this.totalHunks,
    required this.busy,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ai = context.watch<AiSettingsState>();
    // Prefer 'fast' for resolution — low-latency, most conflicts are
    // mechanical. Fall back to any category that has a model configured.
    final defaultCategory = ai.modelSelections.containsKey('fast') &&
            ai.modelSelections['fast']!.isNotEmpty
        ? 'fast'
        : (ai.modelSelections.entries
                .firstWhere(
                  (e) => e.value.isNotEmpty,
                  orElse: () => const MapEntry('', ''),
                )
                .key);
    final count = conflictedPaths.length;
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 0,
      border: Border(
        top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.12)),
        bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.18)),
      ),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Text('◇',
              style: TextStyle(
                color: t.stateConflicted,
                fontSize: 14,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy
                  ? 'reading $count file${count == 1 ? '' : 's'} · drafting resolution…'
                  : '$count conflict${count == 1 ? '' : 's'} across $count file${count == 1 ? '' : 's'}',
              style: TextStyle(
                color: t.textNormal,
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (defaultCategory.isEmpty)
            Text('no AI model configured',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10.5,
                  fontFamily: 'JetBrainsMono',
                  fontStyle: FontStyle.italic,
                ))
          else
            _MergeResolveSplitButton(
              defaultCategoryId: defaultCategory,
              busy: busy,
              onResolve: onResolve,
            ),
        ],
      ),
    );
  }
}

/// Split button: main label click runs resolution with [defaultCategoryId];
/// chevron click opens a menu of the other configured categories so power
/// users can bump to 'quality' for a particularly gnarly conflict.
class _MergeResolveSplitButton extends StatefulWidget {
  final String defaultCategoryId;
  final bool busy;
  final ValueChanged<String> onResolve;
  /// Verb prefix shown before the category label. Merge resolver uses
  /// 'resolve with', shape-staging uses 'shape with'. Keeps the grammar
  /// aligned while letting one widget serve both features.
  final String actionLabel;
  /// When the button's chevron menu is hosted inside another overlay
  /// (e.g. the shape popover), passing the host's [TapRegion] groupId
  /// here makes the menu register in the same group. A tap on the menu
  /// then doesn't count as "outside" the host, so the host doesn't
  /// self-dismiss mid-menu-interaction — which otherwise disposes the
  /// button's State and invalidates the menu's LayerLink.
  final Object? menuTapRegionGroupId;
  const _MergeResolveSplitButton({
    required this.defaultCategoryId,
    required this.busy,
    required this.onResolve,
    this.actionLabel = 'resolve with',
    this.menuTapRegionGroupId,
  });
  @override
  State<_MergeResolveSplitButton> createState() =>
      _MergeResolveSplitButtonState();
}

class _MergeResolveSplitButtonState extends State<_MergeResolveSplitButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _hoverMain = false;
  bool _hoverChev = false;

  void _openMenu() {
    final overlay = Overlay.of(context);
    final ai = context.read<AiSettingsState>();
    final t = context.tokens;
    // Categories that have a model configured AND aren't the default.
    final alt = ai.modelSelections.entries
        .where((e) => e.value.isNotEmpty && e.key != widget.defaultCategoryId)
        .toList();
    if (alt.isEmpty) return;
    final groupId = widget.menuTapRegionGroupId;
    _entry = OverlayEntry(builder: (ctx) {
      Widget menuCard = CompositedTransformFollower(
        link: _link,
        followerAnchor: Alignment.topRight,
        targetAnchor: Alignment.bottomRight,
        offset: const Offset(0, 6),
        child: MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: ctx.surfaceShader.geometry.cardRadius,
          elevated: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Text('OR WITH',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 9,
                        letterSpacing: 1.4,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w800,
                      )),
                ),
                for (final e in alt)
                  _ModelCategoryRow(
                    label: ai.labelForCategory(e.key, e.key),
                    modelValue: e.value,
                    onTap: () {
                      _closeMenu();
                      widget.onResolve(e.key);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
      // When a host groupId is provided, register the menu in the same
      // tap group so the host's TapRegion.onTapOutside doesn't fire on
      // menu clicks (which would dispose this button's state and
      // invalidate the menu's LayerLink mid-interaction).
      if (groupId != null) {
        menuCard = TapRegion(
          groupId: groupId,
          onTapOutside: (_) => _closeMenu(),
          child: menuCard,
        );
      }
      return Stack(children: [
        // Fallback dismiss catcher for non-grouped usage (the merge
        // resolve strip) — opaque so it doesn't consume hits meant
        // for widgets in overlays stacked above.
        if (groupId == null)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _closeMenu(),
            ),
          ),
        Positioned(child: menuCard),
      ]);
    });
    overlay.insert(_entry!);
  }

  void _closeMenu() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final ai = context.watch<AiSettingsState>();
    final label =
        ai.labelForCategory(widget.defaultCategoryId, widget.defaultCategoryId);
    final modelValue = ai.modelSelections[widget.defaultCategoryId] ?? '';
    final modelDisplay = _modelDisplayName(modelValue);
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main label
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoverMain = true),
              onExit: (_) => setState(() => _hoverMain = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.busy
                    ? null
                    : () => widget.onResolve(widget.defaultCategoryId),
                child: Tooltip(
                  message: modelDisplay.isEmpty
                      ? '${widget.actionLabel} $label'
                      : '${widget.actionLabel} $label  ·  $modelDisplay',
                  child: AnimatedContainer(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: BoxDecoration(
                      color: widget.busy
                          ? t.accentBright.withValues(alpha: 0.08)
                          : (_hoverMain
                              ? t.accentBright.withValues(alpha: 0.14)
                              : t.accentBright.withValues(alpha: 0.08)),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(shader.geometry.badgeRadius),
                        bottomLeft:
                            Radius.circular(shader.geometry.badgeRadius),
                      ),
                      border: Border.all(
                        color: t.accentBright.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      widget.busy
                          ? (widget.actionLabel == 'shape with'
                              ? 'shaping…'
                              : 'resolving…')
                          : '↵  ${widget.actionLabel} $label',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 11,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Chevron split
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hoverChev = true),
              onExit: (_) => setState(() => _hoverChev = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.busy ? null : _openMenu,
                child: Tooltip(
                  message: 'or with another model',
                  child: AnimatedContainer(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    padding: const EdgeInsets.fromLTRB(6, 7, 8, 7),
                    decoration: BoxDecoration(
                      color: _hoverChev
                          ? t.accentBright.withValues(alpha: 0.16)
                          : t.accentBright.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(shader.geometry.badgeRadius),
                        bottomRight:
                            Radius.circular(shader.geometry.badgeRadius),
                      ),
                      // Uniform border — Flutter's `Border.paint` asserts
                      // on a non-uniform border combined with non-zero
                      // borderRadius (the previous left-dim-alpha was
                      // firing 600+ assertions per session). The seam
                      // between this chevron and the abutting main
                      // button now renders as a thin double-stroked
                      // vertical line at the join, which is the
                      // intended split-button look anyway.
                      border: Border.all(
                          color: t.accentBright.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '▾',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 10,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCategoryRow extends StatefulWidget {
  final String label;
  final String modelValue;
  final VoidCallback onTap;
  const _ModelCategoryRow({
    required this.label,
    required this.modelValue,
    required this.onTap,
  });
  @override
  State<_ModelCategoryRow> createState() => _ModelCategoryRowState();
}

class _ModelCategoryRowState extends State<_ModelCategoryRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final modelDisplay = _modelDisplayName(widget.modelValue);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                _hover ? t.accentBright.withValues(alpha: 0.08) : Colors.transparent,
          ),
          child: Row(
            children: [
              Text(widget.label,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 12,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(width: 14),
              Text(modelDisplay,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Take a `provider:modelId` string (e.g. `claude:claude-3-5-sonnet`) and
/// return the human-readable model name. Empty input → empty output.
String _modelDisplayName(String modelValue) {
  if (modelValue.isEmpty) return '';
  final i = modelValue.indexOf(':');
  if (i < 0 || i >= modelValue.length - 1) return modelValue;
  return modelValue.substring(i + 1);
}

// ────────────────────────────────────────────────────────────────────────
// ◈ Shape staging — natural-language partial staging. A glyph next to
// the select-all toggle expands a slim prompt bar; the sentence goes
// to the AI with the working-tree diff; the returned subset patch is
// previewed in stage mode and applied via `git apply --cached`.
// Working tree never mutates — only the index shapes.
// ────────────────────────────────────────────────────────────────────────

/// Floating popover anchored above the commit composer's ◈ shape
/// button. Compact card — one input, one submit split button. Lives
/// alongside the other AI toolbar buttons (review, generate) so all
/// AI affordances share the same region of the screen.
class _ShapePopover extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;
  /// Tap-group the popover was opened under. The chevron menu on the
  /// submit split button registers in the same group so clicking a
  /// menu item doesn't dismiss the popover.
  final Object? tapRegionGroupId;
  const _ShapePopover({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSubmit,
    required this.onClose,
    this.tapRegionGroupId,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ai = context.watch<AiSettingsState>();
    final defaultCategory = ai.modelSelections.containsKey('fast') &&
            ai.modelSelections['fast']!.isNotEmpty
        ? 'fast'
        : (ai.modelSelections.entries
            .firstWhere(
              (e) => e.value.isNotEmpty,
              orElse: () => const MapEntry('', ''),
            )
            .key);
    return Material(
      color: Colors.transparent,
      child: MaterialSurface(
        tone: AppMaterialTone.surface1,
        radius: context.surfaceShader.geometry.cardRadius,
        elevated: true,
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Heading row: glyph + tiny label + close ×.
              Row(
                children: [
                  Text('◈',
                      style: TextStyle(
                        color: t.accentBright,
                        fontSize: 12,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(width: 8),
                  Text('SHAPE COMMIT',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      )),
                  const Spacer(),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: busy ? null : onClose,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text('×',
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 14,
                              fontFamily: 'JetBrainsMono',
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            )),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Input field.
              Container(
                decoration: BoxDecoration(
                  color: t.inputBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: t.inputBorder.withValues(alpha: 0.85),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !busy,
                  onSubmitted: (_) {
                    if (defaultCategory.isNotEmpty) onSubmit(defaultCategory);
                  },
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: busy
                        ? 'drafting subset patch…'
                        : 'describe what to stage, in your own words',
                    hintStyle: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Submit row: right-aligned split button. Mirrors the
              // merge resolver's submit grammar ("ask with <category>").
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (defaultCategory.isEmpty)
                    Text('no AI model configured',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10.5,
                          fontFamily: 'JetBrainsMono',
                          fontStyle: FontStyle.italic,
                        ))
                  else
                    _MergeResolveSplitButton(
                      defaultCategoryId: defaultCategory,
                      busy: busy,
                      onResolve: onSubmit,
                      actionLabel: 'ask with',
                      menuTapRegionGroupId: tapRegionGroupId,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
