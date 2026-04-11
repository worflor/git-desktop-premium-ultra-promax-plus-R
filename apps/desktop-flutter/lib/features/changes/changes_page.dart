import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/control_chrome.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';
import '../../backend/ai.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../app/ai_settings_state.dart';
import '../../app/repository_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../diff/diff_shell.dart';

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
  bool _commitAiLoading = false;
  String? _commitAiError;
  List<AiModelCategoryData> _commitAiCategories = const [];
  String? _actionMessage;
  String? _actionError;
  double _leftPanelWidth = 320.0;
  static const _minLeftPanelWidth = 220.0;
  static const _maxLeftPanelWidth = 520.0;

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
    });
  }

  @override
  void dispose() {
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
    return 'Generate commit message';
  }

  Future<void> _refreshCommitAiConfig({bool forceRefresh = false}) async {
    setState(() {
      _commitAiLoading = true;
      _commitAiError = null;
    });
    final result = await listAiModelOptions(forceRefresh: forceRefresh);
    if (!mounted) {
      return;
    }
    if (result.ok) {
      await context
          .read<AiSettingsState>()
          .syncModelCategories(result.data!.categories);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _commitAiLoading = false;
      if (result.ok) {
        _commitAiCategories = result.data!.categories;
        _commitAiError = null;
      } else {
        _commitAiError = result.error;
      }
    });
  }

  Future<List<AiModelCategoryData>?> _resolveCommitAiCategories({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _commitAiCategories.any((category) => category.models.isNotEmpty)) {
      return _commitAiCategories;
    }

    final result = await listAiModelOptions(forceRefresh: forceRefresh);
    if (!mounted) {
      return null;
    }
    if (!result.ok) {
      setState(() {
        _commitAiError = result.error;
      });
      return null;
    }

    await context
        .read<AiSettingsState>()
        .syncModelCategories(result.data!.categories);
    if (!mounted) {
      return null;
    }

    setState(() {
      _commitAiCategories = result.data!.categories;
      _commitAiError = null;
    });
    return result.data!.categories;
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
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _generateRunning = false;
      if (result.ok) {
        _commitMsgCtrl.text = result.data!.message;
        _commitMsgCtrl.selection = TextSelection.collapsed(
          offset: _commitMsgCtrl.text.length,
        );
        _actionMessage =
            'Generated commit message with ${selectedModel.modelId}.';
      } else {
        _actionError = result.error;
      }
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
      _actionMessage = successMessage;
      _actionError = syncError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final aiSettings = context.watch<AiSettingsState>();
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

    _syncDraftFromStatus(status);

    if (status.files.isEmpty) {
      return const AppStatusView(
        title: 'Working tree clean',
        message: 'No staged or unstaged changes detected.',
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
    final canCommit = !_actionRunning &&
        !_generateRunning &&
        _commitMsgCtrl.text.trim().isNotEmpty &&
        includedCount > 0;
    final canGenerate = !_actionRunning &&
        !_generateRunning &&
        !_commitAiLoading &&
        includedCount > 0 &&
        hasCommitAiSelection;

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
                        Text(
                          includedCount == 0
                              ? (stagedCount > 0
                                  ? 'Nothing selected | $stagedCount staged'
                                  : 'Nothing selected')
                              : (stagedCount > 0
                                  ? '$includedCount file${includedCount == 1 ? '' : 's'} selected | $stagedCount staged'
                                  : '$includedCount file${includedCount == 1 ? '' : 's'} selected'),
                          style: TextStyle(
                            color:
                                includedCount == 0 ? t.textMuted : t.textNormal,
                            fontSize: 11,
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
                            onChanged: (_) => setState(() {}),
                            aiEnabled: canGenerate,
                            aiLoading: _generateRunning || _commitAiLoading,
                            aiTooltip:
                                _commitAiTooltip(aiSettings, includedCount),
                            onGenerate: () => _generateCommitMessage(
                              repoPath,
                              status,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _ActionBtn(
                                label: _actionRunning
                                    ? 'Committing...'
                                    : 'Commit only',
                                t: t,
                                enabled: canCommit,
                                primary: false,
                                onTap: () => _commit(
                                  repoPath,
                                  status,
                                  mode: _CommitRunMode.commitOnly,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ActionBtn(
                                label: _actionRunning
                                    ? 'Working...'
                                    : primaryAction.label,
                                t: t,
                                enabled: canCommit,
                                onTap: () => _commit(
                                  repoPath,
                                  status,
                                  mode: primaryAction.syncAfterCommit
                                      ? _CommitRunMode.commitAndSync
                                      : _CommitRunMode.commitOnly,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_actionMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _actionMessage!,
                              style: TextStyle(
                                color: t.stateAdded,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        if (_actionError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _actionError!,
                              style: TextStyle(
                                color: t.stateConflicted,
                                fontSize: 10.5,
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
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification.depth == 0 &&
                                    notification.metrics.axis ==
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
                                repositoryPath: null,
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

class _CommitComposerField extends StatelessWidget {
  final AppTokens tokens;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool aiEnabled;
  final bool aiLoading;
  final String aiTooltip;
  final VoidCallback onGenerate;

  const _CommitComposerField({
    required this.tokens,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.aiEnabled,
    required this.aiLoading,
    required this.aiTooltip,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final radius = themeDefinitionFor(tokens.id)
        .shader
        .geometry
        .radius
        .clamp(0, 18)
        .toDouble();
    final effectiveRadius = (radius * 0.75).clamp(0.0, 14.0);

    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      builder: (context, child) {
        final hasText = controller.text.trim().isNotEmpty;
        final isFocused = focusNode.hasFocus;
        // Inner border radius shrinks slightly to sit flush against the outer
        // border without leaving a gap at the rounded corners.
        final innerRadius = math.max(0.0, effectiveRadius - 1.5);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          height: 118,
          decoration: BoxDecoration(
            color: tokens.inputBg,
            borderRadius: BorderRadius.circular(effectiveRadius),
            border: Border.all(
              color: (isFocused
                      ? tokens.inputFocusBorder.withValues(alpha: 0.70)
                      : tokens.inputBorder)
                  .withValues(alpha: enabled ? 1 : 0.45),
            ),
          ),
          // ClipRRect keeps the toolbar's bottom corners inside the field's
          // rounded border — no visual overflow.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Text entry area ────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: null,
                      maxLines: null,
                      expands: true,
                      onChanged: onChanged,
                      cursorColor: tokens.accentBright,
                      style: TextStyle(
                        color: tokens.textStrong,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Commit message...',
                        hintStyle: TextStyle(
                          color: tokens.textMuted.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Action toolbar ─────────────────────────────
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: tokens.chromeBorder.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _CommitAiToolbarBtn(
                        tokens: tokens,
                        enabled: aiEnabled,
                        loading: aiLoading,
                        tooltip: aiTooltip,
                        hasText: hasText,
                        fieldRadius: effectiveRadius,
                        onTap: onGenerate,
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

class _CommitAiToolbarBtn extends StatefulWidget {
  final AppTokens tokens;
  final bool enabled;
  final bool loading;
  final String tooltip;
  final bool hasText; // de-emphasise when the user already typed something
  final double fieldRadius;
  final VoidCallback onTap;

  const _CommitAiToolbarBtn({
    required this.tokens,
    required this.enabled,
    required this.loading,
    required this.tooltip,
    required this.hasText,
    required this.fieldRadius,
    required this.onTap,
  });

  @override
  State<_CommitAiToolbarBtn> createState() => _CommitAiToolbarBtnState();
}

class _CommitAiToolbarBtnState extends State<_CommitAiToolbarBtn> {
  bool _hovered = false;
  bool _pressed = false;

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
              child: widget.loading
                  ? SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: t.accentBright.withValues(alpha: iconOpacity),
                      ),
                    )
                  : AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: iconOpacity,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: t.accentBright,
                      ),
                    ),
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
