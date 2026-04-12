import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/animated_icons.dart';
import '../../ui/control_chrome.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/resonance_text.dart';
import '../../ui/tokens.dart';
import '../../backend/ai.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../app/ai_settings_state.dart';
import '../../app/preferences_state.dart';
import '../../app/repository_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../diff/diff_shell.dart';

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
  String? _actionMessage;
  String? _actionError;
  double _leftPanelWidth = 320.0;
  static const _minLeftPanelWidth = 220.0;
  static const _maxLeftPanelWidth = 520.0;
  bool _commitOnlyMode = false;
  Timer? _commitDraftSaveDebounce;
  String? _lastDraftRepoPath;
  String? _lastDraftBranch;

  // Filing cabinet (stashes)
  List<StashEntryData> _stashes = const [];
  bool _stashesLoading = false;
  bool _stashesExpanded = false;
  String? _stashPeekDiff;
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
    super.dispose();
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
      ..writeln(review.summary)
      ..writeln()
      ..writeln('RR')
      ..writeln(review.reasoningReport);
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
    });
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
    final repoPath = repo.activePath;
    final status = repo.status;

    if (repoPath == null) {
      return const AppStatusView.noRepository();
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
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: status.files.length,
                            itemBuilder: (ctx, i) {
                              final file = status.files[i];
                              return _FileRow(
                                file: file,
                                tokens: t,
                                isDiffSelected: activeDiffPath == file.path,
                                included: _includedPaths.contains(file.path),
                                onTap: includedFiles.length > 1
                                    ? () {
                                        if (_includedPaths.contains(file.path)) {
                                          _jumpToMultiDiffPath(file.path);
                                        } else {
                                          _inspectSingleDiff(repoPath, file.path);
                                        }
                                      }
                                    : () => _loadDiff(repoPath, file.path),
                                onIncludeChanged: (value) =>
                                    _toggleIncluded(file.path, value),
                              );
                            },
                          ),
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
                              child: Text(
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
                            if (_stashes.isNotEmpty || _stashesLoading)
                              GestureDetector(
                                onTap: () => setState(() => _stashesExpanded = !_stashesExpanded),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${_stashes.length} shelved',
                                      style: TextStyle(
                                        color: t.chromeAccent.withValues(alpha: 0.7),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _stashesExpanded ? '▾' : '▸',
                                      style: TextStyle(color: t.textMuted, fontSize: 9),
                                    ),
                                  ],
                                ),
                              )
                            else
                              GestureDetector(
                                onTap: status.files.isNotEmpty ? () => _shelveAll(repoPath) : null,
                                child: Text(
                                  '↓ shelve',
                                  style: TextStyle(
                                    color: status.files.isNotEmpty
                                        ? t.textMuted
                                        : t.textMuted.withValues(alpha: 0.3),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // ── Filing cabinet drawers (inline) ────────
                        if (_stashesExpanded && _stashes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 120),
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _stashes.length,
                                itemBuilder: (ctx, i) {
                                  final stash = _stashes[i];
                                  final isPeeking = _stashPeekIndex == stash.index;
                                  return _StashDrawerCard(
                                    tokens: t,
                                    stash: stash,
                                    isPeeking: isPeeking,
                                    onPickUp: () => _pickUpStash(repoPath, stash.index),
                                    onPeek: () => _peekStash(repoPath, stash.index),
                                    onToss: () => _tossStash(repoPath, stash.index),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Focus(
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent ||
                                event.logicalKey != LogicalKeyboardKey.enter) {
                              return KeyEventResult.ignored;
                            }
                            if (HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed) {
                              _commit(
                                repoPath,
                                status,
                                mode: primaryAction.syncAfterCommit
                                    ? _CommitRunMode.commitAndSync
                                    : _CommitRunMode.commitOnly,
                              );
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: _CommitComposerField(
                            tokens: t,
                            controller: _commitMsgCtrl,
                            focusNode: _commitMsgFocusNode,
                            enabled: !_actionRunning,
                            onChanged: (value) {
                              _saveCommitDraft(value);
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
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SplitCommitBtn(
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
                  if (_reviewActive) {
                    return MaterialSurface(
                      tone: AppMaterialTone.surface0,
                      radius: 0,
                      borderAlpha: 0,
                      elevated: false,
                      child: _CommitReviewPane(
                        tokens: t,
                        includedCount: includedCount,
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
                                if (notification.metrics.axis ==
                                    Axis.vertical) {
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
      ..color = tokens.chromeBorder.withValues(alpha: 0.28)
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

class _CommitReviewPane extends StatelessWidget {
  final AppTokens tokens;
  final int includedCount;
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
                  Text(
                    '$includedCount included file${includedCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10.5,
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
                          Text(
                            '$includedCount included file${includedCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
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
                            if (review.usedCondensedDiff) ...[
                              TextSpan(
                                text: '  ·  ',
                                style: TextStyle(color: tokens.textFaint),
                              ),
                              TextSpan(
                                text: 'condensed',
                                style: TextStyle(
                                  color: AppSeverityPalette.caution.withValues(alpha: 0.7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
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
                      borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: tokens.chromeBorder.withValues(alpha: 0.08),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.chromeBorder.withValues(alpha: 0.14)),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.chromeBorder.withValues(alpha: 0.14)),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.chromeBorder.withValues(alpha: 0.14)),
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
          duration: const Duration(milliseconds: 100),
          height: 28,
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
      duration: const Duration(milliseconds: 180),
      opacity: widget.aiGenerating && !_anyHovered ? 0.45 : 1.0,
      child: Transform.translate(
      offset: chrome.offset,
      child: Transform.scale(
        scale: chrome.scale,
        child: SizedBox(
          height: 36,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
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
                              duration: const Duration(milliseconds: 250),
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

// ── Stash drawer card ─────────────────────────────────────────────────────

class _StashDrawerCard extends StatefulWidget {
  final AppTokens tokens;
  final StashEntryData stash;
  final bool isPeeking;
  final VoidCallback onPickUp;
  final VoidCallback onPeek;
  final VoidCallback onToss;

  const _StashDrawerCard({
    required this.tokens,
    required this.stash,
    required this.isPeeking,
    required this.onPickUp,
    required this.onPeek,
    required this.onToss,
  });

  @override
  State<_StashDrawerCard> createState() => _StashDrawerCardState();
}

class _StashDrawerCardState extends State<_StashDrawerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final stash = widget.stash;
    // Clean up the default "WIP on branch: hash message" format.
    var label = stash.message;
    final wipMatch = RegExp(r'^WIP on .+?: [a-f0-9]+ (.+)$').firstMatch(label);
    if (wipMatch != null) label = wipMatch.group(1)!;
    final onMatch = RegExp(r'^On .+?: (.+)$').firstMatch(label);
    if (onMatch != null) label = onMatch.group(1)!;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: widget.isPeeking
              ? t.itemActiveBg
              : (_hovered ? t.secondaryBtnHoverBg : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
          border: widget.isPeeking
              ? Border.all(color: t.chromeAccent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: t.textNormal,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${stash.fileCount} file${stash.fileCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            if (_hovered || widget.isPeeking) ...[
              _StashAction(
                icon: '↑',
                tooltip: 'pick up',
                color: t.accentBright,
                onTap: widget.onPickUp,
              ),
              const SizedBox(width: 4),
              _StashAction(
                icon: widget.isPeeking ? '◉' : '◎',
                tooltip: 'peek',
                color: t.chromeAccent,
                onTap: widget.onPeek,
              ),
              const SizedBox(width: 4),
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

  const _FileRow({
    required this.file,
    required this.tokens,
    required this.isDiffSelected,
    required this.included,
    required this.onTap,
    required this.onIncludeChanged,
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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isDiffSelected
                ? t.chromeBorder.withValues(alpha: 0.1)
                : (widget.included
                    ? t.stateAdded.withValues(alpha: 0.05)
                    : (_hovered ? t.itemHoverBg : Colors.transparent)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.included
                  ? t.stateAdded.withValues(alpha: 0.18)
                  : Colors.transparent,
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
    );
  }
}

class _ChangeBadgeSpec {
  final String label;
  final Color color;

  const _ChangeBadgeSpec({required this.label, required this.color});
}

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

  const _CommitComposerField({
    required this.tokens,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
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
  });

  @override
  State<_CommitComposerField> createState() => _CommitComposerFieldState();
}

class _CommitComposerFieldState extends State<_CommitComposerField>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _doneCtrl;
  final ScrollController _scrollCtrl = ScrollController();

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
    if (widget.aiLoading) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_CommitComposerField old) {
    super.didUpdateWidget(old);
    if (widget.aiLoading && !old.aiLoading) {
      _doneCtrl.stop();
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.aiLoading && old.aiLoading) {
      _pulseCtrl.stop();
      _doneCtrl.forward(from: 0);
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
      animation: Listenable.merge([
        _pulseCtrl,
        _doneCtrl,
        widget.focusNode,
        widget.controller,
      ]),
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
                            hintText: 'Commit message...',
                            hintStyle: TextStyle(
                              color: tokens.textMuted.withValues(alpha: 0.55),
                              fontSize: 12,
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

enum _AiToolbarIconKind { search, sparkle }

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
                    : Colors.transparent,
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
                : Colors.transparent,
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
