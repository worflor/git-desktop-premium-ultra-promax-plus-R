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
import '../../ui/control_chrome.dart';
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
  _PromptSaveState _commitPromptSaveState = _PromptSaveState.idle;
  _PromptSaveState _reviewPromptSaveState = _PromptSaveState.idle;

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
      _refreshAiDiagnostics();
    });
  }

  @override
  void dispose() {
    _commitPromptSaveDebounce?.cancel();
    _reviewPromptSaveDebounce?.cancel();
    _commitPromptController.dispose();
    _reviewPromptController.dispose();
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
                value: preferences.reduceMotion,
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setReduceMotion(value));
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

  const _StateCard({
    required this.title,
    required this.summary,
    required this.child,
    this.wide = false,
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
          Text(
            title,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
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
                color: widget.active ? activeColor : Colors.transparent,
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
            items: const [
              DropdownMenuItem(
                value: KeybindingProfile.classic,
                child: Text('Porcelain'),
              ),
              DropdownMenuItem(
                value: KeybindingProfile.compact,
                child: Text('Numeric'),
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
class _CompactModelSlot extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = context.tokens;
    AiModelOptionData? selectedModel;
    for (final model in category.models) {
      if (model.value == selectedValue) {
        selectedModel = model;
        break;
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
                  controller: controller,
                  hintText: category.label,
                  onChanged: onLabelChanged,
                ),
              ),
              const SizedBox(width: 8),
              if (selectedModel != null)
                _ProviderPill(label: selectedModel.providerLabel),
            ],
          ),
          const SizedBox(height: 8),
          // Model picker
          if (category.models.isEmpty)
            Text(
              'No models detected for this slot.',
              style: TextStyle(color: t.textMuted, fontSize: 11),
            )
          else
            AppDropdownField<String>(
              value: selectedValue,
              items: category.models
                  .map(
                    (model) => DropdownMenuItem<String>(
                      value: model.value,
                      child: Text(model.label),
                    ),
                  )
                  .toList(),
              onChanged: onModelChanged ?? (_) {},
            ),
          if (selectedModel != null) ...[
            const SizedBox(height: 6),
            Text(
              'via ${selectedModel.providerLabel.toLowerCase()}',
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
        const SizedBox(height: 6),
        Text(
          'Optional. Appended to the built-in review guide as extra guidance.',
          style: TextStyle(
            color: t.textMuted.withValues(alpha: 0.65),
            fontSize: 10.5,
          ),
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
      baseBorderColor: Colors.transparent,
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
                color: widget.active ? activeColor : Colors.transparent,
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
///
/// Not a checkbox — the element *itself* demonstrates its effect. The
/// dots show a traveling-Gaussian pulse whose forward velocity is
/// modulated by a single envelope:
///
///   * [_speed] is a 0..1 envelope. At 1 the wave advances at the base
///     frequency (≈ 0.556 Hz); at 0 it sits perfectly still. Toggling
///     the pref animates [_speed] across 520ms with easeOutCubic in
///     either direction.
///   * A custom [_phaseTicker] advances the dot-strip's phase by
///     `dt * baseHz * speed` each frame and stops itself once the
///     envelope has settled to zero (no point burning frames on a
///     frozen wave).
///
/// Going INTO reduced: the wave decelerates and the bump freezes
/// wherever it lands — never a teleport, never a disappearing dot.
/// Going OUT: the bump accelerates back up from its frozen position.
/// The frequency badge reads `speed * baseHz` so the Hz number lerps
/// honestly to 0.00 as the wave actually slows, not snapped at toggle
/// time.
///
/// Keyboard: Space/Enter toggle while focused. Focus draws an accent
/// ring. No tap-down scale on this control by design — see the build
/// method.
/// "Change sort guide" picker — three options, rendered as an interactive
/// demo. Above the option row a small stage holds six "file tiles" (each
/// with a stable identity: id / cluster color / letter / impact weight).
/// Hover or focus any option and the tiles *rehearse* that ordering in
/// real time, animating their positions without committing. Click to
/// commit. Same energy as Reduce Motion — the element shows you what it
/// does, so the label becomes a footnote.
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

/// One demo tile in the rehearsal stage. Stable identity across re-sorts
/// so the implicit AnimatedPositioned animates the *same* tile from old
/// position → new position (not a spawn/fade swap).
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
  ///
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
          // ── The rehearsal stage — also the invert toggle ─────────
          // The stage itself is the interaction surface: clicking
          // anywhere on the rehearsal tiles flips the sort order.
          // The tiles animate through to the inverted arrangement via
          // the same AnimatedPositioned machinery, so the "game board"
          // gesture and the invert mechanic are the same thing.
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
          // ── Option row with a sliding selection pill ─────────────
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

/// The rehearsal stage — a horizontal strip of demo tiles that physically
/// translate to new x-positions when the effective sort order changes.
/// Each tile's ValueKey is its id, so Flutter's element reconciliation
/// keeps the *same* widget instance at each id and AnimatedPositioned
/// tweens its new left offset smoothly.
///
/// Sized responsively via LayoutBuilder — tile width fills the available
/// room up to a cap so the stage scales cleanly from a narrow settings
/// column to a wide one without stretching tiles absurdly.
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
///
/// Crucial architectural detail: the `MouseRegion` + `GestureDetector`
/// form a **stable** element tree — neither ever rebuilds on hover or
/// press. Hover/press state travels through [ValueNotifier]s, and only
/// the inner visual subtrees (scale, color) rebuild via
/// `ValueListenableBuilder`. This guarantees Flutter's gesture arena
/// sees the same recognizer across the pointer-down → pointer-up
/// lifecycle; the "first click gets eaten" bug was caused by an
/// ancestor `setState` on `onEnter` swapping those recognizers before
/// the tap could resolve.
///
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
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ReduceMotionToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ReduceMotionToggle> createState() => _ReduceMotionToggleState();
}

class _ReduceMotionToggleState extends State<_ReduceMotionToggle>
    with TickerProviderStateMixin {
  static const Duration _kEnvelopeDuration = Duration(milliseconds: 520);
  // 1 cycle / 1.8 s ≈ 0.556 Hz. The base frequency at full speed.
  static const double _kWaveHz = 1000.0 / 1800.0;

  // Speed envelope drives both the Hz readout AND the phase advancement
  // rate. Going INTO reduced: speed eases 1 → 0, the wave decelerates
  // to a halt and the bump freezes wherever it lands. Going OUT: speed
  // eases 0 → 1, the bump accelerates back up from its frozen position.
  // The dots themselves never disappear — the wave is the same shape
  // throughout, only its forward velocity changes.
  late final AnimationController _speed;
  late final Ticker _phaseTicker;
  final ValueNotifier<double> _phase = ValueNotifier(0.0);
  Duration _lastTick = Duration.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'ReduceMotionToggle');

  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _speed = AnimationController(
      vsync: this,
      duration: _kEnvelopeDuration,
      value: widget.value ? 0.0 : 1.0,
    );
    // Seed phase from the last-persisted position so the bump resumes
    // from wherever it was frozen on the previous session. When reduce
    // motion is OFF, the ticker starts immediately and phase advances
    // from this seed forward; when ON, phase stays put until toggled.
    _phase.value =
        context.read<PreferencesState>().reduceMotionPhase.clamp(0.0, 1.0);
    _phaseTicker = createTicker(_onPhaseTick);
    if (!widget.value) _phaseTicker.start();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onPhaseTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final s = _speed.value;
    // When the envelope has fully settled to zero, the wave has come to
    // rest: stop consuming frames AND persist the frozen phase so the
    // next session can resume the bump from this exact position. The
    // ticker restarts from didUpdateWidget when the user toggles back
    // to normal motion. Without the ticker.stop, it would idle forever
    // computing a phase delta of 0 each frame.
    if (s <= 0.0001 && !_speed.isAnimating) {
      _phaseTicker.stop();
      _lastTick = Duration.zero;
      // Fire-and-forget; the setter debounces writes internally by
      // skipping when the value hasn't changed.
      context.read<PreferencesState>().setReduceMotionPhase(_phase.value);
      return;
    }
    if (s > 0) {
      _phase.value = (_phase.value + dt * _kWaveHz * s) % 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _ReduceMotionToggle old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    // Symmetric easing in both directions — the wave decelerates into
    // stillness, accelerates back out of it. No instant snap, no
    // disappearing dots; the bump is always visible, only its forward
    // velocity changes. The Hz readout reads `_speed * _kWaveHz`, so it
    // honestly counts down to 0.00 as the wave actually slows.
    _speed.animateTo(
      widget.value ? 0.0 : 1.0,
      duration: _kEnvelopeDuration,
      curve: Curves.easeOutCubic,
    );
    if (!_phaseTicker.isActive) {
      _lastTick = Duration.zero;
      _phaseTicker.start();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _phaseTicker.dispose();
    _speed.dispose();
    _phase.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _toggle() {
    widget.onChanged(!widget.value);
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduced = widget.value;

    final Color borderColor = _focused
        ? t.accentBright
        : (reduced
            ? t.chromeBorder.withValues(alpha: 0.25)
            : (_hovered
                ? t.accentBright.withValues(alpha: 0.5)
                : t.inputBorder));

    final Color fillColor = reduced
        ? t.surface1.withValues(alpha: 0.4)
        : (_hovered ? t.accentBright.withValues(alpha: 0.06) : t.inputBg);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          // No press-scale here by design. Every other tappable in the
          // app gets a subtle 0.985× bounce on tap-down, but THIS button
          // is the one place where any tactile micro-motion would
          // contradict the control's purpose — the user is asking for
          // less motion, giving them a farewell bounce on the way in
          // reads as the app not listening. The tap feels instant, the
          // state change is the only feedback needed.
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
                  // Label first — it's what identifies the control.
                  // The waveform (a live demonstration of the motion
                  // state) sits to the right of the text so it reads
                  // as "here's what motion looks like right now",
                  // not as an icon prefixed onto a label.
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
                          duration:
                              context.motion(const Duration(milliseconds: 180)),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 11,
                            height: 1.35,
                          ),
                          child: Text(
                            reduced
                                ? 'Still… like ice?'
                                : 'Flow like water.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 56,
                    height: 18,
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
                  const SizedBox(width: 10),
                  _HzBadge(
                    speed: _speed,
                    hz: _kWaveHz,
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
class _HzBadge extends StatelessWidget {
  final Animation<double> speed;
  final double hz;
  final AppTokens tokens;

  const _HzBadge({
    required this.speed,
    required this.hz,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: speed,
      builder: (context, _) {
        final live = speed.value * hz;
        final fraction = speed.value;
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
///
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
          // Scale-from-cursor materialization on toggle sells the
          // "popped immediately into place" beat.
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

// ── Commit-message format stage ────────────────────────────────────────
//
// Three-axis preference for the shape of generated commit messages:
//   * Structure — title+body / title only / freeform.
//   * Voice     — verb-led / descriptive / narrative.
//   * Coverage  — essentials / balanced / everything.
//
// Mirrors the visual language of the Change Sort Guide: a bordered
// stage with a preview card up top and sliding-pill chip rows below.
// Hover any control to peek the resulting message; click to commit.
// All three axes feed a single pure function that assembles a sample
// commit message — so users see the exact combination they'd get.

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

  /// Sample-message assembler. The same scene plays out across every
  /// preview: a fox is taught to refuse off-scent tokens, with amber as
  /// scent-witness, drift as ambient air, and a gate thorn that marks
  /// the refusals. Coverage controls how far into the scene the
  /// narrator goes (headline / aftermath / deep environment). Voice
  /// controls the grammar and pacing. Guardrail controls the narrator's
  /// mental state: at loose the narrator can barely be bothered to
  /// finish sentences; at paranoid the narrator notices the wrong
  /// things (wood grain, fence-post angles, what amber "weighs" on
  /// certain mornings) and spirals. Every cell of the 4 (beats) ×
  /// 3 (voices) × 4 (stages) matrix is hand-written so the sample
  /// genuinely shifts with each axis instead of word-swapping.
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

  /// Walk the 27 (structure × voice × coverage) combinations for the
  /// given [guardrailStage] and return the tallest rendered height at
  /// [width] under [style]. The preview card uses this to reserve a
  /// footprint that's the exact maximum for *this* stage — so chip
  /// swaps never grow the card, but a loose-stage preview isn't stuck
  /// at paranoid-stage height either. Moving the guardrail slider
  /// resizes the card to fit the new stage's ceiling. Cheap — 27
  /// TextPainter layouts, once per width- or stage-change.
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

  /// Beat 1 of the scene: the headline. What was done with the cookie.
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

  /// Beat 2 of the scene: what the fox actually does now. The body's
  /// opening sentence; coverage tiers add suffixes after it.
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

  /// Beat 3 of the scene: the aftermath. What the porch and backyard
  /// look like after the refusals. Pulled in by the "balanced" coverage
  /// tier and inherited by "everything".
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

  /// Beat 4 of the scene: the deep environment. Amber, drift, and the
  /// gate thorn — the witnesses that keep the day's record. This is
  /// where the schizo dial hits hardest: at paranoid the narrator
  /// starts noticing things the fox would notice and nobody else
  /// would. Pulled in only by the "everything" coverage tier.
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
          // Live preview card — FIXED height.
          //
          // The card reserves exactly as much height as the tallest of
          // the 27 (structure × voice × coverage) variants needs at the
          // current width, measured with a TextPainter for the current
          // guardrail stage's vocabulary. Because the reserved height
          // is the max, no variant can ever grow the card; swapping
          // chips only changes the text inside, never the box. Chip
          // rows below the card therefore never shift. No AnimatedSize,
          // no ConstrainedBox minHeight — those were floor-only and let
          // the card grow above the floor for the paranoid × narrative
          // × everything variant, which is what caused the full-page
          // jump the user saw.
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

