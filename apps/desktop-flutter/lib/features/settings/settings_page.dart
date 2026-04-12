import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../backend/ai.dart';
import '../../backend/ai_audit_store.dart';
import '../../backend/command_telemetry_store.dart';
import '../../backend/dtos.dart';
import '../../app/ai_settings_state.dart';
import '../../app/preferences_state.dart';
import '../../app/theme_state.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../../ui/control_chrome.dart';
import '../../ui/form_controls.dart';
import '../../ui/material_surface.dart';
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
              summary: 'Automated action assertion and safety thresholds.',
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
                  _FitLine(
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
                    child: _FitLine(
                      _themeDescription(themeState.themeId),
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            _StateCard(
              title: 'Local Data Retention',
              summary:
                  'Retention policy for local diagnostics and AI audit records.',
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
                  _FitLine(
                    'Includes diagnostics, performance timings, and AI audit metadata.',
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
          summary:
              'Keyboard architecture, interface behavior, and local AI routing.',
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
                description: "It's designed to be efficient, don't hurt its feelings",
                value: preferences.logoAnimatesWhenUnfocused,
                onChanged: (value) {
                  _setLogoAnimatesWhenUnfocused(value);
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
                'Routing and piping interface messages directly to local provider binaries.',
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
        _StateCard(
          title: 'Diagnostics',
          summary:
              'Comparative overview with focused drill-down for each diagnostic stream.',
          wide: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  _GhostMiniButton(
                      label: 'Copy All', onTap: _copyAllDiagnostics),
                ],
              ),
              const SizedBox(height: 8),
              _ResponsiveCardRow(
                gap: 8,
                children: [
                  _DiagnosticsTab(
                    label: 'Command',
                    meta:
                        '${commandReport.totalSamples} samples | ${commandReport.commandCount} commands',
                    active: _diagnosticsFocus == 'command',
                    onTap: () => setState(() => _diagnosticsFocus = 'command'),
                  ),
                  _DiagnosticsTab(
                    label: 'Diff Render',
                    meta:
                        '${diffReport.totalSessions} sessions | ${((1 - diffReport.fallbackRate) * 100).toStringAsFixed(0)}% stability',
                    active: _diagnosticsFocus == 'diff',
                    onTap: () => setState(() => _diagnosticsFocus = 'diff'),
                  ),
                  _DiagnosticsTab(
                    label: 'UI Timing',
                    meta:
                        '${uiReport.totalSamples} samples | ${uiReport.eventCount} events',
                    active: _diagnosticsFocus == 'ui',
                    onTap: () => setState(() => _diagnosticsFocus = 'ui'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _SettingsSubtitle('Top Offenders'),
              const SizedBox(height: 4),
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
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
              const SizedBox(height: 16),
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
            ],
          ),
        ),
        const SizedBox(height: 10),
        _StateCard(
          title: 'Release Channel',
          summary: 'Update feed and crash diagnostics policy.',
          wide: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Channel + crash reporting side-by-side
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ChannelSelect(
                    value: preferences.updateChannel,
                    onChanged: _saveUpdateChannel,
                  ),
                  const Spacer(),
                  _CheckboxRow(
                    label: 'Capture crash diagnostics',
                    description: 'Stores anonymised crash snapshots locally for stability analysis.',
                    value: preferences.crashReportingEnabled,
                    onChanged: _saveCrashReporting,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _PrimaryButton(
                    label: 'Check for Updates',
                    onTap: _showUpdateStubMessage,
                  ),
                  const SizedBox(width: 8),
                  _PrimaryButton(
                    label: 'Install Available Update',
                    enabled: false,
                    onTap: _showUpdateStubMessage,
                  ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: t.rowBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.secondaryBtnBorder),
        ),
        child: Row(
          children: [
            Text(
              '#$rank',
              style: TextStyle(
                color: t.accentBright,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offender.streamLabel,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    offender.name,
                    style: TextStyle(
                      color: t.textStrong,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              offender.metricLabel,
              textAlign: TextAlign.right,
              style: TextStyle(color: t.textMuted, fontSize: 10),
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
      radius: 8,
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
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
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
    _hasFocus = false;
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    _hasFocus = focused;
    // When losing focus, sync the display value back to the parent's
    // canonical value (in case the user typed something invalid).
    if (!focused && mounted) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppInputShell(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onFocusChange: _onFocusChange,
              child: AppTextField(
                controller: _controller,
                height: 28,
                mono: true,
                fontSize: 12,
                keyboardType: TextInputType.number,
                padding: EdgeInsets.zero,
                onSubmitted: (raw) {
                  final parsed = int.tryParse(raw.trim());
                  if (parsed != null) {
                    widget.onChanged(parsed.clamp(widget.min, widget.max));
                  }
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
    return IntrinsicWidth(
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

class _ChannelSelect extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ChannelSelect({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Channel',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 140,
          child: AppDropdownField<String>(
            value: value,
            items: const [
              DropdownMenuItem(value: 'stable', child: Text('Stable')),
              DropdownMenuItem(value: 'beta', child: Text('Beta')),
            ],
            onChanged: (id) {
              if (id != null) {
                onChanged(id);
              }
            },
          ),
        ),
      ],
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
                child: Text('Classic'),
              ),
              DropdownMenuItem(
                value: KeybindingProfile.compact,
                child: Text('Compact'),
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
        const _SettingsSubtitle('Style Guide'),
        const SizedBox(height: 8),
        AppMultilineTextField(
          controller: promptController,
          hintText:
              'Optional guidance for commit message tone, structure, or formatting.',
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
        _CheckboxRow(
          label: 'Double-check review',
          description: 'Run a second verification pass before showing the final report.',
          value: aiSettings.reviewCommitDoubleCheckEnabled,
          onChanged: onDoubleCheckChanged,
        ),
        const SizedBox(height: 12),
        const _SettingsSubtitle('Review Guide'),
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
          'Leave blank to use the built-in review guide.',
          style: TextStyle(
            color: t.textMuted.withValues(alpha: 0.65),
            fontSize: 10.5,
          ),
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

class _DiagnosticsTab extends StatefulWidget {
  final String label;
  final String meta;
  final bool active;
  final VoidCallback onTap;

  const _DiagnosticsTab({
    required this.label,
    required this.meta,
    required this.active,
    required this.onTap,
  });

  @override
  State<_DiagnosticsTab> createState() => _DiagnosticsTabState();
}

class _DiagnosticsTabState extends State<_DiagnosticsTab> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = modeButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      active: widget.active,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: Transform.translate(
              offset: chrome.offset,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.active ? t.accentBright : t.textNormal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.meta,
                      style: TextStyle(color: t.textMuted, fontSize: 10)),
                ],
              ),
            ),
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
        const SizedBox(height: 4),
        Text(
          '${report.totalSamples} samples | ${report.commandCount} unique commands',
          style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        _DiagnosticsActionRow(
          onRefresh: onRefresh,
          clearLabel: 'Clear Samples',
          onClear: onClear,
          clearEnabled: report.totalSamples > 0,
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
        const _SettingsSubtitle('Backend Command Telemetry'),
        const SizedBox(height: 4),
        Text(
          '${backendReport.sampleCount} samples | ${backendReport.summaries.length} scoped commands',
          style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
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
                const SizedBox(height: 8),
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
        const _SettingsSubtitle('Diff Render Diagnostics'),
        const SizedBox(height: 4),
        Text(
          '${report.totalSessions} sessions | jank ${(report.jankyFrameRate * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        _DiagnosticsActionRow(
          onRefresh: onRefresh,
          clearLabel: 'Clear Diff Metrics',
          onClear: onClear,
          clearEnabled: report.totalSessions > 0,
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
        const _SettingsSubtitle('UI Timing Diagnostics'),
        const SizedBox(height: 4),
        Text(
          '${report.totalSamples} samples | ${report.eventCount} instrumented events',
          style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        _DiagnosticsActionRow(
          onRefresh: onRefresh,
          clearLabel: 'Clear UI Timings',
          onClear: onClear,
          clearEnabled: report.totalSamples > 0,
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
    return Row(
      children: [
        _GhostMiniButton(
          label: 'Refresh Snapshot',
          onTap: () {
            onRefresh();
          },
        ),
        const SizedBox(width: 8),
        _PrimaryButton(
          label: clearLabel,
          enabled: clearEnabled,
          onTap: () {
            onClear();
          },
        ),
      ],
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.secondaryBtnBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface0,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++) ...[
            Text(
              items[i],
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            if (i < items.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  final String label;
  final String? description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _CheckboxRow({
    required this.label,
    this.description,
    required this.value,
    this.enabled = true,
    required this.onChanged,
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
                mainAxisSize: MainAxisSize.min,
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
  Widget build(BuildContext context) {
    if (tokens.id == AppThemeId.crafty) {
      return Center(
        child: Container(width: 10, height: 10, color: tokens.btnBorder),
      );
    }
    if (tokens.id == AppThemeId.blackboard) {
      return CustomPaint(
        painter: _ChalkDiamondPainter(),
        child: const SizedBox.expand(),
      );
    }
    return Icon(Icons.check, size: 13, color: tokens.bg0);
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

class _FitLine extends StatelessWidget {
  final String text;
  final Color color;

  const _FitLine(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 11),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
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

