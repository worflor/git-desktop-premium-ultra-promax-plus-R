import 'package:flutter/foundation.dart';

import '../../backend/git.dart' as git;
import '../../backend/history_surgery.dart';
import '../../backend/logos_git.dart';

enum SurgeryPhase { select, understand, confirm, execute, verify }

class SurgeryState extends ChangeNotifier {
  final String repoPath;
  final LogosGit? engine;
  final bool dryRun;
  late final HistorySurgeryEngine _engine;
  bool _disposed = false;

  SurgeryState({required this.repoPath, this.engine, this.dryRun = false}) {
    _engine = HistorySurgeryEngine(repoPath);
  }

  @override
  void dispose() {
    _disposed = true;
    _engine.cancel();
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ── Phase tracking ──

  SurgeryPhase _phase = SurgeryPhase.select;
  SurgeryPhase get phase => _phase;

  // ── Phase 1: Select ──

  final Set<String> selectedPaths = {};
  final Map<String, Set<String>> renameChains = {};
  Set<String> get allTargetPaths {
    final all = <String>{};
    for (final chain in renameChains.values) {
      all.addAll(chain);
    }
    all.addAll(selectedPaths);
    return all;
  }

  Future<void> addPath(String path) async {
    if (selectedPaths.contains(path)) return;
    selectedPaths.add(path);
    final chain = await _engine.discoverAllPaths(path);
    renameChains[path] = chain;
    _safeNotify();
    _refreshImpact();
  }

  void removePath(String path) {
    selectedPaths.remove(path);
    renameChains.remove(path);
    _safeNotify();
    if (selectedPaths.isEmpty) {
      impact = null;
      _safeNotify();
    } else {
      _refreshImpact();
    }
  }

  // ── Impact (runs automatically on selection change) ──

  SurgeryImpact? impact;
  bool analyzing = false;
  String? analysisError;
  int _analysisGeneration = 0;

  Future<void> _refreshImpact() async {
    if (selectedPaths.isEmpty) return;
    final gen = ++_analysisGeneration;
    analyzing = true;
    analysisError = null;
    _safeNotify();

    try {
      final result = await _engine.analyzeImpact(
        allTargetPaths,
        engine: engine,
      );
      if (gen != _analysisGeneration) return;
      impact = result;
    } catch (e) {
      if (gen != _analysisGeneration) return;
      analysisError = e.toString();
    }

    analyzing = false;
    _safeNotify();
  }

  // ── Phase 3: Confirm ──

  final List<bool> checkboxes = [];
  String typedConfirmation = '';

  void initCheckboxes() {
    checkboxes.clear();
    // Always: commits will be rewritten
    checkboxes.add(false);
    // Always: force-push required
    checkboxes.add(false);
    // Conditional: worktrees
    if (impact != null && impact!.affectedWorktrees.isNotEmpty) {
      checkboxes.add(false);
    }
    // Conditional: stashes
    if (impact != null && impact!.affectedStashIndices.isNotEmpty) {
      checkboxes.add(false);
    }
    _safeNotify();
  }

  void toggleCheckbox(int index) {
    if (index < checkboxes.length) {
      checkboxes[index] = !checkboxes[index];
      _safeNotify();
    }
  }

  void setConfirmationText(String text) {
    typedConfirmation = text;
    _safeNotify();
  }

  bool get confirmationComplete =>
      checkboxes.isNotEmpty &&
      checkboxes.every((c) => c) &&
      typedConfirmation.trim().toUpperCase() == 'PURGE';

  // ── Phase 4: Execute ──

  SurgeryProgress? progress;
  bool executing = false;
  String? executeError;

  Future<void> execute() async {
    _phase = SurgeryPhase.execute;
    executing = true;
    executeError = null;
    _safeNotify();

    if (dryRun) {
      await _simulateExecution();
    } else {
      try {
        result = await _engine.execute(
          allTargetPaths,
          (p) {
            progress = p;
            _safeNotify();
          },
        );
      } catch (e) {
        executeError = e.toString();
        result = SurgeryResult(
          success: false,
          error: e.toString(),
          backupPrefix: _engine.lastBackupPrefix,
          oldHead: '',
          newHead: '',
        );
      }
    }

    executing = false;
    _phase = SurgeryPhase.verify;
    _safeNotify();
  }

  Future<void> _simulateExecution() async {
    final total = impact?.affectedCommits ?? 42;
    for (var i = 0; i <= total; i++) {
      final phase = i == 0
          ? 'Backing up refs...'
          : i < total
              ? 'Rewriting commits...'
              : 'Updating refs...';
      progress = SurgeryProgress(
        processed: i,
        total: total,
        phase: phase,
        currentHash: 'abc${i.toRadixString(16).padLeft(4, '0')}',
      );
      _safeNotify();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!executing || _disposed) return;
    }
    result = SurgeryResult(
      success: true,
      commitsRewritten: total,
      refsUpdated: impact?.affectedBranches.length ?? 1,
      displacedWorktrees: (impact?.affectedWorktrees ?? []).toSet(),
      backupPrefix: 'refs/manifold-surgery-backup/dry-run',
      oldHead: 'abc1234',
      newHead: 'def5678',
    );
  }

  // ── Phase 5: Verify ──

  SurgeryResult? result;
  bool? purgeVerified;
  bool rolledBack = false;

  Future<void> verifyPurge() async {
    if (dryRun) {
      purgeVerified = true;
      _safeNotify();
      return;
    }
    purgeVerified = await _engine.verifyPurge(allTargetPaths);
    _safeNotify();
  }

  final List<String> pushErrors = [];
  final Set<String> pushedBranches = {};
  String? get pushError => pushErrors.isEmpty ? null : pushErrors.join('\n');

  Future<void> forcePush(String branch) async {
    if (rolledBack) return;
    if (dryRun) {
      pushedBranches.add(branch);
      _safeNotify();
      return;
    }
    final result = await git.pushRemote(
      repoPath,
      branch: branch,
      forceWithLease: true,
    );
    if (!result.ok) {
      pushErrors.add('$branch: ${result.error ?? 'unknown error'}');
    } else {
      pushedBranches.add(branch);
    }
    _safeNotify();
  }

  Future<void> rollback() async {
    if (dryRun) {
      rolledBack = true;
      _safeNotify();
      return;
    }
    if (result?.backupPrefix.isEmpty ?? true) return;
    await _engine.rollback(result!.backupPrefix);
    rolledBack = true;
    _safeNotify();
  }

  // ── Navigation ──

  void goToPhase(SurgeryPhase p) {
    _phase = p;
    if (p == SurgeryPhase.confirm) initCheckboxes();
    _safeNotify();
  }

  bool canAdvance() {
    switch (_phase) {
      case SurgeryPhase.select:
        return selectedPaths.isNotEmpty && impact != null && !analyzing;
      case SurgeryPhase.understand:
        return true;
      case SurgeryPhase.confirm:
        return confirmationComplete;
      case SurgeryPhase.execute:
        return false;
      case SurgeryPhase.verify:
        return false;
    }
  }

  void advance() {
    if (!canAdvance()) return;
    switch (_phase) {
      case SurgeryPhase.select:
        goToPhase(SurgeryPhase.understand);
      case SurgeryPhase.understand:
        goToPhase(SurgeryPhase.confirm);
      case SurgeryPhase.confirm:
        execute();
      case SurgeryPhase.execute:
      case SurgeryPhase.verify:
        break;
    }
  }

  void goBack() {
    switch (_phase) {
      case SurgeryPhase.select:
        break;
      case SurgeryPhase.understand:
        _phase = SurgeryPhase.select;
        _safeNotify();
      case SurgeryPhase.confirm:
        _phase = SurgeryPhase.understand;
        _safeNotify();
      case SurgeryPhase.execute:
      case SurgeryPhase.verify:
        break;
    }
  }
}
