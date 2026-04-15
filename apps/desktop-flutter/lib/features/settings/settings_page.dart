import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../backend/ai.dart';
import '../../backend/ai_audit_store.dart';
import '../../backend/command_telemetry_store.dart';
import '../../backend/dtos.dart';
import '../../backend/commit_format.dart';
import '../../backend/file_coupling.dart';
import '../../app/ai_settings_state.dart';
import '../../app/preferences_state.dart';
import '../../app/theme_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../onboarding/onboarding_state.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/form_controls.dart';
import '../../ui/material_surface.dart';
import '../../ui/morph_text.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';

const _guardrailStageLabels = ['Loose', 'Balanced', 'Strict', 'Paranoid'];
const _guardrailStageColors = AppSeverityPalette.guardrailStages;

enum _PromptSaveState { idle, typing, saving, saved, error }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  final Map<String, TextEditingController> _categoryLabelControllers = {};
  final TextEditingController _commitPromptController = TextEditingController();
  final TextEditingController _reviewPromptController = TextEditingController();
  final TextEditingController _musePromptController = TextEditingController();
  String _diagnosticsFocus = 'command';
  String? _actionMessage;
  String? _actionError;
  bool _dataMaintenanceBusy = false;
  bool _aiProvidersLoading = false;
  bool _aiModelOptionsLoading = false;
  String? _aiProvidersError;
  String? _aiModelOptionsError;
  List<AiProviderStatus> _aiProviders = const [];
  List<AiModelCategoryData> _aiModelCategories = const [];
  Timer? _commitPromptSaveDebounce;
  Timer? _reviewPromptSaveDebounce;
  Timer? _musePromptSaveDebounce;
  _PromptSaveState _commitPromptSaveState = _PromptSaveState.idle;
  _PromptSaveState _reviewPromptSaveState = _PromptSaveState.idle;
  _PromptSaveState _musePromptSaveState = _PromptSaveState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'settings.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final aiSettings = context.read<AiSettingsState>();
      _commitPromptController.text = aiSettings.commitMessagePrompt;
      _reviewPromptController.text = aiSettings.reviewCommitPrompt;
      _musePromptController.text = aiSettings.musePrompt;
      _refreshAiDiagnostics();
    });
  }

  @override
  void dispose() {
    _commitPromptSaveDebounce?.cancel();
    _reviewPromptSaveDebounce?.cancel();
    _musePromptSaveDebounce?.cancel();
    _commitPromptController.dispose();
    _reviewPromptController.dispose();
    _musePromptController.dispose();
    for (final controller in _categoryLabelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshAiDiagnostics({bool forceRefresh = false}) async {
    final aiSettings = context.read<AiSettingsState>();
    setState(() {
      _aiProviders = aiSettings.runtimeProviders;
      _aiModelCategories = aiSettings.runtimeModelCategories;
      _aiProvidersLoading = forceRefresh || _aiProviders.isEmpty;
      _aiModelOptionsLoading = forceRefresh || _aiModelCategories.isEmpty;
      _aiProvidersError = aiSettings.runtimeProvidersError;
      _aiModelOptionsError = aiSettings.runtimeModelCategoriesError;
    });

    await Future.wait([
      aiSettings.refreshProviders(forceRefresh: forceRefresh),
      aiSettings.refreshModelCategories(forceRefresh: forceRefresh),
    ]);
    if (!mounted) {
      return;
    }

    setState(() {
      _aiProvidersLoading = false;
      _aiModelOptionsLoading = false;
      _aiProviders = aiSettings.runtimeProviders;
      _aiProvidersError = aiSettings.runtimeProvidersError;
      _aiModelCategories = aiSettings.runtimeModelCategories;
      _aiModelOptionsError = aiSettings.runtimeModelCategoriesError;
      if (_aiModelCategories.isNotEmpty) {
        _syncCategoryControllers();
      }
    });
  }

  void _syncCategoryControllers() {
    final aiSettings = context.read<AiSettingsState>();
    final activeIds = _aiModelCategories.map((category) => category.id).toSet();
    final staleIds = _categoryLabelControllers.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in staleIds) {
      _categoryLabelControllers.remove(id)?.dispose();
    }

    for (final category in _aiModelCategories) {
      final resolvedLabel =
          aiSettings.labelForCategory(category.id, category.label);
      _categoryLabelControllers.putIfAbsent(
        category.id,
        () => TextEditingController(text: resolvedLabel),
      );
      // Don't force-sync controller.text here — it resets cursor position
      // mid-typing. The controller is the source of truth while focused.
    }
  }

  Future<void> _saveGuardrailStage(int stage) async {
    setState(() {
      _actionError = null;
      _actionMessage = null;
    });
    try {
      await context.read<PreferencesState>().setGuardrailStage(stage);
      if (!mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save guardrail profile.');
    }
  }

  Future<void> _saveRetention(int retentionDays, int retentionMb) async {
    setState(() {
      _actionError = null;
      _actionMessage = null;
    });
    try {
      await context
          .read<DiagnosticsState>()
          .setRetentionPolicy(retentionDays, retentionMb);
      if (!mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save retention policy.');
    }
  }

  Future<void> _saveUpdateChannel(String value) async {
    setState(() {
      _actionError = null;
      _actionMessage = null;
    });
    try {
      await context.read<PreferencesState>().setUpdateChannel(value);
      if (!mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save update channel.');
    }
  }

  Future<void> _saveCrashReporting(bool value) async {
    setState(() {
      _actionError = null;
      _actionMessage = null;
    });
    try {
      await context.read<PreferencesState>().setCrashReportingEnabled(value);
      if (!mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save crash reporting policy.');
    }
  }

  Future<void> _setAiReadOnlyDefault(bool value) async {
    await context.read<PreferencesState>().setAiReadOnlyDefault(value);
  }

  Future<void> _setLogoAnimatesWhenUnfocused(bool value) async {
    await context.read<PreferencesState>().setLogoAnimatesWhenUnfocused(value);
  }

  Future<void> _saveModelSelection(String categoryId, String value) async {
    try {
      await context
          .read<AiSettingsState>()
          .setModelSelection(categoryId, value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage = 'Saved AI model selection.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save AI model selection.');
    }
  }

  Future<void> _saveModelCategoryLabel(
    String categoryId,
    String value,
  ) async {
    try {
      await context.read<AiSettingsState>().setCategoryLabel(categoryId, value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage = 'Saved model alias.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save model alias.');
    }
  }

  Future<void> _saveCommitMessageModelCategory(String value) async {
    try {
      await context
          .read<AiSettingsState>()
          .setCommitMessageModelCategoryId(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage = 'Saved commit message model slot.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () => _actionError = 'Failed to save commit message model slot.',
      );
    }
  }

  Future<void> _saveReviewCommitModelCategory(String value) async {
    try {
      await context.read<AiSettingsState>().setReviewCommitModelCategoryId(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage = 'Saved review model slot.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save review model slot.');
    }
  }

  void _scheduleCommitPromptSave(String value) {
    _commitPromptSaveDebounce?.cancel();
    if (mounted) {
      setState(() {
        _commitPromptSaveState = _PromptSaveState.typing;
      });
    }
    _commitPromptSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() {
          _commitPromptSaveState = _PromptSaveState.saving;
        });
      }
      unawaited(_saveCommitPrompt(value));
    });
  }

  void _scheduleReviewPromptSave(String value) {
    _reviewPromptSaveDebounce?.cancel();
    if (mounted) {
      setState(() {
        _reviewPromptSaveState = _PromptSaveState.typing;
      });
    }
    _reviewPromptSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() {
          _reviewPromptSaveState = _PromptSaveState.saving;
        });
      }
      unawaited(_saveReviewPrompt(value));
    });
  }

  Future<void> _saveCommitPrompt(String value) async {
    try {
      await context.read<AiSettingsState>().setCommitMessagePrompt(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage = value.trim().isEmpty
            ? 'Cleared commit message custom prompt.'
            : 'Saved commit message custom prompt.';
        _commitPromptSaveState = _PromptSaveState.saved;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () {
          _actionError = 'Failed to save commit message custom prompt.';
          _commitPromptSaveState = _PromptSaveState.error;
        },
      );
    }
  }

  Future<void> _saveReviewPrompt(String value) async {
    try {
      await context.read<AiSettingsState>().setReviewCommitPrompt(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage = value.trim().isEmpty
            ? 'Cleared review guide.'
            : 'Saved review guide.';
        _reviewPromptSaveState = _PromptSaveState.saved;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = 'Failed to save review guide.';
        _reviewPromptSaveState = _PromptSaveState.error;
      });
    }
  }

  void _scheduleMusePromptSave(String value) {
    _musePromptSaveDebounce?.cancel();
    if (mounted) {
      setState(() {
        _musePromptSaveState = _PromptSaveState.typing;
      });
    }
    _musePromptSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() {
          _musePromptSaveState = _PromptSaveState.saving;
        });
      }
      unawaited(_saveMusePrompt(value));
    });
  }

  Future<void> _saveMusePrompt(String value) async {
    try {
      await context.read<AiSettingsState>().setMusePrompt(value);
      if (!mounted) return;
      setState(() {
        _actionError = null;
        _actionMessage = value.trim().isEmpty
            ? 'Cleared muse notes.'
            : 'Saved muse notes.';
        _musePromptSaveState = _PromptSaveState.saved;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionError = 'Failed to save muse notes.';
        _musePromptSaveState = _PromptSaveState.error;
      });
    }
  }

  Future<void> _saveReviewDoubleCheck(bool value) async {
    try {
      await context
          .read<AiSettingsState>()
          .setReviewCommitDoubleCheckEnabled(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = null;
        _actionMessage =
            value ? 'Enabled double-check review.' : 'Disabled double-check review.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _actionError = 'Failed to save review double-check mode.');
    }
  }

  String? _commitPromptStatusLabel() {
    switch (_commitPromptSaveState) {
      case _PromptSaveState.typing:
        return 'Editing';
      case _PromptSaveState.saving:
        return 'Saving';
      case _PromptSaveState.saved:
        return null;
      case _PromptSaveState.error:
        return 'Save failed';
      case _PromptSaveState.idle:
        return null;
    }
  }

  String? _reviewPromptStatusLabel() {
    switch (_reviewPromptSaveState) {
      case _PromptSaveState.typing:
        return 'Editing';
      case _PromptSaveState.saving:
        return 'Saving';
      case _PromptSaveState.saved:
        return null;
      case _PromptSaveState.error:
        return 'Save failed';
      case _PromptSaveState.idle:
        return null;
    }
  }

  String? _musePromptStatusLabel() {
    switch (_musePromptSaveState) {
      case _PromptSaveState.typing:
        return 'Editing';
      case _PromptSaveState.saving:
        return 'Saving';
      case _PromptSaveState.saved:
        return null;
      case _PromptSaveState.error:
        return 'Save failed';
      case _PromptSaveState.idle:
        return null;
    }
  }

  Future<bool> _confirmLocalDataAction(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _clearDiagnostics() async {
    if (!await _confirmLocalDataAction(
      'Clear local diagnostics samples and performance timings?',
    )) {
      return;
    }

    setState(() {
      _dataMaintenanceBusy = true;
      _actionError = null;
      _actionMessage = null;
    });
    final diagnostics = DiagnosticsState.instance;
    await diagnostics.clearAllDiagnostics();
    if (!mounted) {
      return;
    }
    setState(() {
      _dataMaintenanceBusy = false;
      _actionMessage = 'Cleared local diagnostics samples.';
    });
  }

  Future<void> _clearAudit() async {
    if (!await _confirmLocalDataAction(
      'Clear local AI audit metadata records?',
    )) {
      return;
    }

    setState(() {
      _dataMaintenanceBusy = true;
      _actionError = null;
      _actionMessage = null;
    });
    final count = await AiAuditStore.clearEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _dataMaintenanceBusy = false;
      _actionMessage =
          'Cleared $count AI audit ${count == 1 ? "entry" : "entries"}.';
    });
  }

  Future<void> _clearAllLocalData() async {
    if (!await _confirmLocalDataAction(
      'Clear all local diagnostics samples and AI audit metadata records?',
    )) {
      return;
    }

    setState(() {
      _dataMaintenanceBusy = true;
      _actionError = null;
      _actionMessage = null;
    });
    final diagnostics = DiagnosticsState.instance;
    await diagnostics.clearAllDiagnostics();
    final count = await AiAuditStore.clearEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _dataMaintenanceBusy = false;
      _actionMessage =
          'Cleared diagnostics and $count AI audit ${count == 1 ? "entry" : "entries"}.';
    });
  }

  Future<void> _copyAllDiagnostics() async {
    final snapshot = context
        .read<DiagnosticsState>()
        .buildSnapshot(focusedStream: _diagnosticsFocus);
    await Clipboard.setData(
      ClipboardData(text: jsonEncode(snapshot)),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _actionError = null;
      _actionMessage = 'Copied diagnostics snapshot to clipboard.';
    });
  }

  void _showUpdateStubMessage() {
    setState(() {
      _actionError = null;
      _actionMessage = 'Update actions are not wired in the Flutter build yet.';
    });
  }

  List<_ProviderCard> _buildProviderCards() {
    if (_aiProviders.isEmpty) {
      return const [
        _ProviderCard(
          id: 'codex',
          binaryLabel: 'codex',
          status: 'Detecting...',
          placeholder: true,
        ),
        _ProviderCard(
          id: 'claude',
          binaryLabel: 'claude',
          status: 'Detecting...',
          placeholder: true,
        ),
        _ProviderCard(
          id: 'gemini',
          binaryLabel: 'npx',
          status: 'Detecting...',
          placeholder: true,
        ),
        _ProviderCard(
          id: 'opencode',
          binaryLabel: 'opencode',
          status: 'Detecting...',
          placeholder: true,
        ),
      ];
    }

    return _aiProviders
        .map(
          (provider) => _ProviderCard(
            id: provider.id,
            binaryLabel: provider.resolvedBinary ?? provider.binary,
            status: provider.available
                ? provider.planName ?? 'Ready'
                : 'Not detected',
            detail: provider.healthCheck,
            ready: provider.available,
          ),
        )
        .toList();
  }

  String _formatSampleTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  List<_DiagnosticsOffender> _buildTopOffenders(
    CommandLatencyReport commandReport,
    DiffRenderMetricsReport diffReport,
    UiTimingReport uiReport,
  ) {
    final offenders = <_DiagnosticsOffender>[];
    if (commandReport.summaries.isNotEmpty) {
      final ranked = [...commandReport.summaries]..sort((left, right) {
          final leftFailureRate =
              left.count == 0 ? 0.0 : left.failureCount / left.count;
          final rightFailureRate =
              right.count == 0 ? 0.0 : right.failureCount / right.count;
          final leftScore = left.p95Ms * (1 + leftFailureRate * 3);
          final rightScore = right.p95Ms * (1 + rightFailureRate * 3);
          return rightScore.compareTo(leftScore);
        });
      final summary = ranked.first;
      final failureRate =
          summary.count == 0 ? 0.0 : summary.failureCount / summary.count;
      final score = summary.p95Ms * (1 + failureRate * 3);
      offenders.add(
        _DiagnosticsOffender(
          focus: 'command',
          streamLabel: 'Command',
          name: summary.command,
          score: score,
          metricLabel:
              '${summary.p95Ms.toStringAsFixed(0)}ms p95 | ${(failureRate * 100).toStringAsFixed(0)}% fail',
        ),
      );
    }

    if (diffReport.modeSummaries.isNotEmpty) {
      final ranked = [...diffReport.modeSummaries]..sort((left, right) {
          double score(DiffRenderModeSummary summary) {
            final fpsPenalty =
                (60 - summary.scrollFpsP50).clamp(0, 60).toDouble();
            return summary.firstPaintP95Ms +
                summary.memoryP95Mb * 4 +
                summary.fallbackRate * 600 +
                summary.frameTimeP95Ms * 2.5 +
                summary.jankyFrameRate * 500 +
                fpsPenalty * 6;
          }

          return score(right).compareTo(score(left));
        });
      final summary = ranked.first;
      final fpsPenalty = (60 - summary.scrollFpsP50).clamp(0, 60).toDouble();
      final score = summary.firstPaintP95Ms +
          summary.memoryP95Mb * 4 +
          summary.fallbackRate * 600 +
          summary.frameTimeP95Ms * 2.5 +
          summary.jankyFrameRate * 500 +
          fpsPenalty * 6;
      offenders.add(
        _DiagnosticsOffender(
          focus: 'diff',
          streamLabel: 'Diff Render',
          name: '${summary.rendererMode} renderer',
          score: score,
          metricLabel:
              '${(summary.jankyFrameRate * 100).toStringAsFixed(0)}% jank | ${summary.frameTimeP95Ms.toStringAsFixed(0)}ms frame p95',
        ),
      );
    }

    if (uiReport.summaries.isNotEmpty) {
      final ranked = [...uiReport.summaries]..sort((left, right) {
          final leftFailureRate =
              left.count == 0 ? 0.0 : left.failureCount / left.count;
          final rightFailureRate =
              right.count == 0 ? 0.0 : right.failureCount / right.count;
          final leftScore = left.p95Ms * (1 + leftFailureRate * 3);
          final rightScore = right.p95Ms * (1 + rightFailureRate * 3);
          return rightScore.compareTo(leftScore);
        });
      final summary = ranked.first;
      final failureRate =
          summary.count == 0 ? 0.0 : summary.failureCount / summary.count;
      final score = summary.p95Ms * (1 + failureRate * 3);
      offenders.add(
        _DiagnosticsOffender(
          focus: 'ui',
          streamLabel: 'UI Timing',
          name: '${summary.phase}:${summary.event}',
          score: score,
          metricLabel:
              '${summary.p95Ms.toStringAsFixed(0)}ms p95 | ${(failureRate * 100).toStringAsFixed(0)}% fail',
        ),
      );
    }

    offenders.sort((left, right) => right.score.compareTo(left.score));
    return offenders.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final themeState = context.watch<ThemeState>();
    final aiSettings = context.watch<AiSettingsState>();
    final preferences = context.watch<PreferencesState>();
    final diagnostics = context.watch<DiagnosticsState>();
    final commandReport = diagnostics.commandLatencyReport;
    final backendCommandReport = diagnostics.backendCommandTelemetrySnapshot;
    final diffReport = diagnostics.diffRenderMetricsReport;
    final uiReport = diagnostics.uiTimingReport;
    final topOffenders =
        _buildTopOffenders(commandReport, diffReport, uiReport);
    final providerCards = _buildProviderCards();
    // Don't force-sync prompt controllers here — setting controller.text
    // resets cursor position mid-typing. The controllers are initialized
    // in initState and updated by the user's keystrokes. The debounced
    // save writes the value to AiSettingsState, not back to the controller.
    _syncCategoryControllers();

    return ListView(
      // Settings is the other place users frequently switch themes —
      // PageStorageKey survives the widget-tree restructure (glass↔solid
      // shape flip in MaterialSurface) so the scroll position doesn't
      // snap to top each time the active theme changes.
      key: const PageStorageKey('settings.scroll'),
      padding: const EdgeInsets.all(12),
      children: [
        const _FeatureHeader(),
        if (_actionMessage != null || _actionError != null) ...[
          const SizedBox(height: 10),
          _SettingsNotice(
            message: _actionError ?? _actionMessage!,
            error: _actionError != null,
          ),
        ],
        const SizedBox(height: 10),
        _ResponsiveCardRow(
          gap: 10,
          children: [
            _StateCard(
              title: 'Guardrails',
              summary:
                  'How attentive automation is across the whole experience.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GuardrailStepper(
                    stage: preferences.guardrailStage,
                    onChanged: (stage) {
                      _saveGuardrailStage(stage);
                    },
                  ),
                  const SizedBox(height: 10),
                  _WrappedAnnotation(
                    _guardrailPhrase(preferences.guardrailStage),
                    color: t.textMuted,
                  ),
                ],
              ),
            ),
            _StateCard(
              title: 'Appearance',
              summary: 'Global interface mood and atmosphere.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThemeSelect(
                    value: themeState.themeId,
                    onChanged: themeState.setTheme,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: t.chromeBorder.withValues(alpha: 0.20),
                          width: 2,
                        ),
                      ),
                    ),
                    child: _WrappedAnnotation(
                      _themeDescription(themeState.themeId),
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            _StateCard(
              title: 'Local Data Retention',
              summary: 'Diagnostic and AI audit retention policy.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _InputWithUnit(
                          unit: 'days',
                          value: diagnostics.retentionDays,
                          min: 1,
                          max: 365,
                          onChanged: (value) =>
                              _saveRetention(value, diagnostics.retentionMb),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InputWithUnit(
                          unit: 'MB',
                          value: diagnostics.retentionMb,
                          min: 16,
                          max: 4096,
                          onChanged: (value) =>
                              _saveRetention(diagnostics.retentionDays, value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _WrappedAnnotation(
                    'Includes diagnostics, performance timings, and AI metadata.',
                    color: t.textMuted,
                  ),
                  const SizedBox(height: 8),
                  _HybridRetentionActions(
                    busy: _dataMaintenanceBusy,
                    onClearDiagnostics: () {
                      _clearDiagnostics();
                    },
                    onClearAudit: () {
                      _clearAudit();
                    },
                    onClearAll: () {
                      _clearAllLocalData();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _StateCard(
          title: 'Navigation and Dynamics',
          summary: 'Shortcuts, interface behavior, and AI routing.',
          wide: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileSelect(
                value: themeState.keybindingProfile,
                onChanged: themeState.setKeybindingProfile,
              ),
              const SizedBox(height: 12),
              const _SettingsBody('Core shortcuts for the active profile.'),
              const SizedBox(height: 8),
              _ShortcutsTable(profile: themeState.keybindingProfile),
              const _SettingsGap(),
              const _SettingsSubtitle('Behavioural Dynamics'),
              const SizedBox(height: 12),
              _ReduceMotionToggle(
                value: preferences.motionRate,
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setMotionRate(value));
                },
              ),
              const SizedBox(height: 10),
              _ChangeSortGuide(
                value: preferences.fileSortGuide,
                inverted: preferences.fileSortInverted,
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setFileSortGuide(value));
                },
                onInvertedChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setFileSortInverted(value));
                },
              ),
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'AI read-only mode',
                description: 'Prevents AI from writing or staging changes automatically.',
                value: true, // Forced enabled
                enabled: false, // Grayed out
                onChanged: (_) {},
              ),
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'Logo animates when tabbed out',
                description: preferences.logoAnimatesWhenUnfocused
                    ? "It's designed to be efficient, don't hurt its feelings"
                    : ":(",
                value: preferences.logoAnimatesWhenUnfocused,
                onChanged: (value) {
                  _setLogoAnimatesWhenUnfocused(value);
                },
              ),
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'Stash cabinet starts expanded',
                description:
                    'Show the filing-cabinet drawer open by default when a repo has shelves.',
                value: preferences.stashCabinetDefaultExpanded,
                trailing: _CabinetMiniIndicator(
                  expanded: preferences.stashCabinetDefaultExpanded,
                  tokens: t,
                ),
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setStashCabinetDefaultExpanded(value));
                },
              ),
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'Instant blame hover',
                description:
                    'Skip the 180ms delay before blame info reveals on a diff line.',
                value: preferences.instantBlameHover,
                trailing: _InstantBlameMiniIndicator(
                  instant: preferences.instantBlameHover,
                  tokens: t,
                ),
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setInstantBlameHover(value));
                },
              ),
              const SizedBox(height: 16),
              _LogosDynamicsStage(
                padX: preferences.logosPadX,
                padY: preferences.logosPadY,
                onChanged: (x, y) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setLogosPad(x, y));
                },
              ),
              const _SettingsGap(),
              Row(
                children: [
                  const _SettingsSubtitle('CLI Piggybacking'),
                  const Spacer(),
                  _GhostMiniButton(
                    label: _aiProvidersLoading ? 'Refreshing...' : 'Refresh AI',
                    onTap: _aiProvidersLoading
                        ? null
                        : () {
                            _refreshAiDiagnostics(forceRefresh: true);
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _SettingsBody(
                'Directly pipe interface messages to local provider binaries.',
              ),
              if (_aiProvidersError != null && _aiProviders.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _aiProvidersError!,
                  style: TextStyle(
                    color: t.stateConflicted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
              if (_aiProvidersLoading) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: t.accentBright,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _aiProviders.isEmpty
                          ? 'Loading providers...'
                          : 'Refreshing provider diagnostics...',
                      style: TextStyle(color: t.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _ProviderGrid(providers: providerCards),
              const _SettingsGap(),
              const _SettingsSubtitle('Model Slots'),
              const SizedBox(height: 8),
              Text(
                'Rename and route configurations to any detected provider model.',
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
              if (_aiModelOptionsError != null &&
                  _aiModelCategories.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _aiModelOptionsError!,
                  style: TextStyle(
                    color: t.stateConflicted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
              if (_aiModelOptionsLoading && _aiModelCategories.isEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: t.accentBright,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading model categories...',
                      style: TextStyle(color: t.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ] else if (_aiModelCategories.isEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'No model options are available yet. Detect a compatible local AI CLI first.',
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              ] else ...[
                const SizedBox(height: 10),
                _ModelSlotsGrid(
                  categories: _aiModelCategories,
                  aiSettings: aiSettings,
                  categoryLabelControllers: _categoryLabelControllers,
                  onLabelChanged: (categoryId, value) {
                    _saveModelCategoryLabel(categoryId, value);
                  },
                  onModelChanged: (categoryId, value) {
                    if (value == null || value.isEmpty) return;
                    _saveModelSelection(categoryId, value);
                  },
                ),
              ],
              const _SettingsGap(),
              const _SettingsSubtitle('Commit Messages'),
              const SizedBox(height: 8),
              Text(
                'Pick the model slot for commit messages and add optional style guidance.',
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              if (_aiModelCategories.isNotEmpty)
                _AiCommitIntegrationEditor(
                  categories: _aiModelCategories,
                  aiSettings: aiSettings,
                  promptController: _commitPromptController,
                  promptStatusLabel: _commitPromptStatusLabel(),
                  onCategoryChanged: (value) {
                    if (value == null || value.isEmpty) {
                      return;
                    }
                    _saveCommitMessageModelCategory(value);
                  },
                  onPromptChanged: _scheduleCommitPromptSave,
                )
              else
                Text(
                  'Model-slot settings will appear here once provider models are available.',
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              const _SettingsGap(),
              const _SettingsSubtitle('Review Commit'),
              const SizedBox(height: 8),
              Text(
                'Review the current commit scope before you commit.',
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              if (_aiModelCategories.isNotEmpty)
                _AiReviewIntegrationEditor(
                  categories: _aiModelCategories,
                  aiSettings: aiSettings,
                  guardrailStage: preferences.guardrailStage,
                  promptController: _reviewPromptController,
                  promptStatusLabel: _reviewPromptStatusLabel(),
                  onCategoryChanged: (value) {
                    if (value == null || value.isEmpty) {
                      return;
                    }
                    _saveReviewCommitModelCategory(value);
                  },
                  onPromptChanged: _scheduleReviewPromptSave,
                  onDoubleCheckChanged: _saveReviewDoubleCheck,
                )
              else
                Text(
                  'Model-slot settings will appear here once provider models are available.',
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              const _SettingsGap(),
              const _SettingsSubtitle('Muse'),
              const SizedBox(height: 8),
              Text(
                'Three-phase oracle that brainstorms then synthesizes a forward direction for the diff.',
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              if (_aiModelCategories.isNotEmpty) ...[
                _MuseStage(
                  categories: _aiModelCategories,
                  aiSettings: aiSettings,
                  guardrailStage: preferences.guardrailStage,
                  onBrainstormCategoryChanged: (id) {
                    if (id == null || id.isEmpty) return;
                    unawaited(aiSettings.setMuseBrainstormModelCategoryId(id));
                  },
                  onSynthesisCategoryChanged: (id) {
                    if (id == null || id.isEmpty) return;
                    unawaited(aiSettings.setMuseSynthesisModelCategoryId(id));
                  },
                ),
                const SizedBox(height: 14),
              ],
              _AiMuseIntegrationEditor(
                promptController: _musePromptController,
                promptStatusLabel: _musePromptStatusLabel(),
                guardrailStage: preferences.guardrailStage,
                onPromptChanged: _scheduleMusePromptSave,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _SettingsGap(),
        const _SettingsSubtitle('Performance Diagnostics'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _TelemetrySwitcher(
                focus: _diagnosticsFocus,
                commandReport: commandReport,
                diffReport: diffReport,
                uiReport: uiReport,
                onFocusChanged: (focus) => setState(() => _diagnosticsFocus = focus),
              ),
            ),
            const SizedBox(width: 12),
            _GhostMiniButton(
              label: 'Copy Trace',
              onTap: _copyAllDiagnostics,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const _SettingsSubtitle('Offender Ranking'),
            const SizedBox(width: 8),
            Text(
              'Latency drivers across streams.',
              style: TextStyle(color: t.textMuted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (topOffenders.isEmpty)
          Text(
            'No offender ranking yet. Capture diagnostic activity to populate this list.',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          )
        else
          Column(
            children: [
              for (var i = 0; i < topOffenders.length; i++) ...[
                _DiagnosticsOffenderButton(
                  rank: i + 1,
                  offender: topOffenders[i],
                  onTap: () => setState(
                    () => _diagnosticsFocus = topOffenders[i].focus,
                  ),
                ),
                if (i < topOffenders.length - 1)
                  const SizedBox(height: 4),
              ],
            ],
          ),
        const _SettingsGap(),
        _DiagnosticsFocusPanel(
          focus: _diagnosticsFocus,
          commandReport: commandReport,
          backendCommandReport: backendCommandReport,
          diffReport: diffReport,
          uiReport: uiReport,
          onRefresh: diagnostics.refreshSnapshots,
          onClearCommand: diagnostics.clearCommandLatencyReport,
          onClearDiff: diagnostics.clearDiffRenderMetricsReport,
          onClearUi: diagnostics.clearUiTimingReport,
          formatSampleTime: _formatSampleTime,
        ),
        const SizedBox(height: 10),
        _StateCard(
          title: 'Release Deployment',
          summary: 'Update feeds, crash diagnostics, and environment posture.',
          wide: true,
          action: _ReplayOnboardingButton(
            onTap: () => context.read<OnboardingState>().replay(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEPLOYMENT CHANNEL',
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ChannelRibbon(
                          value: preferences.updateChannel,
                          onChanged: _saveUpdateChannel,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _CheckboxRow(
                      label: 'Capture crash diagnostics',
                      description: 'Anonymised crash snapshots.',
                      value: preferences.crashReportingEnabled,
                      onChanged: _saveCrashReporting,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _DeckButton(
                    label: 'POLL FOR UPDATES',
                    icon: Icons.radar_outlined,
                    onTap: _showUpdateStubMessage,
                  ),
                  const SizedBox(width: 8),
                  _DeckButton(
                    label: 'FORCE DEPLOY',
                    icon: Icons.system_update_alt_outlined,
                    enabled: false,
                    onTap: _showUpdateStubMessage,
                  ),
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsOffender {
  final String focus;
  final String streamLabel;
  final String name;
  final double score;
  final String metricLabel;

  const _DiagnosticsOffender({
    required this.focus,
    required this.streamLabel,
    required this.name,
    required this.score,
    required this.metricLabel,
  });
}

class _SettingsNotice extends StatelessWidget {
  final String message;
  final bool error;

  const _SettingsNotice({required this.message, required this.error});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = error ? t.stateDeleted : t.stateAdded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? t.textStrong : color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DiagnosticsOffenderButton extends StatelessWidget {
  final int rank;
  final _DiagnosticsOffender offender;
  final VoidCallback onTap;

  const _DiagnosticsOffenderButton({
    required this.rank,
    required this.offender,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: t.rowBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: t.chromeBorderFaint),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accentBright.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '0$rank',
                style: TextStyle(
                  color: t.accentBright,
                  fontSize: 9,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Text(
                    offender.name,
                    style: TextStyle(
                      color: t.textStrong,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'in ${offender.streamLabel}',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 9,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              offender.metricLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: t.accentBright.withValues(alpha: 0.8),
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsFocusPanel extends StatelessWidget {
  final String focus;
  final CommandLatencyReport commandReport;
  final CommandTelemetrySnapshotData backendCommandReport;
  final DiffRenderMetricsReport diffReport;
  final UiTimingReport uiReport;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onClearCommand;
  final Future<void> Function() onClearDiff;
  final Future<void> Function() onClearUi;
  final String Function(String value) formatSampleTime;

  const _DiagnosticsFocusPanel({
    required this.focus,
    required this.commandReport,
    required this.backendCommandReport,
    required this.diffReport,
    required this.uiReport,
    required this.onRefresh,
    required this.onClearCommand,
    required this.onClearDiff,
    required this.onClearUi,
    required this.formatSampleTime,
  });

  @override
  Widget build(BuildContext context) {
    if (focus == 'diff') {
      return _DiffDiagnosticsPanel(
        report: diffReport,
        onRefresh: onRefresh,
        onClear: onClearDiff,
        formatSampleTime: formatSampleTime,
      );
    }
    if (focus == 'ui') {
      return _UiDiagnosticsPanel(
        report: uiReport,
        onRefresh: onRefresh,
        onClear: onClearUi,
        formatSampleTime: formatSampleTime,
      );
    }
    return _CommandDiagnosticsPanel(
      report: commandReport,
      backendReport: backendCommandReport,
      onRefresh: onRefresh,
      onClear: onClearCommand,
      formatSampleTime: formatSampleTime,
    );
  }
}

class _ResponsiveCardRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const _ResponsiveCardRow({required this.children, this.gap = 10});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: gap),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i < children.length - 1) SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _FeatureHeader extends StatelessWidget {
  const _FeatureHeader();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workspace Preferences',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure global aesthetics, interface dynamics, and core operational safeguards for the entire workspace.',
                style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  final String title;
  final String summary;
  final Widget child;
  final bool wide;
  /// Optional top-right action — e.g., a small icon button aligned with
  /// the title row. Padded consistently with the card's insets.
  final Widget? action;

  const _StateCard({
    required this.title,
    required this.summary,
    required this.child,
    this.wide = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MaterialSurface(
      tone: AppMaterialTone.surface1,
      borderAlpha: 0.18,
      elevated: false,
      innerHighlight: true,
      hardShadow: true,
      padding: const EdgeInsets.all(10),
      constraints: BoxConstraints(minHeight: wide ? 0 : 168),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Small icon button living in the top-right of the Release Deployment
/// card. Re-opens the first-run onboarding flow — handy for debugging
/// and a quiet "hello again" for anyone who pokes around.
class _ReplayOnboardingButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ReplayOnboardingButton({required this.onTap});

  @override
  State<_ReplayOnboardingButton> createState() =>
      _ReplayOnboardingButtonState();
}

class _ReplayOnboardingButtonState extends State<_ReplayOnboardingButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: 'Replay onboarding',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.snap,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover
                  ? t.accentBright.withValues(alpha: 0.14)
                  : t.accentBright.withValues(alpha: 0),
              border: Border.all(
                color: _hover
                    ? t.accentBright.withValues(alpha: 0.5)
                    : t.chromeBorder.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(
                themeDefinitionFor(t.id)
                    .shader
                    .geometry
                    .radius
                    .clamp(4.0, 8.0)
                    .toDouble(),
              ),
            ),
            child: Icon(
              Icons.waving_hand_outlined,
              size: 14,
              color: _hover ? t.accentBright : t.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _GuardrailStepper extends StatelessWidget {
  final int stage;
  final ValueChanged<int> onChanged;

  const _GuardrailStepper({required this.stage, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final stageColor =
        _guardrailStageColors[stage.clamp(0, _guardrailStageColors.length - 1)];
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: stageColor,
            inactiveTrackColor: t.chromeBorder.withValues(alpha: 0.22),
            thumbColor: t.sliderThumb,
            overlayColor: stageColor.withValues(alpha: 0.16),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
            activeTickMarkColor: t.textStrong.withValues(alpha: 0.70),
            inactiveTickMarkColor: t.textMuted.withValues(alpha: 0.35),
          ),
          child: Slider(
            value: stage.toDouble(),
            min: 0,
            max: (_guardrailStageLabels.length - 1).toDouble(),
            divisions: _guardrailStageLabels.length - 1,
            onChanged: (value) => onChanged(value.round()),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < _guardrailStageLabels.length; i++)
              Expanded(
                child: Text(
                  _guardrailStageLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == stage ? t.textStrong : t.textMuted,
                    fontSize: 10,
                    fontWeight: i == stage ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _InputWithUnit extends StatefulWidget {
  final String unit;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _InputWithUnit({
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_InputWithUnit> createState() => _InputWithUnitState();
}

class _InputWithUnitState extends State<_InputWithUnit> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _InputWithUnit old) {
    super.didUpdateWidget(old);
    // Only sync from parent when unfocused — never fight the user's cursor.
    if (!_hasFocus && old.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    final focused = _focusNode.hasFocus;
    setState(() => _hasFocus = focused);
    if (!focused) {
      // Parse + commit on blur; reset to canonical on invalid.
      final parsed = int.tryParse(_controller.text.trim());
      if (parsed != null) {
        widget.onChanged(parsed.clamp(widget.min, widget.max));
      }
      _controller.text = '${widget.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // EditableText is the raw primitive beneath TextField — no ambient
    // InputDecoration, no Material ink, no nested chrome. The bordered
    // pill is drawn exactly once, by the AppInputShell below.
    return AppInputShell(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      focused: _hasFocus,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: EditableText(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                cursorColor: t.accentBright,
                backgroundCursorColor: t.textMuted,
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12,
                  fontFamily: 'JetBrainsMono',
                ),
                onSubmitted: (raw) {
                  final parsed = int.tryParse(raw.trim());
                  if (parsed != null) {
                    widget.onChanged(parsed.clamp(widget.min, widget.max));
                  }
                  _focusNode.unfocus();
                },
              ),
            ),
          ),
          Text(
            widget.unit,
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.75),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HybridRetentionActions extends StatelessWidget {
  final bool busy;
  final VoidCallback onClearDiagnostics;
  final VoidCallback onClearAudit;
  final VoidCallback onClearAll;

  const _HybridRetentionActions({
    required this.busy,
    required this.onClearDiagnostics,
    required this.onClearAudit,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const labels = ['Diag', 'Audit', 'All'];
    final actions = [onClearDiagnostics, onClearAudit, onClearAll];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IntrinsicWidth(
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: t.rowBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.chromeBorder.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  GestureDetector(
                    onTap: busy ? null : actions[i],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            color: busy
                                ? t.textMuted.withValues(alpha: 0.6)
                                : t.textNormal,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < labels.length - 1)
                    Container(
                      width: 1,
                      height: 16,
                      color: t.chromeBorder.withValues(alpha: 0.14),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '<-- clears',
          style: TextStyle(
            color: t.textMuted.withValues(alpha: 0.55),
            fontSize: 10,
            fontFamily: 'JetBrainsMono',
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _ThemeSelect extends StatelessWidget {
  final AppThemeId value;
  final ValueChanged<AppThemeId> onChanged;

  const _ThemeSelect({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ids = themeOptions.map((option) => option.id).toList(growable: false);
    return AppDropdownField<AppThemeId>(
      value: ids.contains(value) ? value : defaultThemeId,
      items: ids
          .map(
            (id) => DropdownMenuItem(
              value: id,
              child: Text(themeDefinitionFor(id).option.label),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null) {
          onChanged(id);
        }
      },
    );
  }
}

class _ChannelRibbon extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ChannelRibbon({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final channels = [
      ('stable', 'STABLE', true),
      ('beta', 'BETA', true),
      ('dev', 'DEV', true), // Enabled because user is in dev build
    ];

    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.chromeBorder.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final channel in channels)
            _ChannelRibbonItem(
              label: channel.$2,
              active: value == channel.$1,
              enabled: channel.$3,
              onTap: () => onChanged(channel.$1),
            ),
        ],
      ),
    );
  }
}

class _ChannelRibbonItem extends StatefulWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _ChannelRibbonItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_ChannelRibbonItem> createState() => _ChannelRibbonItemState();
}

class _ChannelRibbonItemState extends State<_ChannelRibbonItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final activeColor = t.accentBright;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.35,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.active ? activeColor : activeColor.withValues(alpha: 0),
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.active ? activeColor : t.textNormal,
                      fontSize: 10,
                      fontFamily: 'JetBrainsMono',
                      fontWeight:
                          widget.active ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (widget.active) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 1,
                      height: 8,
                      color: activeColor.withValues(alpha: 0.4),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSelect extends StatelessWidget {
  final KeybindingProfile value;
  final ValueChanged<KeybindingProfile> onChanged;

  const _ProfileSelect({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Text(
          'Keybinding profile',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppDropdownField<KeybindingProfile>(
            value: value,
            height: 32,
            fontWeight: FontWeight.w600,
            menuColor: t.surface1,
            items: [
              for (final profile in KeybindingProfile.values)
                DropdownMenuItem(
                  value: profile,
                  child: Text(profile.label),
                ),
            ],
            onChanged: (profile) {
              if (profile != null) {
                onChanged(profile);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ShortcutsTable extends StatelessWidget {
  final KeybindingProfile profile;

  const _ShortcutsTable({required this.profile});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = profile == KeybindingProfile.classic
        ? const [
            ('Changes', 'G C'),
            ('History', 'G H'),
            ('Branches', 'G B'),
            ('Repo X-Ray', 'G S'),
            ('Search commits', '/'),
            ('Close panel', 'Esc'),
            ('Select range (rebase)', 'Shift+Click'),
          ]
        : const [
            ('Changes', '1'),
            ('History', '2'),
            ('Branches', '3'),
            ('Repo X-Ray', '4'),
            ('Search commits', '/'),
            ('Close panel', 'Esc'),
            ('Select range (rebase)', 'Shift+Click'),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 460
            ? 1
            : constraints.maxWidth < 720
                ? 2
                : 4;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 32,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemBuilder: (context, index) {
            final row = rows[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: t.chromeBorder.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: t.chromeBorder.withValues(alpha: 0.10)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11,
                        fontFamily: 'JetBrainsMono',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: t.chromeBorder.withValues(alpha: 0.30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: t.chromeBorder.withValues(alpha: 0.15),
                          offset: const Offset(0, 1.5),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Text(
                      row.$2,
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ProviderNode extends StatelessWidget {
  final String id;
  final String status;
  final String binaryLabel;
  final String? detail;
  final bool ready;
  final bool placeholder;

  const _ProviderNode({
    required this.id,
    required this.status,
    required this.binaryLabel,
    this.detail,
    this.ready = false,
    this.placeholder = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final statusColor = placeholder
        ? t.textMuted
        : ready
            ? t.stateAdded
            : t.stateConflicted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.rowBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                binaryLabel,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
              if (detail != null && detail!.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.50),
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderCard {
  final String id;
  final String binaryLabel;
  final String status;
  final String? detail;
  final bool ready;
  final bool placeholder;

  const _ProviderCard({
    required this.id,
    required this.binaryLabel,
    required this.status,
    this.detail,
    this.ready = false,
    this.placeholder = false,
  });
}

class _ProviderGrid extends StatelessWidget {
  final List<_ProviderCard> providers;

  const _ProviderGrid({required this.providers});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520
            ? 1
            : constraints.maxWidth < 800
                ? 2
                : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: providers.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 64,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final p = providers[index];
            return _ProviderNode(
              id: p.id,
              binaryLabel: p.binaryLabel,
              status: p.status,
              detail: p.detail,
              ready: p.ready,
              placeholder: p.placeholder,
            );
          },
        );
      },
    );
  }
}

class _EditableSlotTitle extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _EditableSlotTitle({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  State<_EditableSlotTitle> createState() => _EditableSlotTitleState();
}

class _EditableSlotTitleState extends State<_EditableSlotTitle> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final titleStyle = TextStyle(
      color: t.textStrong,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      maxLines: 1,
      onChanged: widget.onChanged,
      cursorColor: t.accentBright,
      style: titleStyle,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: widget.hintText,
        hintStyle: titleStyle.copyWith(
          color: t.textStrong.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}

/// Renders all model slots in a 2-column fluid grid, each slot compact.
class _ModelSlotsGrid extends StatelessWidget {
  final List<AiModelCategoryData> categories;
  final AiSettingsState aiSettings;
  final Map<String, TextEditingController> categoryLabelControllers;
  final void Function(String categoryId, String value) onLabelChanged;
  final void Function(String categoryId, String? value) onModelChanged;

  const _ModelSlotsGrid({
    required this.categories,
    required this.aiSettings,
    required this.categoryLabelControllers,
    required this.onLabelChanged,
    required this.onModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 520;
        if (!twoCol) {
          return Column(
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                _CompactModelSlot(
                  category: categories[i],
                  controller: categoryLabelControllers[categories[i].id]!,
                  selectedValue: aiSettings.modelSelections[categories[i].id] ??
                      (categories[i].models.isNotEmpty
                          ? categories[i].models.first.value
                          : ''),
                  onLabelChanged: (v) => onLabelChanged(categories[i].id, v),
                  onModelChanged: categories[i].models.isEmpty
                      ? null
                      : (v) => onModelChanged(categories[i].id, v),
                ),
                if (i < categories.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }

        // 2-column grid
        final rows = <Widget>[];
        for (var i = 0; i < categories.length; i += 2) {
          final left = categories[i];
          final right = i + 1 < categories.length ? categories[i + 1] : null;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CompactModelSlot(
                    category: left,
                    controller: categoryLabelControllers[left.id]!,
                    selectedValue: aiSettings.modelSelections[left.id] ??
                        (left.models.isNotEmpty ? left.models.first.value : ''),
                    onLabelChanged: (v) => onLabelChanged(left.id, v),
                    onModelChanged: left.models.isEmpty
                        ? null
                        : (v) => onModelChanged(left.id, v),
                  ),
                ),
                if (right != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CompactModelSlot(
                      category: right,
                      controller: categoryLabelControllers[right.id]!,
                      selectedValue: aiSettings.modelSelections[right.id] ??
                          (right.models.isNotEmpty
                              ? right.models.first.value
                              : ''),
                      onLabelChanged: (v) => onLabelChanged(right.id, v),
                      onModelChanged: right.models.isEmpty
                          ? null
                          : (v) => onModelChanged(right.id, v),
                    ),
                  ),
                ] else ...[const SizedBox(), const SizedBox()],
              ],
            ),
          );
          if (i + 2 < categories.length) rows.add(const SizedBox(height: 8));
        }
        return Column(children: rows);
      },
    );
  }
}

/// Compact model slot tile — label editable inline, dropdown below, provider pill on the right.
class _CompactModelSlot extends StatefulWidget {
  final AiModelCategoryData category;
  final TextEditingController controller;
  final String selectedValue;
  final ValueChanged<String> onLabelChanged;
  final ValueChanged<String?>? onModelChanged;

  const _CompactModelSlot({
    required this.category,
    required this.controller,
    required this.selectedValue,
    required this.onLabelChanged,
    required this.onModelChanged,
  });

  @override
  State<_CompactModelSlot> createState() => _CompactModelSlotState();
}

class _CompactModelSlotState extends State<_CompactModelSlot> {
  final Map<String, TextEditingController> _customControllers = {};

  List<({String providerId, String providerLabel})> get _uniqueProviders {
    final seen = <String>{};
    final result = <({String providerId, String providerLabel})>[];
    for (final model in widget.category.models) {
      if (seen.add(model.providerId)) {
        result.add((
          providerId: model.providerId,
          providerLabel: model.providerLabel,
        ));
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(_CompactModelSlot old) {
    super.didUpdateWidget(old);
    if (old.category.models != widget.category.models ||
        old.selectedValue != widget.selectedValue) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    final providers = _uniqueProviders;
    final providerIds = providers.map((p) => p.providerId).toSet();

    for (final p in providers) {
      _customControllers.putIfAbsent(p.providerId, () => TextEditingController());
    }

    for (final key in _customControllers.keys.where((k) => !providerIds.contains(k)).toList()) {
      _customControllers.remove(key)!.dispose();
    }

    // Pre-fill when selected value is a custom entry for a known provider.
    final sel = widget.selectedValue;
    final colonIdx = sel.indexOf(':');
    if (colonIdx > 0) {
      final selProvider = sel.substring(0, colonIdx);
      final selModel = sel.substring(colonIdx + 1);
      final knownValues = widget.category.models.map((m) => m.value).toSet();
      final ctrl = _customControllers[selProvider];
      if (!knownValues.contains(sel) && ctrl != null && ctrl.text != selModel) {
        ctrl.text = selModel;
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _customControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _commitCustom(String providerId) {
    if (widget.onModelChanged == null) return;
    final text = _customControllers[providerId]?.text.trim() ?? '';
    if (text.isEmpty) return;
    widget.onModelChanged!('$providerId:$text');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    AiModelOptionData? selectedModel;
    for (final model in widget.category.models) {
      if (model.value == widget.selectedValue) {
        selectedModel = model;
        break;
      }
    }

    // Resolve provider label even for custom selections.
    String? resolvedProviderLabel = selectedModel?.providerLabel;
    if (resolvedProviderLabel == null && widget.selectedValue.contains(':')) {
      final selProvider = widget.selectedValue.split(':').first;
      for (final model in widget.category.models) {
        if (model.providerId == selProvider) {
          resolvedProviderLabel = model.providerLabel;
          break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _EditableSlotTitle(
                  controller: widget.controller,
                  hintText: widget.category.label,
                  onChanged: widget.onLabelChanged,
                ),
              ),
              const SizedBox(width: 8),
              if (resolvedProviderLabel != null)
                _ProviderPill(label: resolvedProviderLabel),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.category.models.isEmpty)
            Text(
              'No models detected for this slot.',
              style: TextStyle(color: t.textMuted, fontSize: 11),
            )
          else
            _ModelPickerField(
              value: widget.selectedValue,
              models: widget.category.models,
              providers: _uniqueProviders,
              customControllers: _customControllers,
              onChanged: widget.onModelChanged ?? (_) {},
              onCustomSubmit: _commitCustom,
            ),
          if (resolvedProviderLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              'via ${resolvedProviderLabel.toLowerCase()}',
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.65),
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single custom-model input row: mono provider label + text field.
class _CustomModelRow extends StatelessWidget {
  final String providerLabel;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _CustomModelRow({
    required this.providerLabel,
    required this.controller,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            providerLabel.toLowerCase(),
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.50),
              fontSize: 10,
              fontFamily: 'JetBrainsMono',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: 1,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 11,
              fontFamily: 'JetBrainsMono',
            ),
            cursorColor: t.accentBright,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: t.chromeBorder.withValues(alpha: 0.22)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: t.chromeBorder.withValues(alpha: 0.22)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: t.accentBright.withValues(alpha: 0.50)),
              ),
              hintText: 'custom model id',
              hintStyle: TextStyle(
                color: t.textMuted.withValues(alpha: 0.30),
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small rounded pill showing a provider name.
class _ProviderPill extends StatelessWidget {
  final String label;
  const _ProviderPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.accentBright.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.accentBright.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: t.accentBright.withValues(alpha: 0.85),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// Custom overlay-based model picker — replaces AppDropdownField so that the
// custom-model text inputs live inside the popup list itself.

class _ModelPickerField extends StatefulWidget {
  final String value;
  final List<AiModelOptionData> models;
  final List<({String providerId, String providerLabel})> providers;
  final Map<String, TextEditingController> customControllers;
  final ValueChanged<String?> onChanged;
  final void Function(String providerId) onCustomSubmit;

  const _ModelPickerField({
    required this.value,
    required this.models,
    required this.providers,
    required this.customControllers,
    required this.onChanged,
    required this.onCustomSubmit,
  });

  @override
  State<_ModelPickerField> createState() => _ModelPickerFieldState();
}

class _ModelPickerFieldState extends State<_ModelPickerField> {
  final _link = LayerLink();
  final _triggerKey = GlobalKey();
  OverlayEntry? _entry;

  bool get _isOpen => _entry != null;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _toggle() => _isOpen ? _closeOverlay() : _openOverlay();

  void _openOverlay() {
    if (_isOpen) return;
    _entry = OverlayEntry(builder: _buildOverlayContent);
    Overlay.of(context).insert(_entry!);
    setState(() {});
  }

  void _closeOverlay() {
    if (!_isOpen) return;
    _entry!.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _select(String v) {
    widget.onChanged(v);
    _closeOverlay();
  }

  void _submitCustom(String providerId) {
    widget.onCustomSubmit(providerId);
    _closeOverlay();
  }

  Widget _buildOverlayContent(BuildContext ctx) {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 240.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeOverlay,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: _ModelPickerOverlay(
              models: widget.models,
              selectedValue: widget.value,
              providers: widget.providers,
              customControllers: widget.customControllers,
              onSelect: _select,
              onCustomSubmit: _submitCustom,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Display label for the trigger.
    String label = widget.value;
    for (final m in widget.models) {
      if (m.value == widget.value) {
        label = m.label;
        break;
      }
    }
    // Custom value: show just the model-id part.
    if (label == widget.value &&
        widget.value.contains(':') &&
        !widget.models.any((m) => m.value == widget.value)) {
      label = widget.value.split(':').last;
    }

    return CompositedTransformTarget(
      link: _link,
      child: AppInputShell(
        key: _triggerKey,
        focused: _isOpen,
        child: GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: t.textNormal, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: t.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelPickerOverlay extends StatelessWidget {
  final List<AiModelOptionData> models;
  final String selectedValue;
  final List<({String providerId, String providerLabel})> providers;
  final Map<String, TextEditingController> customControllers;
  final ValueChanged<String> onSelect;
  final void Function(String providerId) onCustomSubmit;

  const _ModelPickerOverlay({
    required this.models,
    required this.selectedValue,
    required this.providers,
    required this.customControllers,
    required this.onSelect,
    required this.onCustomSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.bg1,
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: [
                  for (final model in models)
                    _ModelPickerItem(
                      model: model,
                      selected: model.value == selectedValue,
                      onTap: () => onSelect(model.value),
                    ),
                ],
              ),
            ),
            if (providers.isNotEmpty) ...[
              Divider(
                height: 1,
                thickness: 1,
                color: t.chromeBorder.withValues(alpha: 0.12),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  children: [
                    for (var i = 0; i < providers.length; i++) ...[
                      _CustomModelRow(
                        providerLabel: providers[i].providerLabel,
                        controller: customControllers[providers[i].providerId]!,
                        onSubmit: () => onCustomSubmit(providers[i].providerId),
                      ),
                      if (i < providers.length - 1) const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelPickerItem extends StatelessWidget {
  final AiModelOptionData model;
  final bool selected;
  final VoidCallback onTap;

  const _ModelPickerItem({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        color: selected ? t.accentBright.withValues(alpha: 0.08) : null,
        child: Text(
          model.label,
          style: TextStyle(
            color: selected ? t.accentBright : t.textNormal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _AiCommitIntegrationEditor extends StatelessWidget {
  final List<AiModelCategoryData> categories;
  final AiSettingsState aiSettings;
  final TextEditingController promptController;
  final String? promptStatusLabel;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onPromptChanged;

  const _AiCommitIntegrationEditor({
    required this.categories,
    required this.aiSettings,
    required this.promptController,
    required this.promptStatusLabel,
    required this.onCategoryChanged,
    required this.onPromptChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selectedCategoryId = categories.any(
      (category) => category.id == aiSettings.commitMessageModelCategoryId,
    )
        ? aiSettings.commitMessageModelCategoryId
        : categories.first.id;
    final selectedCategory =
        categories.where((category) => category.id == selectedCategoryId).first;
    AiModelOptionData? selectedModel;
    for (final model in selectedCategory.models) {
      if (model.value == aiSettings.modelSelections[selectedCategory.id]) {
        selectedModel = model;
        break;
      }
    }
    selectedModel ??=
        selectedCategory.models.isEmpty ? null : selectedCategory.models.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact slot selector row
        _AiSlotSelectorRow(
          selectedCategoryId: selectedCategoryId,
          selectedModel: selectedModel,
          categories: categories,
          aiSettings: aiSettings,
          onCategoryChanged: onCategoryChanged,
          statusLabel: promptStatusLabel,
        ),
        const SizedBox(height: 12),
        // Format stage — sets the default shape (structure/voice/
        // coverage) of generated commit messages. AI generation and the
        // manual composer both consult these prefs; the Style Guide
        // below layers voice/tone notes on top.
        _CommitFormatStage(
          structure: context.watch<PreferencesState>().commitStructure,
          voice: context.watch<PreferencesState>().commitVoice,
          coverage: context.watch<PreferencesState>().commitCoverage,
          onStructureChanged: (v) {
            unawaited(context
                .read<PreferencesState>()
                .setCommitStructure(v));
          },
          onVoiceChanged: (v) {
            unawaited(context.read<PreferencesState>().setCommitVoice(v));
          },
          onCoverageChanged: (v) {
            unawaited(
                context.read<PreferencesState>().setCommitCoverage(v));
          },
        ),
        const SizedBox(height: 12),
        const _SettingsSubtitle('Style Guide'),
        const SizedBox(height: 8),
        AppMultilineTextField(
          controller: promptController,
          hintText:
              'Optional. Voice / tone / bans. The format above handles skeleton.',
          minHeight: 100,
          maxHeight: 200,
          onChanged: onPromptChanged,
        ),
      ],
    );
  }
}

class _AiReviewIntegrationEditor extends StatelessWidget {
  final List<AiModelCategoryData> categories;
  final AiSettingsState aiSettings;
  final int guardrailStage;
  final TextEditingController promptController;
  final String? promptStatusLabel;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onPromptChanged;
  final ValueChanged<bool> onDoubleCheckChanged;

  const _AiReviewIntegrationEditor({
    required this.categories,
    required this.aiSettings,
    required this.guardrailStage,
    required this.promptController,
    required this.promptStatusLabel,
    required this.onCategoryChanged,
    required this.onPromptChanged,
    required this.onDoubleCheckChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selectedCategoryId = categories.any(
      (category) => category.id == aiSettings.reviewCommitModelCategoryId,
    )
        ? aiSettings.reviewCommitModelCategoryId
        : categories.first.id;
    final selectedCategory =
        categories.where((category) => category.id == selectedCategoryId).first;
    AiModelOptionData? selectedModel;
    for (final model in selectedCategory.models) {
      if (model.value == aiSettings.modelSelections[selectedCategory.id]) {
        selectedModel = model;
        break;
      }
    }
    selectedModel ??=
        selectedCategory.models.isEmpty ? null : selectedCategory.models.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact slot selector row
        _AiSlotSelectorRow(
          selectedCategoryId: selectedCategoryId,
          selectedModel: selectedModel,
          categories: categories,
          aiSettings: aiSettings,
          onCategoryChanged: onCategoryChanged,
          statusLabel: promptStatusLabel,
        ),
        const SizedBox(height: 12),
        const _SettingsSubtitle('Additional notes to review with'),
        const SizedBox(height: 8),
        AppMultilineTextField(
          controller: promptController,
          hintText: _reviewGuideHint(guardrailStage),
          minHeight: 100,
          maxHeight: 200,
          onChanged: onPromptChanged,
        ),
        const SizedBox(height: 12),
        _CheckboxRow(
          label: 'Double-check review',
          description: 'Run a second verification pass before showing the final report.',
          value: aiSettings.reviewCommitDoubleCheckEnabled,
          onChanged: onDoubleCheckChanged,
        ),
      ],
    );
  }
}

class _AiMuseIntegrationEditor extends StatelessWidget {
  final TextEditingController promptController;
  final String? promptStatusLabel;
  final int guardrailStage;
  final ValueChanged<String> onPromptChanged;

  const _AiMuseIntegrationEditor({
    required this.promptController,
    required this.promptStatusLabel,
    required this.guardrailStage,
    required this.onPromptChanged,
  });

  // Placeholder echoes the muse profile at the active guardrail level.
  // Lowercase to match the composer's tooltip vocabulary; short so it
  // doesn't read as instruction noise.
  static String _hintForGuardrail(int stage) {
    switch (stage.clamp(0, 3)) {
      case 0:
        return 'anything to gently steer toward? mood is kind today.';
      case 1:
        return 'what to dwell on, what to skip. honest, not harsh.';
      case 2:
        return 'the standards. the bans. what the muse won\'t let slide.';
      default:
        return 'tune the lens. what frequencies should the manifold hum at?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SettingsSubtitle('Additional notes for the muse'),
            if (promptStatusLabel != null) ...[
              const SizedBox(width: 8),
              Text(
                promptStatusLabel!.toLowerCase(),
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AppMultilineTextField(
          controller: promptController,
          hintText: _hintForGuardrail(guardrailStage),
          minHeight: 100,
          maxHeight: 200,
          onChanged: onPromptChanged,
        ),
      ],
    );
  }
}

/// The muse stage — a [1] → [2] visual that lets the user assign which
/// AI category (slot) drives each phase of the oracle pipeline.
/// Phase 1 (brainstorm) is cheap and divergent — defaults to "fast".
/// Phase 2 (synthesis) is rigorous and grounding-aware — defaults to
/// the same category review uses, typically "quality". Either may be
/// remapped here. The down-arrow between stations is annotated with
/// the guardrail-derived idea count, surfacing what the macro setting
/// is actually doing without taking control away from it.
class _MuseStage extends StatelessWidget {
  final List<AiModelCategoryData> categories;
  final AiSettingsState aiSettings;
  final int guardrailStage;
  final ValueChanged<String?> onBrainstormCategoryChanged;
  final ValueChanged<String?> onSynthesisCategoryChanged;

  const _MuseStage({
    required this.categories,
    required this.aiSettings,
    required this.guardrailStage,
    required this.onBrainstormCategoryChanged,
    required this.onSynthesisCategoryChanged,
  });

  // Same axis as MuseGuardrailProfile.suggestedIdeaCount in ai.dart —
  // duplicated here for the inline annotation. Kept terse on purpose.
  String _guardrailIdeaCountHint(int stage) {
    switch (stage.clamp(0, 3)) {
      case 0:
        return '~12 ideas';
      case 1:
        return '~16 ideas';
      case 2:
        return '~20 ideas';
      default:
        return '~24 ideas';
    }
  }

  String _guardrailMacroLabel(int stage) {
    switch (stage.clamp(0, 3)) {
      case 0:
        return 'loose';
      case 1:
        return 'balanced';
      case 2:
        return 'strict';
      default:
        return 'paranoid';
    }
  }

  AiModelCategoryData _resolveCategory(String preferredId) {
    return categories
            .where((c) => c.id == preferredId && c.models.isNotEmpty)
            .firstOrNull ??
        categories.firstWhere((c) => c.models.isNotEmpty,
            orElse: () => categories.first);
  }

  AiModelOptionData? _resolveModel(AiModelCategoryData category) {
    return category.models
            .where((m) =>
                m.value == aiSettings.modelSelections[category.id])
            .firstOrNull ??
        category.models.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final brain = _resolveCategory(aiSettings.museBrainstormModelCategoryId);
    final synth = _resolveCategory(aiSettings.museSynthesisModelCategoryId);
    final brainModel = _resolveModel(brain);
    final synthModel = _resolveModel(synth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MuseStation(
          tokens: t,
          number: '1',
          title: 'BRAINSTORM',
          slotLabel: 'slot',
          categories: categories,
          aiSettings: aiSettings,
          selectedCategoryId: brain.id,
          selectedModel: brainModel,
          onCategoryChanged: onBrainstormCategoryChanged,
        ),
        // Connector — a continuous vertical thread from the bottom of
        // station 1 to the top of station 2, aligned with the [N] tag
        // column so the flow reads as one diagram. Arrow + annotation
        // float on the right of the thread at its midpoint.
        SizedBox(
          height: 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // x-offset matches the station padding (12) + half the
              // [N] tag width (~7) so the line emerges out of the
              // numbered tag column above and re-enters it below.
              const SizedBox(width: 18),
              Container(
                width: 1,
                color: t.textMuted.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 12),
              Icon(Icons.south, size: 12,
                  color: t.textMuted.withValues(alpha: 0.6)),
              const SizedBox(width: 8),
              Text(
                '${_guardrailIdeaCountHint(guardrailStage)}  ·  guardrail: ${_guardrailMacroLabel(guardrailStage)}',
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.7),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        _MuseStation(
          tokens: t,
          number: '2',
          title: 'SYNTHESIZE',
          slotLabel: 'slot',
          categories: categories,
          aiSettings: aiSettings,
          selectedCategoryId: synth.id,
          selectedModel: synthModel,
          onCategoryChanged: onSynthesisCategoryChanged,
        ),
      ],
    );
  }
}

/// Numbered station inside the muse pipeline.
/// Header row shows [1]/[2] and phase title. Body row has the model
/// dropdown plus resolved model pill.
class _MuseStation extends StatelessWidget {
  final AppTokens tokens;
  final String number;
  final String title;
  final String slotLabel;
  final List<AiModelCategoryData> categories;
  final AiSettingsState aiSettings;
  final String selectedCategoryId;
  final AiModelOptionData? selectedModel;
  final ValueChanged<String?> onCategoryChanged;

  const _MuseStation({
    required this.tokens,
    required this.number,
    required this.title,
    required this.slotLabel,
    required this.categories,
    required this.aiSettings,
    required this.selectedCategoryId,
    required this.selectedModel,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: t.textMuted.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: [N]  TITLE
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: t.accentBright.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    color: t.accentBright,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Body: slot dropdown + provider pill on one row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                slotLabel,
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDropdownField<String>(
                  value: selectedCategoryId,
                  items: categories
                      .map((category) => DropdownMenuItem<String>(
                            value: category.id,
                            child: Text(aiSettings.labelForCategory(
                                category.id, category.label)),
                          ))
                      .toList(),
                  onChanged: onCategoryChanged,
                ),
              ),
              if (selectedModel != null) ...[
                const SizedBox(width: 8),
                _ProviderPill(label: selectedModel!.providerLabel),
              ],
            ],
          ),
          if (selectedModel != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                selectedModel!.label,
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.75),
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared compact slot selector: label+provider pill on one line, dropdown below.
class _AiSlotSelectorRow extends StatelessWidget {
  final String selectedCategoryId;
  final AiModelOptionData? selectedModel;
  final List<AiModelCategoryData> categories;
  final AiSettingsState aiSettings;
  final ValueChanged<String?> onCategoryChanged;
  final String? statusLabel;

  const _AiSlotSelectorRow({
    required this.selectedCategoryId,
    required this.selectedModel,
    required this.categories,
    required this.aiSettings,
    required this.onCategoryChanged,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AppDropdownField<String>(
            value: selectedCategoryId,
            items: categories
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category.id,
                    child: Text(
                      aiSettings.labelForCategory(category.id, category.label),
                    ),
                  ),
                )
                .toList(),
            onChanged: onCategoryChanged,
          ),
        ),
        if (selectedModel != null) ...[
          const SizedBox(width: 8),
          _ProviderPill(label: selectedModel!.providerLabel),
        ],
        if (statusLabel != null) ...[
          const SizedBox(width: 8),
          Text(
            statusLabel!,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Section subtitle label — readable, anchored with a left accent stroke.
class _SettingsSubtitle extends StatelessWidget {
  final String label;

  const _SettingsSubtitle(this.label);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 2,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: t.accentBright.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: t.textNormal,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Body description text — the most common text pattern in settings.
class _SettingsBody extends StatelessWidget {
  final String text;

  const _SettingsBody(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
    );
  }
}

/// Consistent vertical gap between settings sections — a thin ruled divider.
class _SettingsGap extends StatelessWidget {
  const _SettingsGap();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              t.chromeBorder.withValues(alpha: 0),
              t.chromeBorder.withValues(alpha: 0.18),
              t.chromeBorder.withValues(alpha: 0.18),
              t.chromeBorder.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.15, 0.85, 1.0],
          ),
        ),
      ),
    );
  }
}

// Logos pad and grip are one control: interactive tuning + static status.

class _LogosDynamicsStage extends StatelessWidget {
  final double padX;
  final double padY;
  final void Function(double x, double y) onChanged;

  const _LogosDynamicsStage({
    required this.padX,
    required this.padY,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      // Pad uses the remaining width; grip stays fixed at 128px.
      const gripW = 128.0;
      const gap = 12.0;
      final totalW = c.maxWidth.clamp(420.0, 720.0).toDouble();
      final padW = (totalW - gripW - gap).clamp(280.0, 600.0).toDouble();
      final padH = (padW / 1.7).clamp(220.0, 360.0).toDouble();
      // Use IntrinsicHeight so whichever child is taller sets the row height.
      return SizedBox(
        width: totalW,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: padW,
                height: padH,
                child: _LogosPad(
                  x: padX,
                  y: padY,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: gap),
              const SizedBox(
                width: gripW,
                child: _LogosGrip(),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _LogosPad extends StatefulWidget {
  final double x;
  final double y;
  final void Function(double x, double y) onChanged;

  const _LogosPad({
    required this.x,
    required this.y,
    required this.onChanged,
  });

  @override
  State<_LogosPad> createState() => _LogosPadState();
}

/// Trail point used for the puck history.
/// Alpha is calculated from age at paint time, not stored state.
class _TrailDot {
  final double x;
  final double y;
  final DateTime at;
  _TrailDot(this.x, this.y, this.at);
}

class _LogosPadState extends State<_LogosPad>
    with SingleTickerProviderStateMixin {
  // Ambient pulse drives the halo and field shimmer.
  late final AnimationController _ambient;

  // Keep a capped trail of puck positions while dragging.
  final List<_TrailDot> _trail = [];
  static const int _kTrailMax = 18;
  static const Duration _kTrailFade = Duration(milliseconds: 520);

  bool _hovered = false;

  // Cursor parallax is normalized to [-1, 1] around the pad center.
  Offset _targetParallax = Offset.zero;
  Offset _currentParallax = Offset.zero;

  // Scroll parallax adds a small Y shift based on scroll position.
  ScrollPosition? _scrollPos;
  double _scrollParallaxY = 0.0;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final found = Scrollable.maybeOf(context)?.position;
    if (!identical(found, _scrollPos)) {
      _scrollPos?.removeListener(_onScroll);
      _scrollPos = found;
      _scrollPos?.addListener(_onScroll);
      // Recompute scroll offset once layout is settled.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  void _onScroll() {
    if (!mounted) return;
    final scroll = _scrollPos;
    if (scroll == null) return;
    final scrollableContext = Scrollable.maybeOf(context)?.context;
    final scrollBox = scrollableContext?.findRenderObject() as RenderBox?;
    final myBox = context.findRenderObject() as RenderBox?;
    if (scrollBox == null || myBox == null) return;
    final myCenter = myBox.localToGlobal(
      Offset(myBox.size.width / 2, myBox.size.height / 2),
      ancestor: scrollBox,
    );
    final viewportH = scrollBox.size.height;
    // -1 when pad center sits at top edge, +1 at bottom edge of the
    // viewport. Clamped so values past the visible window saturate
    // rather than spiraling out.
    final norm = ((myCenter.dy / viewportH) - 0.5) * 2;
    final clamped = norm.clamp(-1.0, 1.0);
    if ((clamped - _scrollParallaxY).abs() > 0.001) {
      setState(() => _scrollParallaxY = clamped);
    }
  }

  @override
  void dispose() {
    _scrollPos?.removeListener(_onScroll);
    _ambient.dispose();
    super.dispose();
  }

  // Snap radius around center dampens small pointer movements.
  static const double _kSnapRadius = 0.045;

  void _emit(Offset pos, double w, double h) {
    var nx = (pos.dx / w).clamp(0.0, 1.0);
    var ny = (pos.dy / h).clamp(0.0, 1.0);
    final dx = nx - 0.5;
    final dy = ny - 0.5;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < _kSnapRadius) {
      // Smoothstep keeps movement gradual near center.
      final t = dist / _kSnapRadius;
      final gain = t * t * (3 - 2 * t);
      nx = 0.5 + dx * gain;
      ny = 0.5 + dy * gain;
    }
    _trail.add(_TrailDot(nx, ny, DateTime.now()));
    if (_trail.length > _kTrailMax) {
      _trail.removeRange(0, _trail.length - _kTrailMax);
    }
    widget.onChanged(nx, ny);
  }

  void _onHover(Offset pos, double w, double h) {
    _targetParallax = Offset(
      ((pos.dx / w) - 0.5) * 2,
      ((pos.dy / h) - 0.5) * 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      return MouseRegion(
        cursor: SystemMouseCursors.precise,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) {
          _targetParallax = Offset.zero;
          setState(() => _hovered = false);
        },
        onHover: (e) => _onHover(e.localPosition, w, h),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            _onHover(d.localPosition, w, h);
            _emit(d.localPosition, w, h);
          },
          onPanStart: (d) {
            _onHover(d.localPosition, w, h);
            _emit(d.localPosition, w, h);
          },
          onTapDown: (d) {
            _onHover(d.localPosition, w, h);
            _emit(d.localPosition, w, h);
          },
          child: AnimatedBuilder(
            animation: _ambient,
            builder: (_, __) {
              // Drop stale trail points while rendering.
              final now = DateTime.now();
              _trail.removeWhere(
                (d) => now.difference(d.at) > _kTrailFade,
              );
              // Critically damped easing keeps the parallax smooth.
              const easing = 0.18;
              _currentParallax = Offset(
                _currentParallax.dx +
                    (_targetParallax.dx - _currentParallax.dx) * easing,
                _currentParallax.dy +
                    (_targetParallax.dy - _currentParallax.dy) * easing,
              );
              // Combine hover and scroll parallax; scroll effect is softer.
              final combined = Offset(
                _currentParallax.dx,
                _currentParallax.dy + _scrollParallaxY * 0.55,
              );
              return CustomPaint(
                painter: _LogosPadPainter(
                  x: widget.x,
                  y: widget.y,
                  hovered: _hovered,
                  ambient: _ambient.value,
                  parallax: combined,
                  trail: _trail,
                  now: now,
                  tokens: t,
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

/// Point in the pad for one file path.
/// Relevance is based on distance from the puck.
class _LogosNode {
  final String path;
  final double bx;
  final double by;
  const _LogosNode(this.path, this.bx, this.by);
}

// Nodes are real paths from this app/session.
// Grouped by axis (folder/history x far/near).
const List<_LogosNode> _kLogosNodes = [
  // Folder × Far — directory roots, the architecture-level view.
  _LogosNode('backend/', 0.12, 0.16),
  _LogosNode('features/', 0.26, 0.10),
  _LogosNode('ui/', 0.08, 0.30),
  _LogosNode('app/', 0.30, 0.26),
  // History × Far — repo-wide hubs git keeps revisiting.
  _LogosNode('app/main.dart', 0.84, 0.14),
  _LogosNode('app/repository_state.dart', 0.74, 0.24),
  _LogosNode('ui/tokens.dart', 0.92, 0.28),
  // Folder × Near — siblings of logos_git.dart in backend/.
  _LogosNode('backend/logos_core.dart', 0.10, 0.78),
  _LogosNode('backend/logos_chunks.dart', 0.22, 0.86),
  _LogosNode('backend/logos_hunks.dart', 0.30, 0.72),
  _LogosNode('backend/logos_git_stats.dart', 0.06, 0.66),
  // History × Near — what moved alongside the pad work itself.
  _LogosNode('features/settings/settings_page.dart', 0.86, 0.84),
  _LogosNode('app/preferences_state.dart', 0.72, 0.74),
  _LogosNode('backend/settings_store.dart', 0.92, 0.68),
];

class _LogosPadPainter extends CustomPainter {
  final double x;
  final double y;
  final bool hovered;
  final double ambient; // 0..1, driven by AnimationController
  final Offset parallax; // -1..1 normalized cursor offset from center
  final List<_TrailDot> trail;
  final DateTime now;
  final AppTokens tokens;

  _LogosPadPainter({
    required this.x,
    required this.y,
    required this.hovered,
    required this.ambient,
    required this.parallax,
    required this.trail,
    required this.now,
    required this.tokens,
  });

  // Parallax offsets for depth layers, in pixels at full deflection.
  static const double _depthFieldPx = -3.0;
  static const double _depthGridPx = -2.0;
  static const double _depthGlyphPx = 1.5;
  static const double _depthNodePx = 4.0;
  static const double _depthPuckPx = 7.5;

  Offset _shift(double depthPx) =>
      Offset(parallax.dx * depthPx, parallax.dy * depthPx);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(rr);

    // Each depth layer is translated independently.
    void layer(double depthPx, void Function() draw) {
      final s = _shift(depthPx);
      canvas.save();
      canvas.translate(s.dx, s.dy);
      draw();
      canvas.restore();
    }

    layer(_depthFieldPx, () => _paintField(canvas, w, h));
    layer(_depthGridPx, () {
      _paintGrid(canvas, w, h);
      _paintAxisHints(canvas, w, h);
    });
    layer(_depthGlyphPx, () => _paintPictograms(canvas, w, h));
    layer(_depthNodePx, () => _paintNodes(canvas, w, h));
    layer(_depthNodePx, () => _paintTrail(canvas, w, h));
    layer(_depthPuckPx, () {
      _paintPuck(canvas, w, h);
      _paintQuadrantWhisper(canvas, w, h);
    });

    canvas.restore();

    // Border drawn outside the clip so it remains crisp.
    final border = Paint()
      ..color = tokens.chromeBorder.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rr, border);
  }

  //
  /// Deterministic textured background.
  ///
  /// Stable hash keeps the dot field static between frames.
  void _paintField(Canvas canvas, double w, double h) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = tokens.surface0.withValues(alpha: 0.5),
    );

    // Static jittered dots create subtle texture without shimmer.
    const step = 14.0;
    final dotPaint = Paint()..style = PaintingStyle.fill;
    int hash(int a, int b) {
      // Deterministic hash avoids allocations and drift.
      var n = (a * 73856093) ^ (b * 19349663);
      n = (n ^ (n >> 13)) * 1274126177;
      return n & 0x7fffffff;
    }

    for (double gy = step / 2; gy < h; gy += step) {
      for (double gx = step / 2; gx < w; gx += step) {
        final ix = (gx / step).floor();
        final iy = (gy / step).floor();
        final hRaw = hash(ix, iy);
        // Jitter +/- 3px from grid position.
        final jx = ((hRaw & 0xff) / 255.0 - 0.5) * 6;
        final jy = (((hRaw >> 8) & 0xff) / 255.0 - 0.5) * 6;
        // Vary alpha so the field has subtle topography.
        final a = 0.04 + ((hRaw >> 16) & 0x3f) / 0x3f * 0.06;
        dotPaint.color = tokens.textMuted.withValues(alpha: a);
        canvas.drawCircle(Offset(gx + jx, gy + jy), 0.7, dotPaint);
      }
    }
  }

  void _paintGrid(Canvas canvas, double w, double h) {
    final g = Paint()
      ..color = tokens.chromeBorder.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    // Dashed crosshair centered on both axes.
    _drawDashedLine(canvas, Offset(w * 0.5, 16), Offset(w * 0.5, h - 16),
        g, dashLen: 3, gapLen: 5);
    _drawDashedLine(canvas, Offset(16, h * 0.5), Offset(w - 16, h * 0.5),
        g, dashLen: 3, gapLen: 5);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {required double dashLen, required double gapLen}) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final step = dashLen + gapLen;
    final n = (len / step).floor();
    final ux = dx / len;
    final uy = dy / len;
    for (int i = 0; i <= n; i++) {
      final s = i * step;
      final e = (s + dashLen).clamp(0.0, len);
      canvas.drawLine(
        Offset(a.dx + ux * s, a.dy + uy * s),
        Offset(a.dx + ux * e, a.dy + uy * e),
        paint,
      );
    }
  }

  // Corner glyphs for each quadrant; active corner is brighter.
  void _paintPictograms(Canvas canvas, double w, double h) {
    const inset = 20.0;
    const glyphSize = 22.0;
    final active = _LogosQuadrant.nearest(x, y);

    _drawFolderStack(canvas, Offset(inset + glyphSize / 2, inset + glyphSize / 2),
        glyphSize, active == _LogosQuadrant.moduleMap);
    _drawHubSpoke(canvas,
        Offset(w - inset - glyphSize / 2, inset + glyphSize / 2),
        glyphSize, active == _LogosQuadrant.repoCenters);
    _drawCluster(canvas,
        Offset(inset + glyphSize / 2, h - inset - glyphSize / 2),
        glyphSize, active == _LogosQuadrant.neighbors);
    _drawPulseArrow(canvas,
        Offset(w - inset - glyphSize / 2, h - inset - glyphSize / 2),
        glyphSize, active == _LogosQuadrant.toTouch);
  }

  Color _glyphColor(bool active) => active
      ? tokens.textNormal.withValues(alpha: 0.88)
      : tokens.textMuted.withValues(alpha: 0.38);

  /// Folder × Far — three nested squares (a tree collapsing inward).
  void _drawFolderStack(Canvas canvas, Offset c, double size, bool active) {
    final p = Paint()
      ..color = _glyphColor(active)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int i = 0; i < 3; i++) {
      final s = size * (1 - i * 0.28);
      final r = Rect.fromCenter(center: c, width: s, height: s);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        p,
      );
    }
  }

  /// History × Far — hub-and-spoke. Center node, 6 orbitals, soft lines.
  void _drawHubSpoke(Canvas canvas, Offset c, double size, bool active) {
    final col = _glyphColor(active);
    final line = Paint()
      ..color = col.withValues(alpha: col.a * 0.6)
      ..strokeWidth = 1;
    final dot = Paint()
      ..color = col
      ..style = PaintingStyle.fill;
    const n = 6;
    final r = size * 0.44;
    for (int i = 0; i < n; i++) {
      final a = (i / n) * 2 * math.pi;
      final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      canvas.drawLine(c, p, line);
      canvas.drawCircle(p, 1.4, dot);
    }
    canvas.drawCircle(c, 2.2, dot);
  }

  /// Folder × Near — 3×3 dot grid. Adjacency as matter.
  void _drawCluster(Canvas canvas, Offset c, double size, bool active) {
    final dot = Paint()
      ..color = _glyphColor(active)
      ..style = PaintingStyle.fill;
    final step = size * 0.32;
    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        canvas.drawCircle(
            c.translate(i * step, j * step), 1.5, dot);
      }
    }
  }

  /// History × Near — forward chevron wave. "What comes next."
  void _drawPulseArrow(Canvas canvas, Offset c, double size, bool active) {
    final col = _glyphColor(active);
    final p = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = size * 0.38;
    // Three stacked chevrons → right-leaning motion signature.
    for (int i = 0; i < 3; i++) {
      final x0 = c.dx - r + i * (r * 0.45);
      final path = Path()
        ..moveTo(x0, c.dy - r * 0.55)
        ..lineTo(x0 + r * 0.4, c.dy)
        ..lineTo(x0, c.dy + r * 0.55);
      final fade = p..color = col.withValues(alpha: col.a * (0.5 + i * 0.22));
      canvas.drawPath(path, fade);
    }
  }

  void _paintAxisHints(Canvas canvas, double w, double h) {
    final col = tokens.textFaint.withValues(alpha: 0.35);
    void word(String s, Offset c, {double rotate = 0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: col,
            fontSize: 8,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(c.dx, c.dy);
      if (rotate != 0) canvas.rotate(rotate);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    word('FOLDER', Offset(w * 0.25, h - 10));
    word('HISTORY', Offset(w * 0.75, h - 10));
    word('FAR', Offset(12, h * 0.25), rotate: -math.pi / 2);
    word('NEAR', Offset(12, h * 0.75), rotate: -math.pi / 2);
  }

  //
  // Relevance = 1 / (1 + k·d²) — a soft Lorentzian that gives nearby
  // nodes a strong pull while letting far ones fade gracefully.
  // Relevance is 1/(1 + k*d²), so nearby nodes dominate smoothly.
  // Top-3 labels are placed opposite the puck to avoid overlap.
  void _paintNodes(Canvas canvas, double w, double h) {
    final px = x * w;
    final py = y * h;
    final scored = <({_LogosNode n, double r, Offset pos})>[];
    for (final n in _kLogosNodes) {
      final nx = n.bx * w;
      final ny = n.by * h;
      final dx = (nx - px) / w;
      final dy = (ny - py) / h;
      final d2 = dx * dx + dy * dy;
      // k=12 keeps nearby nodes readable while suppressing distant ones.
      final rel = 1.0 / (1.0 + 12.0 * d2);
      scored.add((n: n, r: rel, pos: Offset(nx, ny)));
    }

    // Draw low-relevance first so top-3 composite cleanly on top.
    scored.sort((a, b) => a.r.compareTo(b.r));
    final dot = Paint()..style = PaintingStyle.fill;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final s in scored) {
      final r = 1.6 + 3.2 * s.r;
      final alpha = (0.18 + 0.78 * s.r).clamp(0.0, 1.0);
      final col = Color.lerp(
        tokens.textMuted.withValues(alpha: alpha * 0.55),
        tokens.accentBright.withValues(alpha: alpha),
        s.r,
      )!;
      dot.color = col;
      canvas.drawCircle(s.pos, r, dot);
      // Use an extra ring for high-relevance nodes.
      if (s.r > 0.35) {
        ring.color = tokens.accentBright
            .withValues(alpha: ((s.r - 0.35) / 0.65 * 0.55).clamp(0.0, 1.0));
        canvas.drawCircle(s.pos, r + 3, ring);
      }
    }

    // Label the top 3 nodes by relevance.
    final topN = scored.sublist(scored.length - 3);
    for (final s in topN) {
      final labelAlpha = ((s.r - 0.18) / 0.5).clamp(0.0, 1.0);
      if (labelAlpha <= 0) continue;
      _drawNodeLabel(canvas, s.n.path, s.pos, Offset(px, py),
          alpha: labelAlpha, w: w);
    }
  }

  void _drawNodeLabel(
    Canvas canvas,
    String path,
    Offset nodePos,
    Offset puckPos, {
    required double alpha,
    required double w,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: path,
        style: TextStyle(
          color: tokens.textStrong.withValues(alpha: alpha),
          fontSize: 10.5,
          height: 1,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Place labels away from the puck and keep them readable.
    final dx = nodePos.dx - puckPos.dx;
    final dy = nodePos.dy - puckPos.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux = len > 0.5 ? dx / len : 1.0;
    final uy = len > 0.5 ? dy / len : 0.0;
    const off = 9.0;
    double lx = nodePos.dx + ux * off;
    double ly = nodePos.dy + uy * off - tp.height / 2;
    // If label runs off the right edge, flip to the left of the node.
    if (lx + tp.width > w - 6) lx = nodePos.dx - off - tp.width;
    if (lx < 4) lx = 4;

    // Soft backer to keep the label readable against field glow.
    const pad = 3.0;
    final bgRect = Rect.fromLTWH(
        lx - pad, ly - pad, tp.width + pad * 2, tp.height + pad * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()
        ..color = tokens.surface0.withValues(alpha: alpha * 0.7),
    );
    tp.paint(canvas, Offset(lx, ly));
  }

  // Render trail as a thin polyline with age-based alpha.
  void _paintTrail(Canvas canvas, double w, double h) {
    if (trail.length < 2) return;
    final fadeMs = _LogosPadState._kTrailFade.inMilliseconds;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i < trail.length; i++) {
      final a = trail[i - 1];
      final b = trail[i];
      final ageMs = now.difference(b.at).inMilliseconds.toDouble();
      final t = (1.0 - ageMs / fadeMs).clamp(0.0, 1.0);
      if (t <= 0) continue;
      p.color = tokens.accentBright.withValues(alpha: 0.42 * t);
      canvas.drawLine(
        Offset(a.x * w, a.y * h),
        Offset(b.x * w, b.y * h),
        p,
      );
    }
  }

  // Draw puck rings, directional ticks, and center dot.
  void _paintPuck(Canvas canvas, double w, double h) {
    final px = x * w;
    final py = y * h;
    final c = Offset(px, py);
    final breathe = 0.5 + 0.5 * math.sin(ambient * 2 * math.pi);
    final scale = hovered ? 1.12 : 1.0;
    final ringOuter = (15.0 + 1.5 * breathe) * scale;
    final ringInner = 7.5 * scale;
    final coreR = (2.4 + 0.4 * breathe) * scale;

    final accent = tokens.accentBright;

    // Draw filled center and concentric outer strokes.
    canvas.drawCircle(
      c,
      ringInner - 0.5,
      Paint()..color = accent.withValues(alpha: 0.16),
    );

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    stroke
      ..strokeWidth = 1.0
      ..color = accent.withValues(alpha: 0.85);
    canvas.drawCircle(c, ringInner, stroke);

    stroke
      ..strokeWidth = 0.8
      ..color = accent.withValues(alpha: 0.45);
    canvas.drawCircle(c, ringOuter, stroke);

    // Cardinal ticks at N/E/S/W of the outer ring.
    final tickPaint = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    const tickLen = 3.5;
    canvas.drawLine(
        c.translate(0, -ringOuter), c.translate(0, -ringOuter - tickLen),
        tickPaint);
    canvas.drawLine(
        c.translate(0, ringOuter), c.translate(0, ringOuter + tickLen),
        tickPaint);
    canvas.drawLine(
        c.translate(-ringOuter, 0), c.translate(-ringOuter - tickLen, 0),
        tickPaint);
    canvas.drawLine(
        c.translate(ringOuter, 0), c.translate(ringOuter + tickLen, 0),
        tickPaint);

    // Center dot — small and dense.
    canvas.drawCircle(
      c,
      coreR,
      Paint()..color = tokens.textStrong,
    );
  }

  // Show a quadrant label only when the puck is meaningfully in a corner.
  // Opacity scales with distance-from-center so the neutral center state
  // stays label-free.
  void _paintQuadrantWhisper(Canvas canvas, double w, double h) {
    final dx = x - 0.5;
    final dy = y - 0.5;
    final distFromCenter = math.sqrt(dx * dx + dy * dy);
    if (distFromCenter < 0.08) return;
    // 0 at centre, 1 at corner (max dist = √0.5 ≈ 0.707).
    final commitment = ((distFromCenter - 0.08) / 0.35).clamp(0.0, 1.0);
    final q = _LogosQuadrant.nearest(x, y);
    final tp = TextPainter(
      text: TextSpan(
        text: q.whisper,
        style: TextStyle(
          color: tokens.textStrong.withValues(alpha: 0.65 * commitment),
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Place below the puck when puck is on upper half, above on lower.
    final px = x * w;
    final py = y * h;
    final offY = y < 0.5 ? 28.0 : -28.0 - tp.height;
    double tx = px - tp.width / 2;
    final ty = py + offY;
    if (tx < 10) tx = 10;
    if (tx + tp.width > w - 10) tx = w - 10 - tp.width;
    tp.paint(canvas, Offset(tx, ty));
  }

  @override
  bool shouldRepaint(_LogosPadPainter old) =>
      old.x != x ||
      old.y != y ||
      old.hovered != hovered ||
      old.ambient != ambient ||
      old.parallax != parallax ||
      !identical(old.trail, trail) ||
      old.trail.length != trail.length;
}

/// Quadrant labels for the pad; the label appears near the puck near each corner.
enum _LogosQuadrant {
  moduleMap,
  repoCenters,
  neighbors,
  toTouch;

  static _LogosQuadrant nearest(double x, double y) {
    if (y < 0.5) {
      return x < 0.5 ? _LogosQuadrant.moduleMap : _LogosQuadrant.repoCenters;
    }
    return x < 0.5 ? _LogosQuadrant.neighbors : _LogosQuadrant.toTouch;
  }

  String get whisper => switch (this) {
        _LogosQuadrant.moduleMap => 'module map',
        _LogosQuadrant.repoCenters => 'repo centers',
        _LogosQuadrant.neighbors => 'neighbors',
        _LogosQuadrant.toTouch => 'what to touch next',
      };
}

/// Static info plate to the right of the pad.
/// It's read-only and mirrors the active Logos configuration while the
/// puck interaction updates continuously.
class _LogosGrip extends StatelessWidget {
  const _LogosGrip();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: t.surface0.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: t.chromeBorder.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wordmark — small caps, wide tracking, stamped feel.
          Text(
            'LOGOS',
            style: TextStyle(
              color: t.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4.0,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'relevance engine',
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.7),
              fontSize: 9,
              letterSpacing: 1.6,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          _GripDivider(t: t),
          const SizedBox(height: 12),
          // Static stat rows use a two-column layout so values stay
          // stable and easy to compare.
          _GripStat(label: 'method', value: 'heat-kernel', t: t),
          _GripStat(label: 'graph', value: 'born-mix', t: t),
          _GripStat(label: 'axes', value: '4', t: t),
          const SizedBox(height: 10),
          _GripDivider(t: t),
          const SizedBox(height: 12),
          _GripStat(label: 't', value: '1.0', t: t, mono: true),
          _GripStat(label: 'k', value: '20', t: t, mono: true),
          _GripStat(label: 'range', value: '0.3–3.0', t: t, mono: true),
          const SizedBox(height: 14),
          _GripDivider(t: t),
          const SizedBox(height: 10),
          Text(
            'self-tuned\nno manual\nweights',
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.55),
              fontSize: 9.5,
              letterSpacing: 0.4,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _GripDivider extends StatelessWidget {
  final AppTokens t;
  const _GripDivider({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            t.chromeBorder.withValues(alpha: 0),
            t.chromeBorder.withValues(alpha: 0.35),
            t.chromeBorder.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _GripStat extends StatelessWidget {
  final String label;
  final String value;
  final AppTokens t;
  final bool mono;
  const _GripStat({
    required this.label,
    required this.value,
    required this.t,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    // Keep value rows two-line to avoid wrapping.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.55),
              fontSize: 8.5,
              letterSpacing: 1.4,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: t.textNormal,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: mono ? 'monospace' : null,
              letterSpacing: mono ? 0 : 0.2,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiMetaRow extends StatelessWidget {
  final String left;
  final String right;

  const _AiMetaRow({
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.82),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AiSupportLine extends StatelessWidget {
  final String text;
  final bool strong;

  const _AiSupportLine(this.text, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(
        color: strong ? t.textNormal : t.textMuted,
        fontSize: 10.5,
        fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
        fontFamily: 'JetBrainsMono',
      ),
    );
  }
}

class _GhostMiniButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const _GhostMiniButton({required this.label, required this.onTap});

  @override
  State<_GhostMiniButton> createState() => _GhostMiniButtonState();
}

class _GhostMiniButtonState extends State<_GhostMiniButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = ghostButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      enabled: widget.onTap != null,
      // Same-RGB-as-hover-border so the lerp animates only alpha and
      // doesn't pass through translucent black.
      baseBorderColor: t.inputFocusBorder.withValues(alpha: 0),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.onTap != null
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 80),
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            constraints: const BoxConstraints(minHeight: 24),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: chrome.background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: Transform.translate(
              offset: chrome.offset,
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.onTap != null ? t.textNormal : t.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TelemetrySwitcher extends StatelessWidget {
  final String focus;
  final CommandLatencyReport commandReport;
  final DiffRenderMetricsReport diffReport;
  final UiTimingReport uiReport;
  final ValueChanged<String> onFocusChanged;

  const _TelemetrySwitcher({
    required this.focus,
    required this.commandReport,
    required this.diffReport,
    required this.uiReport,
    required this.onFocusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = [
      (
        'command',
        'Command',
        '${commandReport.totalSamples} samples | ${commandReport.commandCount} commands'
      ),
      (
        'diff',
        'Diff Render',
        '${diffReport.totalSessions} sessions | ${((1 - diffReport.fallbackRate) * 100).toStringAsFixed(0)}% stability'
      ),
      (
        'ui',
        'UI Timing',
        '${uiReport.totalSamples} samples | ${uiReport.eventCount} events'
      ),
    ];

    return Container(
      height: 32,
      padding: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.chromeBorder.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in items)
            _TelemetrySwitcherItem(
              label: item.$2,
              meta: item.$3,
              active: focus == item.$1,
              onTap: () => onFocusChanged(item.$1),
            ),
        ],
      ),
    );
  }
}

class _TelemetrySwitcherItem extends StatefulWidget {
  final String label;
  final String meta;
  final bool active;
  final VoidCallback onTap;

  const _TelemetrySwitcherItem({
    required this.label,
    required this.meta,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TelemetrySwitcherItem> createState() => _TelemetrySwitcherItemState();
}

class _TelemetrySwitcherItemState extends State<_TelemetrySwitcherItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final activeColor = t.accentBright;
    final mutedColor = t.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(right: 20),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.active ? activeColor : activeColor.withValues(alpha: 0),
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.active ? activeColor : t.textNormal,
                      fontSize: 10,
                      fontWeight:
                          widget.active ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (widget.active) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 8,
                      color: activeColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.meta.split(' | ').first, // Shorthand metrics
                      style: TextStyle(
                        color: activeColor.withValues(alpha: 0.7),
                        fontSize: 8,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}


class _CommandDiagnosticsPanel extends StatelessWidget {
  final CommandLatencyReport report;
  final CommandTelemetrySnapshotData backendReport;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onClear;
  final String Function(String value) formatSampleTime;

  const _CommandDiagnosticsPanel({
    required this.report,
    required this.backendReport,
    required this.onRefresh,
    required this.onClear,
    required this.formatSampleTime,
  });

  @override
  Widget build(BuildContext context) {
    final summaries = report.summaries.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SettingsSubtitle('Command Diagnostics'),
        const SizedBox(height: 6),
        _DiagnosticsActionRow(
          onRefresh: onRefresh,
          clearLabel: 'Clear Samples',
          onClear: onClear,
          clearEnabled: report.totalSamples > 0,
        ),
        const SizedBox(height: 8),
        Text(
          '${report.totalSamples} samples | ${report.commandCount} unique commands',
          style: TextStyle(
            color: context.tokens.textMuted,
            fontSize: 10,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          Text(
            'No command timings captured yet. Run normal actions to populate diagnostics.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          Column(
            children: [
              for (final summary in summaries) ...[
                _TelemetrySummaryRow(
                  title: summary.command,
                  cells: [
                    _TelemetryCell(
                      label: 'p50',
                      value: '${summary.p50Ms.toStringAsFixed(1)}ms',
                    ),
                    _TelemetryCell(
                      label: 'Reliability',
                      value:
                          '${((summary.successCount / summary.count) * 100).round()}%',
                    ),
                    _TelemetryCell(
                      label: 'Range',
                      value:
                          '${summary.minMs.round()}-${summary.maxMs.round()}ms',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        if (report.recentSamples.isNotEmpty) ...[
          const SizedBox(height: 8),
          _RecentSamplesList(
            title: 'Recent Operations',
            items: report.recentSamples
                .map(
                  (sample) =>
                      '${formatSampleTime(sample.recordedAt)} | ${sample.command} | ${(sample.backendDurationMs ?? sample.roundTripMs).toStringAsFixed(2)} ms | ${sample.ok ? "ok" : sample.errorCode}',
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        const _SettingsSubtitle('Network Flow Telemetry'),
        const SizedBox(height: 8),
        Text(
          '${backendReport.sampleCount} samples | ${backendReport.summaries.length} scoped commands',
          style: TextStyle(
            color: context.tokens.textMuted,
            fontSize: 10,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 10),
        if (backendReport.summaries.isEmpty)
          Text(
            'No backend command samples captured yet. Run git and settings actions to populate this log.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          Column(
            children: [
              for (final summary in backendReport.summaries.take(10)) ...[
                _TelemetrySummaryRow(
                  title: '${summary.scope}:${summary.command}',
                  cells: [
                    _TelemetryCell(label: 'p50', value: '${summary.p50Ms}ms'),
                    _TelemetryCell(label: 'p95', value: '${summary.p95Ms}ms'),
                    _TelemetryCell(
                      label: 'Failures',
                      value: '${summary.failureCount}/${summary.sampleCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        if (backendReport.recentSamples.isNotEmpty) ...[
          const SizedBox(height: 8),
          _RecentSamplesList(
            title: 'Recent Backend Operations',
            items: backendReport.recentSamples.reversed
                .take(10)
                .map(
                  (sample) =>
                      '${formatSampleTime(sample.createdAt)} | ${sample.scope}:${sample.command} | ${sample.durationMs} ms | ${sample.ok ? "ok" : sample.errorCode}',
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _DiffDiagnosticsPanel extends StatelessWidget {
  final DiffRenderMetricsReport report;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onClear;
  final String Function(String value) formatSampleTime;

  const _DiffDiagnosticsPanel({
    required this.report,
    required this.onRefresh,
    required this.onClear,
    required this.formatSampleTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        _DiagnosticsActionRow(
          onRefresh: onRefresh,
          clearLabel: 'Clear Metrics',
          onClear: onClear,
          clearEnabled: report.totalSessions > 0,
        ),
        const SizedBox(height: 8),
        Text(
          '${report.totalSessions} sessions | jank ${(report.jankyFrameRate * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: context.tokens.textMuted,
            fontSize: 10,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 12),
        if (report.modeSummaries.isEmpty)
          Text(
            'No diff render sessions captured yet. Open and scroll file diffs to populate this panel.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          Column(
            children: [
              for (final summary in report.modeSummaries) ...[
                _TelemetrySummaryRow(
                  title: 'Renderer: ${summary.rendererMode}',
                  cells: [
                    _TelemetryCell(
                      label: 'First Paint',
                      value: '${summary.firstPaintP50Ms.toStringAsFixed(0)}ms',
                    ),
                    _TelemetryCell(
                      label: 'Frame p95',
                      value: '${summary.frameTimeP95Ms.toStringAsFixed(1)}ms',
                    ),
                    _TelemetryCell(
                      label: 'Raster p95',
                      value: '${summary.rasterTimeP95Ms.toStringAsFixed(1)}ms',
                    ),
                    _TelemetryCell(
                      label: 'Jank',
                      value:
                          '${(summary.jankyFrameRate * 100).toStringAsFixed(0)}%',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        if (report.recentSamples.isNotEmpty) ...[
          const SizedBox(height: 8),
          _RecentSamplesList(
            title: 'Recent Diff Sessions',
            items: report.recentSamples
                .map(
                  (sample) =>
                      '${formatSampleTime(sample.recordedAt)} | ${sample.rendererMode}:${sample.path} | frame ${sample.frameTimeP95Ms.toStringAsFixed(1)}ms | jank ${sample.frameCount == 0 ? "0" : ((sample.jankyFrameCount / sample.frameCount) * 100).toStringAsFixed(0)}%',
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _UiDiagnosticsPanel extends StatelessWidget {
  final UiTimingReport report;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onClear;
  final String Function(String value) formatSampleTime;

  const _UiDiagnosticsPanel({
    required this.report,
    required this.onRefresh,
    required this.onClear,
    required this.formatSampleTime,
  });

  @override
  Widget build(BuildContext context) {
    final summaries = report.summaries.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        _DiagnosticsActionRow(
          onRefresh: onRefresh,
          clearLabel: 'Clear Timings',
          onClear: onClear,
          clearEnabled: report.totalSamples > 0,
        ),
        const SizedBox(height: 8),
        Text(
          '${report.totalSamples} samples | ${report.eventCount} instrumented events',
          style: TextStyle(
            color: context.tokens.textMuted,
            fontSize: 10,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          Text(
            'No UI timing sessions captured yet. Open panels and navigate routes to populate this panel.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          Column(
            children: [
              for (final summary in summaries) ...[
                _TelemetrySummaryRow(
                  title: '${summary.phase}: ${summary.event}',
                  cells: [
                    _TelemetryCell(
                      label: 'p50',
                      value: '${summary.p50Ms.toStringAsFixed(1)}ms',
                    ),
                    _TelemetryCell(
                      label: 'Failures',
                      value: '${summary.failureCount}',
                    ),
                    _TelemetryCell(
                      label: 'Range',
                      value:
                          '${summary.minMs.round()}-${summary.maxMs.round()}ms',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        if (report.recentSamples.isNotEmpty) ...[
          const SizedBox(height: 8),
          _RecentSamplesList(
            title: 'Recent UI Timings',
            items: report.recentSamples
                .map(
                  (sample) =>
                      '${formatSampleTime(sample.recordedAt)} | ${sample.phase}:${sample.event} | ${sample.durationMs.toStringAsFixed(2)} ms | ${sample.ok ? "ok" : sample.errorCode}',
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _DiagnosticsActionRow extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final String clearLabel;
  final Future<void> Function() onClear;
  final bool clearEnabled;

  const _DiagnosticsActionRow({
    required this.onRefresh,
    required this.clearLabel,
    required this.onClear,
    required this.clearEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        _DeckButton(
          label: 'RECALIBRATE',
          icon: Icons.refresh_outlined,
          onTap: onRefresh,
        ),
        const SizedBox(width: 8),
        _DeckButton(
          label: clearLabel.toUpperCase(),
          icon: Icons.cleaning_services_outlined,
          enabled: clearEnabled,
          onTap: onClear,
          isDestructive: true,
        ),
      ],
    );
  }
}

class _DeckButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool isDestructive;

  const _DeckButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.isDestructive = false,
  });

  @override
  State<_DeckButton> createState() => _DeckButtonState();
}

class _DeckButtonState extends State<_DeckButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = widget.isDestructive ? t.stateDeleted : t.accentBright;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered && widget.enabled
                  ? color.withValues(alpha: 0.12)
                  : t.rowBg.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _hovered && widget.enabled
                    ? color.withValues(alpha: 0.4)
                    : t.chromeBorder.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 14,
                  color: _hovered && widget.enabled ? color : t.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _hovered && widget.enabled ? t.textStrong : t.textNormal,
                    fontSize: 9,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TelemetryCell {
  final String label;
  final String value;

  const _TelemetryCell({required this.label, required this.value});
}

class _TelemetrySummaryRow extends StatelessWidget {
  final String title;
  final List<_TelemetryCell> cells;

  const _TelemetrySummaryRow({required this.title, required this.cells});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: t.rowBg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
        border: Border(
          left: BorderSide(color: t.accentBright.withValues(alpha: 0.4), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              if (compact) {
                return Column(
                  children: [
                    for (var i = 0; i < cells.length; i++) ...[
                      _TelemetryCellView(cell: cells[i]),
                      if (i < cells.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    Expanded(child: _TelemetryCellView(cell: cells[i])),
                    if (i < cells.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TelemetryCellView extends StatelessWidget {
  final _TelemetryCell cell;

  const _TelemetryCellView({required this.cell});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cell.label,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cell.value,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSamplesList extends StatelessWidget {
  final String title;
  final List<String> items;

  const _RecentSamplesList({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: t.accentBright.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: t.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: t.chromeBorder.withValues(alpha: 0.1), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                Text(
                  items[i],
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                    height: 1.5,
                  ),
                ),
                if (i < items.length - 1)
                  Container(
                    height: 1,
                    width: 24,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: t.chromeBorder.withValues(alpha: 0.05),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom toggle for "Reduce motion."
/// Not a checkbox — the element *itself* demonstrates its effect. The
/// dots show a traveling-Gaussian pulse whose forward velocity is
/// modulated by a single envelope:
///   * [_speed] is a 0..1 envelope. At 1 the wave advances at the base
///     frequency (≈ 0.556 Hz); at 0 it sits perfectly still. Toggling
///     the pref animates [_speed] across 520ms with easeOutCubic in
///     either direction.
///   * A custom [_phaseTicker] advances the dot-strip's phase by
///     `dt * baseHz * speed` each frame and stops itself once the
///     envelope has settled to zero (no point burning frames on a
///     frozen wave).
/// Going INTO reduced: the wave decelerates and the bump freezes
/// wherever it lands — never a teleport, never a disappearing dot.
/// Going OUT: the bump accelerates back up from its frozen position.
/// The frequency badge reads `speed * baseHz` so the Hz number lerps
/// honestly to 0.00 as the wave actually slows, not snapped at toggle
/// time.
/// Keyboard: Space/Enter toggle while focused. Focus draws an accent
/// ring. No tap-down scale on this control by design — see the build
/// method.
/// Interactive sort-guide picker with a live preview.
/// Six demo tiles with stable identity (id, cluster color, letter,
/// impact weight) animate into each ordering without committing.
/// Hover/focus previews an option; click commits it.
class _ChangeSortGuide extends StatefulWidget {
  final FileSortGuide value;
  final bool inverted;
  final ValueChanged<FileSortGuide> onChanged;
  final ValueChanged<bool> onInvertedChanged;

  const _ChangeSortGuide({
    required this.value,
    required this.inverted,
    required this.onChanged,
    required this.onInvertedChanged,
  });

  @override
  State<_ChangeSortGuide> createState() => _ChangeSortGuideState();
}

/// One demo tile in the preview.
/// Stable identity across re-sorts so AnimatedPositioned animates the same
/// tile from old position to new position (no spawn/fade swap).
class _SortDemoTile {
  final int id;
  final int cluster;
  final String letter;
  // Normalized 0..1 weight used for the bar's height in "impact" mode.
  // Chosen so the three modes produce visibly distinct orderings.
  final double weight;
  // Universal rule demo: a conflict tile renders amber and is always
  // pulled to position 0 regardless of sort mode. Its letter is chosen
  // so the override is visible in alphabetical too (not just colored).
  final bool conflict;
  // Included-in-current-commit flag. Excluded tiles render at reduced
  // opacity and — in "near related" only — drift to the bottom of their
  // cluster. Alphabetical and impact ignore it, which the demo honestly
  // reflects: excluded tiles stay where their letter/weight put them.
  final bool included;
  const _SortDemoTile({
    required this.id,
    required this.cluster,
    required this.letter,
    required this.weight,
    this.conflict = false,
    this.included = true,
  });
}

class _ChangeSortGuideState extends State<_ChangeSortGuide>
    with TickerProviderStateMixin {
  // Seven tiles: one conflicted, two excluded, three clusters.
  //   * Tile 6 is the conflict — labelled '!!' rather than a regular
  //     letter so it reads as a flag, not as a file that happens to
  //     sort weirdly. Its amber color + '!!' glyph together make the
  //     "this is a conflict, it lives at the top in every mode" signal
  //     unmistakable without competing with the alphabetical ordering
  //     of the real file tiles.
  //   * Tile 0 and tile 3 are excluded, one in each of the first two
  //     clusters. In related mode they drift to the bottom of their
  //     cluster; in the other modes they stay where their letter or
  //     weight places them, which is honest — those modes ignore
  //     inclusion.
  static const List<_SortDemoTile> _tiles = [
    _SortDemoTile(
        id: 0, cluster: 0, letter: 'F', weight: 0.55, included: false),
    _SortDemoTile(id: 1, cluster: 0, letter: 'B', weight: 0.90),
    _SortDemoTile(id: 2, cluster: 1, letter: 'D', weight: 0.30),
    _SortDemoTile(
        id: 3, cluster: 1, letter: 'A', weight: 0.70, included: false),
    _SortDemoTile(id: 4, cluster: 2, letter: 'E', weight: 1.00),
    _SortDemoTile(id: 5, cluster: 2, letter: 'C', weight: 0.20),
    _SortDemoTile(
        id: 6, cluster: -1, letter: '!!', weight: 0.50, conflict: true),
  ];

  // Hover-preview and tap-press state are exposed as ValueNotifiers so
  // that changing them does NOT trigger a rebuild of this widget (or
  // the chip row that contains the gesture detectors). Only the
  // reactive subtrees — badge, stage, pill, label visuals — rebuild
  // via ValueListenableBuilder. This keeps the MouseRegion/
  // GestureDetector element tree stable across hover events, which is
  // what a first-click needs: Flutter's gesture arena must see a
  // pointer-down arrive at the same recognizer it was tracking, and a
  // mid-pointer-down setState on an ancestor was invalidating that
  // recognizer before onTap could fire.
  final ValueNotifier<FileSortGuide?> _previewing = ValueNotifier(null);
  final ValueNotifier<int?> _pressedIndex = ValueNotifier(null);

  @override
  void dispose() {
    _previewing.dispose();
    _pressedIndex.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChangeSortGuide old) {
    super.didUpdateWidget(old);
    // If the committed value changed externally (or the user tapped to
    // commit the currently-previewed option), clear any stale preview.
    if (_previewing.value == widget.value) {
      _previewing.value = null;
    }
  }

  FileSortGuide _effectiveFor(FileSortGuide? preview) =>
      preview ?? widget.value;

  /// One-liner copy per (mode, inverted) pair. Reads as that variant's
  /// *personality* — what it values, what it rewards — not the mechanic.
  /// Inverted variants share structure only where sharing is natural
  /// (A → Z / Z → A; heaviest / lightest). Where the mirror would be
  /// forced, each side is phrased on its own terms.
  String _descriptionFor(FileSortGuide guide, {required bool inverted}) {
    switch (guide) {
      case FileSortGuide.relatedProximity:
        return inverted
            ? 'Isolated changes come first. '
                'Tightly-coupled clusters sink to the bottom.'
            : 'Files that change together cluster together. '
                'The concern comes first; context follows.';
      case FileSortGuide.alphabetical:
        return inverted
            ? 'Plain Z → A by path. '
                'Case-insensitive, numbers ordered naturally.'
            : 'Plain A → Z by path. '
                'Case-insensitive, numbers ordered naturally.';
      case FileSortGuide.impact:
        return inverted
            ? 'Lightest changes surface first. '
                'Quick wins on top; the heavy lifts wait.'
            : 'Heaviest changes surface first. '
                'Churn is weighted; binaries and new files get boosted.';
    }
  }

  /// Return tile ids in the order they should appear for [guide].
  /// Runs the mode's own sort on non-conflict tiles, applies invert if
  /// requested (by reversing the non-conflict list), then prepends any
  /// conflict tiles at position 0. Mirrors the production rule in
  /// `clusterFiles` exactly so the demo never lies about what the real
  /// list will look like.
  List<int> _orderFor(FileSortGuide guide, {bool inverted = false}) {
    final conflicts = <int>[];
    final nonConflicts = <int>[];
    for (final t in _tiles) {
      (t.conflict ? conflicts : nonConflicts).add(t.id);
    }
    switch (guide) {
      case FileSortGuide.relatedProximity:
        nonConflicts.sort((a, b) {
          final ta = _tiles[a];
          final tb = _tiles[b];
          if (ta.cluster != tb.cluster) return ta.cluster.compareTo(tb.cluster);
          if (ta.included != tb.included) return ta.included ? -1 : 1;
          return a.compareTo(b);
        });
      case FileSortGuide.alphabetical:
        nonConflicts.sort(
          (a, b) => _tiles[a].letter.compareTo(_tiles[b].letter),
        );
      case FileSortGuide.impact:
        nonConflicts.sort((a, b) {
          final w = _tiles[b].weight.compareTo(_tiles[a].weight);
          if (w != 0) return w;
          return a.compareTo(b);
        });
    }
    final body = inverted ? nonConflicts.reversed.toList() : nonConflicts;
    return <int>[...conflicts, ...body];
  }

  Color _clusterColor(AppTokens t, int cluster) {
    switch (cluster % 3) {
      case 0:
        return t.hyperChromatic1;
      case 1:
        return t.hyperChromatic2;
      default:
        return t.accentBright;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Change sort guide',
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Right-anchored live readout. One Container, one text; no
              // AnimatedSwitcher cross-fade, so the right edge stays
              // pinned across label-width changes.
              ValueListenableBuilder<FileSortGuide?>(
                valueListenable: _previewing,
                builder: (context, preview, _) => _SortGuideBadge(
                  guide: _effectiveFor(preview),
                  previewing: preview != null,
                  inverted: widget.inverted,
                  tokens: t,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Mode-specific one-liner. Tracks the effective (preview) mode
          // so hovering an option gives you its own description to read
          // while the stage rehearses it. AnimatedDefaultTextStyle keeps
          // the color + metrics stable across swaps — only the text
          // content changes, in place, no layout jitter.
          ValueListenableBuilder<FileSortGuide?>(
            valueListenable: _previewing,
            builder: (context, preview, _) {
              return AnimatedDefaultTextStyle(
                duration: context.motion(const Duration(milliseconds: 140)),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
                child: ThemeMorphText(_descriptionFor(
                  _effectiveFor(preview),
                  inverted: widget.inverted,
                )),
              );
            },
          ),
          const SizedBox(height: 12),
          // The preview itself is the interaction surface: tapping any tile
          // flips the sort-order inversion.
          // The same AnimatedPositioned flow drives both preview and commit
          // so the motion stays consistent.
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onInvertedChanged(!widget.inverted),
              child: ValueListenableBuilder<FileSortGuide?>(
                valueListenable: _previewing,
                builder: (context, preview, _) {
                  final order = _orderFor(
                    _effectiveFor(preview),
                    inverted: widget.inverted,
                  );
                  final positions = <int, int>{};
                  for (var i = 0; i < order.length; i++) {
                    positions[order[i]] = i;
                  }
                  return _SortDemoStage(
                    tiles: _tiles,
                    positions: positions,
                    clusterColor: (cluster) => _clusterColor(t, cluster),
                    inverted: widget.inverted,
                    tokens: t,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          // The Row of labels is a STABLE subtree: its GestureDetector
          // + MouseRegion elements never rebuild on hover. Reactive
          // visuals (pill position + each label's color) live in
          // ValueListenableBuilders, so hover fires don't disrupt the
          // gesture arena mid-click.
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 6.0;
              final options = FileSortGuide.values;
              final count = options.length;
              final chipWidth =
                  (constraints.maxWidth - gap * (count - 1)) / count;

              return SizedBox(
                height: 34,
                child: Stack(
                  children: [
                    // Reactive sliding pill — rebuilds only on preview change.
                    ValueListenableBuilder<FileSortGuide?>(
                      valueListenable: _previewing,
                      builder: (context, preview, _) {
                        final committedIdx = options.indexOf(widget.value);
                        final hoverIdx = preview == null
                            ? null
                            : options.indexOf(preview);
                        final targetIdx = hoverIdx ?? committedIdx;
                        final isPreview = hoverIdx != null;
                        return AnimatedPositioned(
                          duration: context
                              .motion(const Duration(milliseconds: 220)),
                          curve: Curves.easeOutCubic,
                          left: targetIdx * (chipWidth + gap),
                          top: 0,
                          bottom: 0,
                          width: chipWidth,
                          child: AnimatedContainer(
                            duration: context
                                .motion(const Duration(milliseconds: 180)),
                            decoration: BoxDecoration(
                              color: isPreview
                                  ? t.accentBright.withValues(alpha: 0.05)
                                  : t.accentBright.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isPreview
                                    ? t.accentBright.withValues(alpha: 0.45)
                                    : t.accentBright,
                                width: isPreview ? 1 : 1.2,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Stable labels — gesture elements never rebuild on
                    // hover/press; only the inner visual layers do.
                    Row(
                      children: [
                        for (var i = 0; i < count; i++) ...[
                          if (i > 0) const SizedBox(width: gap),
                          Expanded(
                            child: _SortOptionLabel(
                              guide: options[i],
                              index: i,
                              committed: widget.value == options[i],
                              previewing: _previewing,
                              pressedIndex: _pressedIndex,
                              onHoverChanged: (hovered) {
                                if (hovered &&
                                    options[i] != widget.value) {
                                  _previewing.value = options[i];
                                } else if (!hovered &&
                                    _previewing.value == options[i]) {
                                  _previewing.value = null;
                                }
                              },
                              onPressedChanged: (pressed) {
                                _pressedIndex.value = pressed ? i : null;
                              },
                              onTap: () {
                                _previewing.value = null;
                                widget.onChanged(options[i]);
                              },
                              tokens: t,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Live readout text — echoes the state badge on Reduce Motion. While the
/// user is hovering an option (previewing) the label dims so they can
/// tell the difference from a committed selection.
class _SortGuideBadge extends StatelessWidget {
  final FileSortGuide guide;
  final bool previewing;
  final bool inverted;
  final AppTokens tokens;
  const _SortGuideBadge({
    super.key,
    required this.guide,
    required this.previewing,
    required this.inverted,
    required this.tokens,
  });

  String get _label {
    switch (guide) {
      case FileSortGuide.relatedProximity:
        return 'near related';
      case FileSortGuide.alphabetical:
        return 'alphabetical';
      case FileSortGuide.impact:
        return 'by impact';
    }
  }

  String _fullLabel() {
    final base = _label;
    // Suffix order: peek first (ephemeral hover state), then inverted
    // (persistent flip state) — so "alphabetical · flipped · peek"
    // reads left-to-right as mode → persistent modifier → live state.
    final parts = <String>[base];
    if (inverted) parts.add('flipped');
    if (previewing) parts.add('peek');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: context.motion(const Duration(milliseconds: 140)),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: previewing
            ? tokens.textMuted.withValues(alpha: 0.10)
            : tokens.accentBright.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AnimatedDefaultTextStyle(
        duration: context.motion(const Duration(milliseconds: 140)),
        curve: Curves.easeOutCubic,
        style: TextStyle(
          color: previewing ? tokens.textMuted : tokens.accentBright,
          fontSize: 9,
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
        child: ThemeMorphText(_fullLabel()),
      ),
    );
  }
}

/// Horizontal strip of demo tiles that animate to new x-positions when the
/// effective sort order changes.
/// Each tile's ValueKey is its id, so Flutter keeps the same widget
/// instance per tile and AnimatedPositioned interpolates its new left offset.
class _SortDemoStage extends StatelessWidget {
  final List<_SortDemoTile> tiles;
  final Map<int, int> positions;
  final Color Function(int cluster) clusterColor;
  final AppTokens tokens;

  // Layout budget — chosen so the tallest possible tile body fits
  // within the stage with visible breathing room:
  //   letter (fontSize 9, height:1.0)  ≈  9 px
  //   gap                                2 px
  //   bar max                           22 px
  //   total content                     33 px   ≤ tileHeight 40 ≤ stage 50
  static const double _minTileWidth = 22;
  static const double _maxTileWidth = 34;
  static const double _tileGap = 6;
  static const double _tileHeight = 40;
  static const double _stageHeight = 50;

  final bool inverted;

  const _SortDemoStage({
    required this.tiles,
    required this.positions,
    required this.clusterColor,
    required this.inverted,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = tiles.length;
        // Pick a tile width that fits the available space without
        // clipping. Clamp into the aesthetic range.
        final slotsByFit =
            (constraints.maxWidth - _tileGap * (count - 1)) / count;
        final tileWidth = slotsByFit.clamp(_minTileWidth, _maxTileWidth);
        final slotWidth = tileWidth + _tileGap;
        final stageWidth = slotWidth * count - _tileGap;

        return Center(
          child: SizedBox(
            width: stageWidth,
            height: _stageHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Baseline — a subtle rule the bars grow from. Gives
                // "by impact" a visible reference edge.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Container(
                    height: 1,
                    color: tokens.chromeBorder.withValues(alpha: 0.15),
                  ),
                ),
                for (final tile in tiles)
                  AnimatedPositioned(
                    key: ValueKey(tile.id),
                    duration:
                        context.motion(const Duration(milliseconds: 320)),
                    curve: Curves.easeOutCubic,
                    left: (positions[tile.id] ?? 0) * slotWidth,
                    bottom: 6,
                    width: tileWidth,
                    height: _tileHeight,
                    child: _SortDemoTileBody(
                      tile: tile,
                      // Conflict tiles render in the theme's conflict
                      // color (amber/warn) so they read as distinct from
                      // cluster members even at a glance. Non-conflict
                      // tiles use their cluster color as before.
                      color: tile.conflict
                          ? tokens.stateConflicted
                          : clusterColor(tile.cluster),
                      tokens: tokens,
                    ),
                  ),
                // Subtle ↕ glyph in the corner of the stage — it's the
                // only hint that the stage is tappable to invert, AND
                // the current state indicator. Rotates a half-turn on
                // state change so the flip gesture and the glyph's
                // flip are the same animation.
                Positioned(
                  top: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedRotation(
                      turns: inverted ? 0.5 : 0,
                      duration:
                          context.motion(const Duration(milliseconds: 260)),
                      curve: Curves.easeOutCubic,
                      child: Text(
                        '⇅',
                        style: TextStyle(
                          color: tokens.textMuted.withValues(
                              alpha: inverted ? 0.9 : 0.35),
                          fontSize: 11,
                          height: 1.0,
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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

class _SortDemoTileBody extends StatelessWidget {
  final _SortDemoTile tile;
  final Color color;
  final AppTokens tokens;
  const _SortDemoTileBody({
    required this.tile,
    required this.color,
    required this.tokens,
  });

  // Bar height range — tight clamp so the tallest bar fits within the
  // tile height budget with the letter above it. Gives "by impact" a
  // visibly left-heavy silhouette (0.20 → 10px, 1.00 → 22px) without
  // letting any tile bleed past its slot.
  static const double _barMin = 10;
  static const double _barMax = 22;

  @override
  Widget build(BuildContext context) {
    final barHeight = (_barMin + tile.weight * (_barMax - _barMin))
        .clamp(_barMin, _barMax);
    // Excluded tiles ghost down to 45% so the "in the commit" / "not in
    // the commit" split is legible at a glance. Conflict tiles never
    // dim — they must scream for attention regardless of inclusion.
    final double opacity = (!tile.included && !tile.conflict) ? 0.45 : 1.0;
    // Conflict tiles use a slightly stronger fill so the amber carries,
    // even at small sizes.
    final double fillAlpha = tile.conflict ? 0.35 : 0.25;
    return AnimatedOpacity(
      duration: context.motion(const Duration(milliseconds: 200)),
      curve: Curves.easeOutCubic,
      opacity: opacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Letter cap — `height: 1.0` kills the font's default line-leading
          // so the text occupies exactly its font-size (9 px) and the
          // overall tile content fits the enclosing slot precisely.
          Text(
            tile.letter,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontSize: 9,
              height: 1.0,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 320)),
            curve: Curves.easeOutCubic,
            height: barHeight,
            decoration: BoxDecoration(
              color: color.withValues(alpha: fillAlpha),
              border: Border.all(
                color: color.withValues(alpha: 0.75),
                width: tile.conflict ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

/// A transparent label that sits on top of the shared sliding selection
/// pill. Hovering writes to [previewing]; tap commits the choice.
/// Crucial architectural detail: the `MouseRegion` + `GestureDetector`
/// form a **stable** element tree — neither ever rebuilds on hover or
/// press. Hover/press state travels through [ValueNotifier]s, and only
/// the inner visual subtrees (scale, color) rebuild via
/// `ValueListenableBuilder`. This guarantees Flutter's gesture arena
/// sees the same recognizer across the pointer-down → pointer-up
/// lifecycle; the "first click gets eaten" bug was caused by an
/// ancestor `setState` on `onEnter` swapping those recognizers before
/// the tap could resolve.
/// `HitTestBehavior.opaque` on the GestureDetector makes the full chip
/// bounds tappable, not just the text glyphs — so a click on whitespace
/// near the label still commits.
class _SortOptionLabel extends StatelessWidget {
  final FileSortGuide guide;
  final int index;
  final bool committed;
  final ValueListenable<FileSortGuide?> previewing;
  final ValueListenable<int?> pressedIndex;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback onTap;
  final AppTokens tokens;
  const _SortOptionLabel({
    required this.guide,
    required this.index,
    required this.committed,
    required this.previewing,
    required this.pressedIndex,
    required this.onHoverChanged,
    required this.onPressedChanged,
    required this.onTap,
    required this.tokens,
  });

  String get _label {
    switch (guide) {
      case FileSortGuide.relatedProximity:
        return 'near related';
      case FileSortGuide.alphabetical:
        return 'alphabetical';
      case FileSortGuide.impact:
        return 'by impact';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        // Opaque so the full chip rectangle is tappable, not just the
        // text glyphs. Without this, clicks on label whitespace fall
        // through to the sliding pill behind, which has no gesture
        // handler — they'd miss entirely.
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPressedChanged(true),
        onTapUp: (_) => onPressedChanged(false),
        onTapCancel: () => onPressedChanged(false),
        onTap: onTap,
        // Scale reacts to the pressed notifier; the gesture shell above
        // is UNAFFECTED by press state.
        child: ValueListenableBuilder<int?>(
          valueListenable: pressedIndex,
          builder: (context, pressed, inner) => AnimatedScale(
            scale: pressed == index ? 0.97 : 1.0,
            duration: context.motion(const Duration(milliseconds: 110)),
            curve: Curves.easeOutCubic,
            child: inner,
          ),
          // Text color reacts to preview + committed state, also isolated.
          child: ValueListenableBuilder<FileSortGuide?>(
            valueListenable: previewing,
            builder: (context, preview, _) {
              final selected = committed || preview == guide;
              return Container(
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration:
                      context.motion(const Duration(milliseconds: 160)),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: selected
                        ? tokens.accentBright
                        : tokens.textNormal.withValues(alpha: 0.85),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  child: Text(_label),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReduceMotionToggle extends StatefulWidget {
  /// Current motion rate in [0, 2]. 0 = no motion (matches the legacy
  /// reduce-motion=true behavior), 1 = authored speed, 2 = double-time.
  final double value;
  final ValueChanged<double> onChanged;

  const _ReduceMotionToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ReduceMotionToggle> createState() => _ReduceMotionToggleState();
}

class _ReduceMotionToggleState extends State<_ReduceMotionToggle>
    with TickerProviderStateMixin {
  // 1 cycle / 1.8 s ≈ 0.556 Hz at rate 1.0. The live Hz readout and the
  // pulse-wave phase advance both scale from this base by the current
  // rate, so rate=2.0 shows ~1.11 Hz and the wave literally animates 2×
  // as fast. The number on screen and the speed of the wave are the
  // same quantity rendered in two different modalities.
  static const double _kWaveHzBase = 1000.0 / 1800.0;
  static const double _kMaxRate = 2.0;
  static const Duration _kEnvelopeDuration = Duration(milliseconds: 280);

  // The wave IS the slider. Width matches the original 56px layout
  // exactly so the 5 dots look identical to before the control became
  // a scrub target. Drag precision is ~28px per unit rate — arrow
  // keys (±0.1) are available for finer tuning.
  static const double _kWaveWidth = 56.0;
  static const double _kWaveHeight = 18.0;

  // Live rate for the pulse animation. Eases toward widget.value on every
  // external change, so a programmatic set from elsewhere (or a toggle
  // tap) produces a smooth ramp instead of a snap. During an active
  // horizontal drag the rate is updated immediately without easing —
  // the wave tracks the finger in real time.
  late final AnimationController _envelope;
  double _rateFrom = 1.0;
  double _rateTo = 1.0;
  double get _liveRate {
    final t = _envelope.value;
    return _rateFrom + (_rateTo - _rateFrom) * t;
  }

  late final Ticker _phaseTicker;
  final ValueNotifier<double> _phase = ValueNotifier(0.0);
  Duration _lastTick = Duration.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'ReduceMotionToggle');

  // Remembers the last non-zero rate so tap-to-toggle (the muscle-memory
  // gesture from the old boolean toggle) can restore whatever speed the
  // user had dialed in before going to zero.
  double _lastPositiveRate = 1.0;

  // Row-wide hover — the whole button is clickable (tap = toggle), so
  // the whole row is the hover target. Matches the original bool toggle.
  bool _rowHovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _rateFrom = widget.value;
    _rateTo = widget.value;
    if (widget.value > 0) _lastPositiveRate = widget.value;
    _envelope = AnimationController(
      vsync: this,
      duration: _kEnvelopeDuration,
      value: 1.0, // start settled at the initial rate
    );
    _phase.value =
        context.read<PreferencesState>().reduceMotionPhase.clamp(0.0, 1.0);
    _phaseTicker = createTicker(_onPhaseTick);
    if (widget.value > 0.0001) _phaseTicker.start();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onPhaseTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final rate = _liveRate;
    // When the rate collapses to ~0 AND the envelope has settled, the
    // wave has come to rest. Stop consuming frames AND persist the
    // frozen phase so the next session resumes the bump from here.
    if (rate <= 0.0001 && !_envelope.isAnimating) {
      _phaseTicker.stop();
      _lastTick = Duration.zero;
      context.read<PreferencesState>().setReduceMotionPhase(_phase.value);
      return;
    }
    if (rate > 0) {
      _phase.value = (_phase.value + dt * _kWaveHzBase * rate) % 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _ReduceMotionToggle old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (widget.value > 0.0001) _lastPositiveRate = widget.value;
    // Ease from current live rate to the new target. During an active
    // drag the setState loop overwrites these each frame; the tween
    // duration is effectively inert because the value updates faster
    // than the envelope completes.
    _rateFrom = _liveRate;
    _rateTo = widget.value;
    _envelope.forward(from: 0);
    if (!_phaseTicker.isActive && widget.value > 0.0001) {
      _lastTick = Duration.zero;
      _phaseTicker.start();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _phaseTicker.dispose();
    _envelope.dispose();
    _phase.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  /// Tap toggles between OFF (rate=0) and the last non-zero rate. This
  /// preserves the muscle-memory of the old boolean control — users who
  /// just want "motion off" keep their one-tap workflow; users who want
  /// to tune pull horizontally.
  void _onTap() {
    final next = widget.value > 0.0001 ? 0.0 : _lastPositiveRate;
    widget.onChanged(next);
    _focusNode.requestFocus();
  }

  /// Horizontal drag across the wave maps cursor X to rate. 0 at the
  /// left edge, [_kMaxRate] at the right. Updates fire live so the wave
  /// speeds up / slows down in step with the finger — the speed of the
  /// wave IS the feedback, no overlay required.
  void _onDragStart(DragStartDetails d) {
    _applyDragRate(d.localPosition.dx);
    _focusNode.requestFocus();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _applyDragRate(d.localPosition.dx);
  }

  void _applyDragRate(double dx) {
    final frac = (dx / _kWaveWidth).clamp(0.0, 1.0);
    final rate = (frac * _kMaxRate).clamp(0.0, _kMaxRate);
    if ((widget.value - rate).abs() < 0.005) return;
    widget.onChanged(rate);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _onTap();
      return KeyEventResult.handled;
    }
    // Arrow keys nudge by 0.1 in each direction — keyboard parity with
    // the horizontal drag gesture, for accessibility.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      widget.onChanged((widget.value - 0.1).clamp(0.0, _kMaxRate));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      widget.onChanged((widget.value + 0.1).clamp(0.0, _kMaxRate));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _subtitleForRate(double r) =>
      r <= 0.0001 ? 'Still… like ice?' : 'Flow like water.';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rate = widget.value;
    final off = rate <= 0.0001;

    // Border/fill mirror the original reduce-motion toggle exactly —
    // hover of the whole row picks up the accent tint, off state dims
    // the chrome. Focus ring renders when the keyboard accelerator
    // (space/enter toggle, arrow nudges) has focus.
    final Color borderColor = _focused
        ? t.accentBright
        : (off
            ? t.chromeBorder.withValues(alpha: 0.25)
            : (_rowHovered
                ? t.accentBright.withValues(alpha: 0.5)
                : t.inputBorder));
    final Color fillColor = off
        ? t.surface1.withValues(alpha: 0.4)
        : (_rowHovered ? t.accentBright.withValues(alpha: 0.06) : t.inputBg);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _rowHovered = true),
        onExit: (_) => setState(() => _rowHovered = false),
        child: GestureDetector(
          // Whole-row tap toggles OFF ↔ last-positive rate — preserves the
          // original single-click-to-reduce-motion muscle memory. Drag
          // lives on the inner wave only, so tapping the label / badge
          // still just toggles, but dragging across the 5 dots scrubs
          // the rate. The gesture arena resolves the split automatically:
          // no horizontal motion → tap; horizontal motion started over
          // the wave → drag.
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 200)),
            curve: Curves.easeOutCubic,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: _focused ? 1.5 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: t.accentBright.withValues(alpha: 0.18),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reduce motion',
                        style: TextStyle(
                          color: t.textNormal,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedDefaultTextStyle(
                        duration: context
                            .motion(const Duration(milliseconds: 180)),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                        child: Text(_subtitleForRate(rate)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // No onTap here — tap falls through to the outer
                // row-level GestureDetector so the whole button keeps
                // toggling. Only horizontal drag is captured so scrub
                // works precisely on the wave area. Wave speed tracks
                // live rate; no separate overlays, no baseline boost,
                // no emphasis shift — the dots look exactly as they
                // did when the control was a pure bool.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  child: SizedBox(
                    width: _kWaveWidth,
                    height: _kWaveHeight,
                    child: AnimatedBuilder(
                      animation: _phase,
                      builder: (context, _) => CustomPaint(
                        painter: _PulseWavePainter(
                          progress: _phase.value,
                          accent: t.accentBright,
                          muted: t.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _HzBadge(
                  envelope: _envelope,
                  rateFrom: () => _rateFrom,
                  rateTo: () => _rateTo,
                  hzBase: _kWaveHzBase,
                  tokens: t,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frequency readout. Reads the live speed envelope so the number lerps
/// smoothly during the 520ms transition — 0.56 ↔ 0.00 is rendered
/// honestly as the wave actually accelerates / decelerates, not snapped
/// at toggle time.
/// Live Hz readout. Interpolates the displayed rate between the previous
/// and target values across the envelope tween so the digits lerp
/// smoothly during a transition — a drag that moves the rate from 0.56
/// to 1.34 shows the intermediate values ticking by, not a snap.
class _HzBadge extends StatelessWidget {
  final Animation<double> envelope;
  final double Function() rateFrom;
  final double Function() rateTo;
  final double hzBase;
  final AppTokens tokens;

  const _HzBadge({
    required this.envelope,
    required this.rateFrom,
    required this.rateTo,
    required this.hzBase,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: envelope,
      builder: (context, _) {
        final t = envelope.value;
        final rate = rateFrom() + (rateTo() - rateFrom()) * t;
        final live = rate * hzBase;
        // Visual intensity tracks rate magnitude, clamped so >1 rates
        // don't oversaturate the badge. 1.0 = full accent, 0 = muted.
        final fraction = (rate / 2.0).clamp(0.0, 1.0);
        final fg = Color.lerp(tokens.textMuted, tokens.accentBright, fraction)!;
        final bg = Color.lerp(
          tokens.textMuted.withValues(alpha: 0.12),
          tokens.accentBright.withValues(alpha: 0.15),
          fraction,
        )!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          // Monospace with tabular figures so the digits don't shimmy as
          // they change — the badge reads as a steady readout, not a
          // bouncing counter.
          child: Text(
            '${live.toStringAsFixed(2)} Hz',
            style: TextStyle(
              color: fg,
              fontSize: 9,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// Five-dot traveling Gaussian pulse.
/// Phase is the only input — the bump always paints at full magnitude.
/// "Slowing down" is expressed by the parent advancing phase more slowly
/// (or not at all when the speed envelope settles to zero), not by
/// fading the bump out. The bump stays visible at all times; what
/// changes is whether it's moving.
class _PulseWavePainter extends CustomPainter {
  final double progress; // [0..1) wave phase
  final Color accent;
  final Color muted;

  _PulseWavePainter({
    required this.progress,
    required this.accent,
    required this.muted,
  });

  // Painter tuning — 5 dots, with σ widened so the wave's neighbour trail
  // matches the feel of the denser 7-dot layout: at dot spacing Δ=1/5,
  // σ≈0.18 lands the nearest-neighbour bump at ~0.55, same as σ=0.13 at
  // Δ=1/7. So the shape is the same, just spread across fewer dots.
  static const int _kDotCount = 5;
  static const double _kBaseIntensity = 0.32;
  static const double _kBumpIntensity = 0.68;
  static const double _kBaseRadius = 1.5;
  static const double _kBumpRadius = 1.9;
  static const double _kSigma = 0.18; // phase units
  static const double _kTwoSigmaSq = 2 * _kSigma * _kSigma;

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = size.width / (_kDotCount - 1);
    final cy = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _kDotCount; i++) {
      // Dot's phase offset around the cycle. Negative moduli are normalized
      // back into [0,1) by Dart's % so no extra wrap math needed.
      final phase = (progress - i / _kDotCount) % 1.0;
      // Shortest circular distance from the wave peak at phase==0.
      final dist = phase <= 0.5 ? phase : 1.0 - phase;
      // Gaussian e^(-x²/2σ²). Peaks at 1.0, never drops below ~0 at ±3σ.
      final bump = math.exp(-(dist * dist) / _kTwoSigmaSq);

      final intensity = (_kBaseIntensity + bump * _kBumpIntensity)
          .clamp(0.0, 1.0);
      final radius = _kBaseRadius + bump * _kBumpRadius;

      // Color walks from muted (off-pulse) to accent (on the bump) by
      // the bump's gaussian weight, so each dot's hue tells you where
      // it sits relative to the wave peak right now.
      paint.color =
          Color.lerp(muted, accent, bump)!.withValues(alpha: intensity);
      canvas.drawCircle(Offset(i * spacing, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseWavePainter old) =>
      progress != old.progress ||
      accent != old.accent ||
      muted != old.muted;
}

class _CheckboxRow extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  /// Optional tiny visual on the far right of the label line — a small
  /// metaphor for what the toggle controls. Kept size-bounded (≤ 32×20)
  /// so a row with trailing reads the same height as one without.
  final Widget? trailing;

  const _CheckboxRow({
    required this.label,
    this.description,
    required this.value,
    this.enabled = true,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isCrafty = t.id == AppThemeId.crafty;
    final isBlackboard = t.id == AppThemeId.blackboard;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // When a trailing indicator is present the row expands
                // to full width so the indicator can sit pinned at the
                // right edge. Otherwise the row shrinks to fit its
                // content, matching all existing checkbox rows.
                mainAxisSize: trailing == null
                    ? MainAxisSize.min
                    : MainAxisSize.max,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: value
                          ? (isBlackboard ? Colors.transparent : t.sliderThumb)
                          : t.inputBg,
                      borderRadius: BorderRadius.circular(
                          isCrafty ? 0 : (isBlackboard ? 2 : 4)),
                      border: Border.all(
                        color: value
                            ? (isCrafty
                                ? t.btnBorder
                                : (isBlackboard ? Colors.white : t.accentBright))
                            : t.inputBorder,
                        width: isCrafty ? 2 : 1,
                      ),
                      boxShadow: value && isCrafty
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                offset: const Offset(-2, -2),
                              ),
                            ]
                          : null,
                    ),
                    child: value
                        ? _ThemeCheckGlyph(tokens: t)
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(color: t.textNormal, fontSize: 13),
                  ),
                  if (trailing != null) ...[
                    const Spacer(),
                    trailing!,
                  ],
                ],
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Text(
                    description!,
                    style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.65),
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCheckGlyph extends StatelessWidget {
  final AppTokens tokens;

  const _ThemeCheckGlyph({required this.tokens});

  @override
  Widget build(BuildContext context) => switch (tokens.id) {
        AppThemeId.crafty => Center(
            child: Container(width: 10, height: 10, color: tokens.btnBorder),
          ),
        AppThemeId.blackboard => CustomPaint(
            painter: _ChalkDiamondPainter(),
            child: const SizedBox.expand(),
          ),
        _ => Icon(Icons.check, size: 13, color: tokens.bg0),
      };
}

/// Mini-viz for "stash cabinet starts expanded." Mirrors the actual
/// stash drawer in the Changes panel: a `▸ N shelved` header chip at
/// the top, with a reveal area below that holds the stash rows. When
/// the toggle flips, the chevron rotates 90° and the hidden rows slide
/// down into view — exactly what the setting does on repo load.
class _CabinetMiniIndicator extends StatelessWidget {
  final bool expanded;
  final AppTokens tokens;
  const _CabinetMiniIndicator({
    required this.expanded,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dur = context.motion(const Duration(milliseconds: 220));
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    final active = tokens.accentBright;
    return SizedBox(
      width: 32,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Header chip — the "N shelved ▸" pill. Always visible.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              height: 7,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: expanded ? active : muted,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Tiny bar hinting at the "N shelved" label text.
                  Container(
                    width: 12,
                    height: 1,
                    color: expanded ? active : muted,
                  ),
                  AnimatedRotation(
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    turns: expanded ? 0.25 : 0,
                    child: Text(
                      '▸',
                      style: TextStyle(
                        color: expanded ? active : muted,
                        fontSize: 6,
                        height: 1.0,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Reveal area. `ClipRect` + `AnimatedContainer(height: 0/11)`
          // makes the stash rows truly emerge from behind the header
          // rather than fade in place — same motion as a real accordion.
          //
          // The inner Column has a natural height of 8 px (two 3-px
          // rows + a 2-px gap). While the AnimatedContainer's height
          // interpolates through the 0–7 range, a plain Column child
          // would overflow and briefly trip Flutter's layout asserts.
          // `OverflowBox` pins the child to its final 11-px slot so
          // layout never changes during the tween; `ClipRect` above
          // handles the visual reveal by clipping paint.
          Positioned(
            top: 9,
            left: 0,
            right: 0,
            child: ClipRect(
              child: AnimatedContainer(
                duration: dur,
                curve: Curves.easeOutCubic,
                height: expanded ? 11 : 0,
                alignment: Alignment.topCenter,
                child: OverflowBox(
                  minHeight: 11,
                  maxHeight: 11,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniStashRow(active),
                      const SizedBox(height: 2),
                      _miniStashRow(active),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStashRow(Color color) => Container(
        height: 3,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.75), width: 1),
          borderRadius: BorderRadius.circular(1),
        ),
      );
}

/// Mini-viz for "instant blame hover." Mirrors the diff view: two
/// faint code lines, a cursor dot on the lower line, and a blame
/// tooltip. When the toggle is OFF the tooltip simply isn't there —
/// in the real UI you haven't waited the 180 ms yet. When ON the
/// tooltip pops into place next to the cursor with no delay. The
/// presence/absence of the tooltip IS the signal.
class _InstantBlameMiniIndicator extends StatelessWidget {
  final bool instant;
  final AppTokens tokens;
  const _InstantBlameMiniIndicator({
    required this.instant,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dur = context.motion(const Duration(milliseconds: 220));
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    final active = tokens.accentBright;
    return SizedBox(
      width: 32,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Two faint "code lines" — reads as diff context rather than
          // abstract geometry. Second one is the hovered target.
          Positioned(
            top: 4,
            left: 0,
            right: 10,
            child: Container(height: 1, color: muted),
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 16,
            child: Container(height: 1, color: muted),
          ),
          // Cursor on the second line — always visible, marks the
          // hover target. Colors up when instant is engaged so the
          // "hot" state reads as lit.
          Positioned(
            top: 8,
            left: 12,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: instant ? active : muted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Tooltip — present iff instant. When off, it's simply
          // absent (because the delay would have held it back).
          // It scales in from the cursor so the tooltip appears with instant
          // mode timing.
          Positioned(
            top: 13,
            left: 10,
            child: AnimatedOpacity(
              duration: dur,
              curve: Curves.easeOutCubic,
              opacity: instant ? 1.0 : 0.0,
              child: AnimatedScale(
                duration: dur,
                curve: Curves.easeOutCubic,
                scale: instant ? 1.0 : 0.5,
                alignment: Alignment.topLeft,
                child: Container(
                  width: 18,
                  height: 6,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: active.withValues(alpha: 0.20),
                    border: Border.all(color: active, width: 1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Tiny "content" slivers — at this scale they
                      // stand in for the avatar + short-hash + time
                      // slots of the real blame popup.
                      Container(
                        width: 3,
                        height: 1,
                        color: active.withValues(alpha: 0.75),
                      ),
                      Container(
                        width: 6,
                        height: 1,
                        color: active.withValues(alpha: 0.75),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChalkDiamondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    final path = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width - 4, size.height / 2)
      ..lineTo(size.width / 2, size.height - 4)
      ..lineTo(4, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    this.enabled = true,
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
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 80),
            scale: chrome.scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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

class _WrappedAnnotation extends StatelessWidget {
  final String text;
  final Color color;

  const _WrappedAnnotation(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return ThemeMorphText(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        height: 1.25,
      ),
    );
  }
}

String _guardrailPhrase(int stage) {
  switch (stage) {
    case 0:
      return 'Probably fine means fine';
    case 1:
      return 'A proper read, logic, integration, patterns';
    case 2:
      return 'Look again. Something might be hiding';
    case 3:
      return 'Assume something is wrong. Find it';
    default:
      return 'A proper read, logic, integration, patterns';
  }
}

String _themeDescription(AppThemeId id) {
  return themeDefinitionFor(id).option.description;
}

String _reviewGuideHint(int stage) {
  switch (stage) {
    case 0:
      return 'e.g. Focus on high-level logic and major bugs. Be brief and forgiving.';
    case 1:
      return 'e.g. Surface potential bugs, architectural inconsistencies, and edge case failures.';
    case 2:
      return 'e.g. Scrutinize every line for optimization, security, and pattern compliance.';
    case 3:
      return 'e.g. Trust nothing. Question every side effect. Treat every line as a potential failure.';
    default:
      return 'Optional guidance for what the review should care about.';
  }
}
/// Commit format controls with live preview.

class _CommitFormatStage extends StatefulWidget {
  final CommitStructure structure;
  final CommitVoice voice;
  final CommitCoverage coverage;
  final ValueChanged<CommitStructure> onStructureChanged;
  final ValueChanged<CommitVoice> onVoiceChanged;
  final ValueChanged<CommitCoverage> onCoverageChanged;

  const _CommitFormatStage({
    required this.structure,
    required this.voice,
    required this.coverage,
    required this.onStructureChanged,
    required this.onVoiceChanged,
    required this.onCoverageChanged,
  });

  @override
  State<_CommitFormatStage> createState() => _CommitFormatStageState();
}

class _CommitFormatStageState extends State<_CommitFormatStage> {
  // Peek state lives in ValueNotifiers so chip hover doesn't rebuild
  // the gesture layer. Same architecture as Change Sort Guide.
  final ValueNotifier<CommitStructure?> _peekStructure = ValueNotifier(null);
  final ValueNotifier<CommitVoice?> _peekVoice = ValueNotifier(null);
  final ValueNotifier<CommitCoverage?> _peekCoverage = ValueNotifier(null);
  final ValueNotifier<int?> _pressedIndex = ValueNotifier(null);

  @override
  void dispose() {
    _peekStructure.dispose();
    _peekVoice.dispose();
    _peekCoverage.dispose();
    _pressedIndex.dispose();
    super.dispose();
  }

  CommitStructure _effectiveStructure(CommitStructure? peek) =>
      peek ?? widget.structure;
  CommitVoice _effectiveVoice(CommitVoice? peek) => peek ?? widget.voice;
  CommitCoverage _effectiveCoverage(CommitCoverage? peek) =>
      peek ?? widget.coverage;

  /// Build preview text for the selected structure, voice, and coverage.
  String _previewFor({
    required CommitStructure structure,
    required CommitVoice voice,
    required CommitCoverage coverage,
    required int guardrailStage,
  }) {
    final s = guardrailStage;
    final title = _titleFor(voice, s);
    final base = _baseFor(voice, s);
    final body = switch (coverage) {
      CommitCoverage.essentials => base,
      CommitCoverage.balanced => '$base${_balancedSuffixFor(voice, s)}',
      CommitCoverage.everything =>
        '$base${_balancedSuffixFor(voice, s)}${_everythingSuffix(voice, s)}',
    };
    switch (structure) {
      case CommitStructure.titleBody:
        return '$title\n\n$body';
      case CommitStructure.titleOnly:
        return title;
      case CommitStructure.freeform:
        return body;
    }
  }

  /// Compute max preview height across all combinations for this stage.
  /// Keeps the preview card height stable while stage options change.
  double _maxPreviewHeight({
    required double width,
    required TextStyle style,
    required int guardrailStage,
  }) {
    if (width <= 0) return 0;
    double tallest = 0;
    for (final s in CommitStructure.values) {
      for (final v in CommitVoice.values) {
        for (final c in CommitCoverage.values) {
          final text = _previewFor(
            structure: s,
            voice: v,
            coverage: c,
            guardrailStage: guardrailStage,
          );
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: width);
          if (tp.size.height > tallest) tallest = tp.size.height;
          tp.dispose();
        }
      }
    }
    return tallest;
  }

  /// Headline text for each voice/stage combination.
  String _titleFor(CommitVoice voice, int stage) {
    switch (voice) {
      case CommitVoice.verbLed:
        switch (stage) {
          case 0:
            return 'Let fox skip cookies that smell off';
          case 2:
            return 'Train fox to refuse tampered cookies before swallowing';
          case 3:
            return 'Compel fox to forensically vet every cookie at the gate';
          default:
            return 'Teach fox to refuse bad cookies';
        }
      case CommitVoice.descriptive:
        switch (stage) {
          case 0:
            return 'fox now picks the cookies';
          case 2:
            return 'Cookie-inspection routine, drilled into fox';
          case 3:
            return 'Cookie-vetting forensics, embedded in fox by repetition';
          default:
            return 'Cookie-sniff protocol, installed in fox';
        }
      case CommitVoice.narrative:
        switch (stage) {
          case 0:
            return 'the fox started skipping cookies that smelled wrong';
          case 2:
            return 'Sat down with the fox and worked through which '
                'cookies to refuse';
          case 3:
            return 'Spent the better part of an afternoon convincing the '
                'fox that not every cookie offered is, in good faith, '
                'a cookie';
          default:
            return 'Asked the fox to sniff cookies before eating them';
        }
    }
  }

  /// Base body text for each voice/stage combination.
  String _baseFor(CommitVoice voice, int stage) {
    switch (voice) {
      case CommitVoice.verbLed:
        switch (stage) {
          case 0:
            return 'Fox glances. Anything off gets left.';
          case 2:
            return 'Fox inspects each token, declines anything off-scent, '
                'and notes the refusal on the porch.';
          case 3:
            return 'Fox circles each token, samples the air at three angles, '
                'refuses any that read wrong, and waits a beat to make sure '
                'the refusal sticks.';
          default:
            return 'Fox sniffs each token now and politely declines the '
                'suspicious ones.';
        }
      case CommitVoice.descriptive:
        switch (stage) {
          case 0:
            return 'Soft pass on the weird ones, mostly.';
          case 2:
            return 'A documented refusal on every off-scent token, issued '
                'from the porch and noted.';
          case 3:
            return 'A notarized refusal per off-scent token, issued from '
                'the porch with one paw raised, the other still.';
          default:
            return 'A polite refusal on suspicious tokens, issued from the '
                'porch.';
        }
      case CommitVoice.narrative:
        switch (stage) {
          case 0:
            return 'The fox just sort of stopped eating the weird ones. '
                'Easy.';
          case 2:
            return 'Every token used to go down without much thought; now '
                'there\u2019s a pause, a proper look, and a refusal for '
                'the ones that don\u2019t sit right.';
          case 3:
            return 'Every token used to go down without thinking. Now: a '
                'pause. The air, taken in. The air, held. The fox watches '
                'the porch boards for the small twitch they sometimes have '
                'when something is off, and only then is the call made.';
          default:
            return 'Every token used to be swallowed without ceremony; now '
                'there\u2019s a whiff first.';
        }
    }
  }

  /// Extra text for the "balanced" coverage tier (also included in "everything").
  String _balancedSuffixFor(CommitVoice voice, int stage) {
    switch (voice) {
      case CommitVoice.verbLed:
        switch (stage) {
          case 0:
            return ' Porch is fine. Backyard is whatever.';
          case 2:
            return ' Porch swept after each refusal; backyard mud allowed '
                'within posted hours.';
          case 3:
            return ' Porch swept and re-swept; backyard mud catalogued by '
                'paw-print and weather, and the fox lingers at the '
                'threshold longer than before.';
          default:
            return ' Porch stays clean; backyard keeps its mud rights.';
        }
      case CommitVoice.descriptive:
        switch (stage) {
          case 0:
            return ' Porch okay. Backyard does backyard things.';
          case 2:
            return ' Porch as evidence-clean zone; backyard as designated '
                'mud zone, hours posted.';
          case 3:
            return ' Porch as evidence-grade clean room; backyard as '
                'cataloged mud archive; threshold as a place the fox '
                'stands and thinks too long.';
          default:
            return ' Clean porch; mud rights preserved in the backyard.';
        }
      case CommitVoice.narrative:
        switch (stage) {
          case 0:
            return ' Porch was fine. Backyard, who knows.';
          case 2:
            return ' The porch was kept clean afterward; the fox retreated '
                'to the backyard, which is where the thinking happens.';
          case 3:
            return ' The porch was scrubbed twice that evening. The fox '
                'walked the backyard slow, paused at the same fence post '
                'as always, and looked back at the porch like the porch '
                'owed something.';
          default:
            return ' The porch stays clean, though the backyard still '
                'wins on dignity.';
        }
    }
  }

  /// Extra text for the "everything" coverage tier only.
  String _everythingSuffix(CommitVoice voice, int stage) {
    switch (voice) {
      case CommitVoice.verbLed:
        switch (stage) {
          case 0:
            return ' Amber\u2019s there. Drift drifts. Thorn pricks if it '
                'has to. Mostly nothing.';
          case 2:
            return ' Amber holds each scent for review. Drift carries the '
                'day\u2019s air toward the gate thorn, which marks each '
                'refusal for the evening tally.';
          case 3:
            return ' Amber holds each scent and gives a different weight '
                'depending on the hour. Drift moves through the porch at '
                'angles that should not matter but do. The gate thorn '
                'pricks once for refusals and twice for the ones the fox '
                'almost missed, and the fox knows the difference even '
                'when nobody else does.';
          default:
            return ' Amber holds the scent. Drift moves it on. The gate '
                'thorn catches what shouldn\u2019t pass.';
        }
      case CommitVoice.descriptive:
        switch (stage) {
          case 0:
            return ' Amber on the post. Drift in the air. Thorn at the '
                'gate. Fine.';
          case 2:
            return ' Amber as designated scent-witness; drift as a logged '
                'ambient; thorn-marks as the day\u2019s refusal record, '
                'reconciled at dusk.';
          case 3:
            return ' Amber as a scent-witness whose silence is itself a '
                'reading; drift as a patterned ambient that moves wrong '
                'on the days something is wrong; thorn as the gate\u2019s '
                'tally-keeper, whose marks the fox checks before bed and '
                'again before dawn.';
          default:
            return ' Amber as scent-witness; drift as ambient context; '
                'thorn as the gate\u2019s quiet refusal-mark.';
        }
      case CommitVoice.narrative:
        switch (stage) {
          case 0:
            return ' Amber was around. Drift came and went. Thorn did its '
                'quiet thing. Whatever, it was chill.';
          case 2:
            return ' Amber kept the scent-record for the day, drift was '
                'noted by direction and hour, and the thorn\u2019s marks '
                'were tallied and countersigned by the porch.';
          case 3:
            return ' Amber kept the scent-record, but the fox swears it '
                'weighs heavier on certain mornings. Drift moved through '
                'the porch the way it always does, which is to say wrong '
                'on the days that matter. The gate thorn marked each '
                'refusal; the fox went out at first light to count them, '
                'the way you count stairs you have already counted.';
          default:
            return ' Amber held the scent-record, drift moved the air, '
                'and the gate thorn caught what needed catching.';
        }
    }
  }

  String _structureLabel(CommitStructure s) => switch (s) {
        CommitStructure.titleBody => 'title + body',
        CommitStructure.titleOnly => 'title only',
        CommitStructure.freeform => 'freeform',
      };

  String _voiceLabel(CommitVoice v) => switch (v) {
        CommitVoice.verbLed => 'action orientated',
        CommitVoice.descriptive => 'descriptive',
        CommitVoice.narrative => 'narrative',
      };

  String _coverageLabel(CommitCoverage c) => switch (c) {
        CommitCoverage.essentials => 'essentials',
        CommitCoverage.balanced => 'balanced',
        CommitCoverage.everything => 'everything',
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Guardrail subtly flavors the preview copy (see _previewFor).
    // Watching it here rebuilds the stage when the user touches the
    // guardrail slider elsewhere — no AI-generation coupling, purely
    // a settings-UI immersion detail.
    final guardrailStage =
        context.watch<PreferencesState>().guardrailStage;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with badge summarizing the committed triple.
          Row(
            children: [
              Text(
                'Format',
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: Listenable.merge(
                    [_peekStructure, _peekVoice, _peekCoverage]),
                builder: (context, _) {
                  final s = _effectiveStructure(_peekStructure.value);
                  final v = _effectiveVoice(_peekVoice.value);
                  final c = _effectiveCoverage(_peekCoverage.value);
                  // Always include all three axes so the badge's width
                  // doesn't flicker as the user hovers options. Its
                  // width still tweens when label widths differ
                  // (freeform < title + body), but the *segment count*
                  // stays stable so nothing pops in or out.
                  final parts = <String>[
                    _structureLabel(s),
                    _voiceLabel(v),
                    _coverageLabel(c),
                  ];
                  final peeking = _peekStructure.value != null ||
                      _peekVoice.value != null ||
                      _peekCoverage.value != null;
                  if (peeking) parts.add('peek');
                  return AnimatedContainer(
                    duration:
                        context.motion(const Duration(milliseconds: 140)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: peeking
                          ? t.textMuted.withValues(alpha: 0.10)
                          : t.accentBright.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration:
                          context.motion(const Duration(milliseconds: 140)),
                      style: TextStyle(
                        color:
                            peeking ? t.textMuted : t.accentBright,
                        fontSize: 9,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                      child: ThemeMorphText(parts.join(' · ')),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Fixed-height preview card.
          // Pre-measure all format combinations once per width so chip
          // swaps never change card height.
          LayoutBuilder(
            builder: (context, constraints) {
              const horizontalPad = 10.0;
              const verticalPad = 8.0;
              final textStyle = TextStyle(
                color: t.textNormal,
                fontSize: 11.5,
                height: 1.5,
                fontFamily: 'JetBrainsMono',
              );
              final innerWidth =
                  constraints.maxWidth - horizontalPad * 2;
              final reservedHeight = _maxPreviewHeight(
                width: innerWidth,
                style: textStyle,
                guardrailStage: guardrailStage,
              );
              return AnimatedBuilder(
                animation: Listenable.merge(
                    [_peekStructure, _peekVoice, _peekCoverage]),
                builder: (context, _) {
                  final s = _effectiveStructure(_peekStructure.value);
                  final v = _effectiveVoice(_peekVoice.value);
                  final c = _effectiveCoverage(_peekCoverage.value);
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPad, vertical: verticalPad),
                    decoration: BoxDecoration(
                      color: t.surface1.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: t.chromeBorder.withValues(alpha: 0.2)),
                    ),
                    child: SizedBox(
                      height: reservedHeight,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: AnimatedDefaultTextStyle(
                          duration: context
                              .motion(const Duration(milliseconds: 180)),
                          style: textStyle,
                          child: ThemeMorphText(
                            _previewFor(
                              structure: s,
                              voice: v,
                              coverage: c,
                              guardrailStage: guardrailStage,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _CommitFormatChipRow<CommitStructure>(
            label: 'Structure',
            options: CommitStructure.values,
            committed: widget.structure,
            peeking: _peekStructure,
            pressedIndex: _pressedIndex,
            pressedGroup: 0,
            optionLabel: _structureLabel,
            onHoverChanged: (value) {
              if (value != null && value != widget.structure) {
                _peekStructure.value = value;
              } else if (_peekStructure.value == value || value == null) {
                _peekStructure.value = null;
              }
            },
            onTap: (value) {
              _peekStructure.value = null;
              widget.onStructureChanged(value);
            },
          ),
          const SizedBox(height: 10),
          _CommitFormatChipRow<CommitVoice>(
            label: 'Voice',
            options: CommitVoice.values,
            committed: widget.voice,
            peeking: _peekVoice,
            pressedIndex: _pressedIndex,
            pressedGroup: 1,
            optionLabel: _voiceLabel,
            onHoverChanged: (value) {
              if (value != null && value != widget.voice) {
                _peekVoice.value = value;
              } else if (_peekVoice.value == value || value == null) {
                _peekVoice.value = null;
              }
            },
            onTap: (value) {
              _peekVoice.value = null;
              widget.onVoiceChanged(value);
            },
          ),
          const SizedBox(height: 10),
          _CommitFormatChipRow<CommitCoverage>(
            label: 'Coverage',
            options: CommitCoverage.values,
            committed: widget.coverage,
            peeking: _peekCoverage,
            pressedIndex: _pressedIndex,
            pressedGroup: 2,
            optionLabel: _coverageLabel,
            onHoverChanged: (value) {
              if (value != null && value != widget.coverage) {
                _peekCoverage.value = value;
              } else if (_peekCoverage.value == value || value == null) {
                _peekCoverage.value = null;
              }
            },
            onTap: (value) {
              _peekCoverage.value = null;
              widget.onCoverageChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

/// Generic three-option chip row with sliding pill, for any enum-like
/// axis of the commit format stage. Parametrized on the option type so
/// structure/voice/coverage share one implementation without casts.
class _CommitFormatChipRow<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final T committed;
  final ValueNotifier<T?> peeking;
  final ValueNotifier<int?> pressedIndex;
  // Distinguishes which axis is being pressed so the three chip rows
  // don't share a single "pressed index" value (index 0 of structure
  // ≠ index 0 of voice). Encoded as (group * 10 + index) inside the
  // shared pressedIndex notifier.
  final int pressedGroup;
  final String Function(T) optionLabel;
  final ValueChanged<T?> onHoverChanged;
  final ValueChanged<T> onTap;

  const _CommitFormatChipRow({
    required this.label,
    required this.options,
    required this.committed,
    required this.peeking,
    required this.pressedIndex,
    required this.pressedGroup,
    required this.optionLabel,
    required this.onHoverChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            final count = options.length;
            final chipWidth =
                (constraints.maxWidth - gap * (count - 1)) / count;
            return SizedBox(
              height: 30,
              child: Stack(
                children: [
                  ValueListenableBuilder<T?>(
                    valueListenable: peeking,
                    builder: (context, peek, _) {
                      final committedIdx = options.indexOf(committed);
                      final hoverIdx =
                          peek == null ? null : options.indexOf(peek);
                      final targetIdx = hoverIdx ?? committedIdx;
                      final isPreview = hoverIdx != null;
                      return AnimatedPositioned(
                        duration: context
                            .motion(const Duration(milliseconds: 220)),
                        curve: Curves.easeOutCubic,
                        left: targetIdx * (chipWidth + gap),
                        top: 0,
                        bottom: 0,
                        width: chipWidth,
                        child: AnimatedContainer(
                          duration: context
                              .motion(const Duration(milliseconds: 180)),
                          decoration: BoxDecoration(
                            color: isPreview
                                ? t.accentBright.withValues(alpha: 0.05)
                                : t.accentBright.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isPreview
                                  ? t.accentBright.withValues(alpha: 0.45)
                                  : t.accentBright,
                              width: isPreview ? 1 : 1.2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < count; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        Expanded(
                          child: _CommitFormatChipLabel<T>(
                            option: options[i],
                            committed: committed,
                            peeking: peeking,
                            pressedIndex: pressedIndex,
                            pressedKey: pressedGroup * 10 + i,
                            optionLabel: optionLabel,
                            onHoverChanged: onHoverChanged,
                            onTap: onTap,
                            tokens: t,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CommitFormatChipLabel<T> extends StatelessWidget {
  final T option;
  final T committed;
  final ValueListenable<T?> peeking;
  final ValueListenable<int?> pressedIndex;
  final int pressedKey;
  final String Function(T) optionLabel;
  final ValueChanged<T?> onHoverChanged;
  final ValueChanged<T> onTap;
  final AppTokens tokens;

  const _CommitFormatChipLabel({
    required this.option,
    required this.committed,
    required this.peeking,
    required this.pressedIndex,
    required this.pressedKey,
    required this.optionLabel,
    required this.onHoverChanged,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(option),
      onExit: (_) => onHoverChanged(null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) =>
            (pressedIndex as ValueNotifier<int?>).value = pressedKey,
        onTapUp: (_) =>
            (pressedIndex as ValueNotifier<int?>).value = null,
        onTapCancel: () =>
            (pressedIndex as ValueNotifier<int?>).value = null,
        onTap: () => onTap(option),
        child: ValueListenableBuilder<int?>(
          valueListenable: pressedIndex,
          builder: (context, pressed, inner) => AnimatedScale(
            scale: pressed == pressedKey ? 0.97 : 1.0,
            duration: context.motion(const Duration(milliseconds: 110)),
            curve: Curves.easeOutCubic,
            child: inner,
          ),
          child: ValueListenableBuilder<T?>(
            valueListenable: peeking,
            builder: (context, peek, _) {
              final selected = committed == option || peek == option;
              return Container(
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration:
                      context.motion(const Duration(milliseconds: 160)),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: selected
                        ? tokens.accentBright
                        : tokens.textNormal.withValues(alpha: 0.85),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  child: Text(optionLabel(option)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


