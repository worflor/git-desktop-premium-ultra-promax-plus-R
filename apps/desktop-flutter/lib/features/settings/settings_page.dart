import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../backend/ai.dart' show cliProviderIds;
import '../../backend/ai_api_provider.dart';
import '../../backend/ai_audit_store.dart';
import '../../backend/command_telemetry_store.dart';
import '../../backend/dtos.dart';
import '../../backend/commit_format.dart';
import '../../backend/file_coupling.dart';
import '../../backend/logos_git.dart';
import '../../backend/release_check.dart';
import '../../backend/settings_store.dart';
import '../../backend/storage_paths.dart';
import '../../backend/system_browser.dart';
import '../../backend/undo_controller.dart';
import '../../app/ai_settings_state.dart';
import '../../app/build_info.dart';
import '../../app/logos_git_state.dart';
import '../../app/preferences_state.dart';
import '../../app/repository_state.dart';
import '../../app/window_activity.dart';
import '../../app/external_tools_state.dart';
import '../../app/settings_navigation_state.dart';
import '../../app/theme_state.dart';
import '../../app/tool_detection_state.dart';
import '../../backend/external_tools.dart';
import '../../backend/system_paths.dart';
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
  final SettingsSection? focusSection;
  final VoidCallback? onOpenReleaseNotes;

  const SettingsPage({super.key, this.focusSection, this.onOpenReleaseNotes});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  final Stopwatch _mountedAt = Stopwatch()..start();
  // Section keys for deep-link scroll. Each [SettingsSection] enum
  // value gets a key here; the section's top widget passes the same
  // key. `Scrollable.ensureVisible` then scrolls and we briefly flash
  // the section header to confirm the focus.
  final Map<SettingsSection, GlobalKey> _sectionKeys = {
    SettingsSection.externalTools: GlobalKey(),
  };
  // Drives a brief border / bg pulse on the focused section header
  // after deep-link. Forward-only — fires once per focus request.
  late final AnimationController _focusFlash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  SettingsSection? _flashingSection;
  final Map<String, TextEditingController> _categoryLabelControllers = {};
  final TextEditingController _commitPromptController = TextEditingController();
  final TextEditingController _reviewPromptController = TextEditingController();
  final TextEditingController _musePromptController = TextEditingController();
  String _diagnosticsFocus = 'command';
  String? _actionError;
  bool _releaseChecking = false;
  ReleaseCheckResult? _releaseCheck;
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
    if (widget.focusSection != null) {
      // Defer to post-frame so the section keys have rendered and
      // `Scrollable.ensureVisible` can find them in the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusSection(widget.focusSection!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final aiSettings = context.read<AiSettingsState>();
    if (!identical(aiSettings.runtimeProviders, _aiProviders) &&
        aiSettings.runtimeProviders.isNotEmpty) {
      _aiProviders = aiSettings.runtimeProviders;
      _aiProvidersError = aiSettings.runtimeProvidersError;
    }
    if (!identical(aiSettings.runtimeModelCategories, _aiModelCategories) &&
        aiSettings.runtimeModelCategories.isNotEmpty) {
      _aiModelCategories = aiSettings.runtimeModelCategories;
      _aiModelOptionsError = aiSettings.runtimeModelCategoriesError;
      _syncCategoryControllers();
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fire the focus pulse when the deep-link target changes
    // mid-mount — e.g., the user navigates from one settings link to
    // another without closing the panel.
    if (widget.focusSection != null &&
        widget.focusSection != oldWidget.focusSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusSection(widget.focusSection!);
      });
    }
  }

  /// Scroll the section into view and start the highlight pulse.
  /// Safe to call at any time; ignores requests for sections that
  /// haven't rendered yet (key.currentContext == null).
  void _focusSection(SettingsSection section) {
    final key = _sectionKeys[section];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppMotion.fluid,
      curve: AppMotion.fluidCurve,
      alignment: 0.08,
    );
    setState(() => _flashingSection = section);
    _focusFlash
      ..stop()
      ..value = 0
      ..forward().whenComplete(() {
        if (!mounted) return;
        if (_flashingSection == section) {
          setState(() => _flashingSection = null);
        }
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
    _focusFlash.dispose();
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
    if (!mounted) return;

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

    // If API providers have keys but their models didn't land (network
    // timing on startup, cache miss, etc.), retry once more. The guard
    // in refreshModelCategories detects this via hasApiProvidersWithoutModels.
    if (mounted && aiSettings.hasApiProvidersWithoutModels) {
      await aiSettings.refreshModelCategories(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _aiModelCategories = aiSettings.runtimeModelCategories;
        _aiModelOptionsError = aiSettings.runtimeModelCategoriesError;
        if (_aiModelCategories.isNotEmpty) {
          _syncCategoryControllers();
        }
      });
    }
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
    final prefs = context.read<PreferencesState>();
    // Resolve through the same normalisation the persistence layer uses,
    // so a no-op tap (e.g. clicking the already-active channel, or a
    // value that's about to be coerced — 'dev' on a beta build) doesn't
    // wipe the last poll result.
    final normalized = BuildInfo.normalizeChannelId(value);
    final changed = normalized != prefs.updateChannel;
    setState(() {
      _actionError = null;
      if (changed) {
        // The previous poll was against a different channel; clearing
        // avoids "Up to date on BETA" lingering after a flip to STABLE.
        _releaseCheck = null;
      }
    });
    try {
      await prefs.setUpdateChannel(value);
      if (!mounted) return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Failed to save update channel.');
    }
  }

  Future<void> _saveCrashReporting(bool value) async {
    setState(() {
      _actionError = null;
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
    });
    final diagnostics = DiagnosticsState.instance;
    await diagnostics.clearAllDiagnostics();
    if (!mounted) {
      return;
    }
    setState(() {
      _dataMaintenanceBusy = false;
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
    });
    final count = await AiAuditStore.clearEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _dataMaintenanceBusy = false;
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
    });
    final diagnostics = DiagnosticsState.instance;
    await diagnostics.clearAllDiagnostics();
    final count = await AiAuditStore.clearEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _dataMaintenanceBusy = false;
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
    });
  }

  Future<void> _pollForUpdates() async {
    if (_releaseChecking) return;
    final channel = context.read<PreferencesState>().updateChannel;
    setState(() {
      _releaseChecking = true;
      _actionError = null;
    });
    final result = await ReleaseChecker.check(channel: channel);
    if (!mounted) return;
    setState(() {
      _releaseChecking = false;
      _releaseCheck = result;
    });
  }

  Future<void> _resetLocalData({required bool wipeRecents}) async {
    if (!await _confirmLocalDataAction(
      wipeRecents
          ? 'Wipe all local app data — including the recent repos list — '
              'and quit? Your actual git repos on disk are not touched.'
          : 'Reset local app data and quit?\n\n'
              'Settings, theme, onboarding, AI preferences, telemetry, and '
              'engram caches are cleared. Your recent repos list survives.',
    )) {
      return;
    }
    // Drop the in-memory snapshot so nothing in this process tries to
    // satisfy a future load() from the (now-stale) cache and re-persist it.
    SettingsStore.invalidateCache();
    try {
      if (wipeRecents) {
        // SharedPreferences holds the recent_repos list (plus a few minor
        // UI flags like file-pills-wrap). Clear before the gdpu purge —
        // its native backend is independent of our data dir.
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      }
      await StoragePaths.purgeDataDir();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not clear local data: $e');
      return;
    }
    // Hard exit, intentionally synchronous: any ChangeNotifier disposal
    // running through windowManager.destroy() would happily re-write
    // settings.json from in-memory state and undo the purge. Process.exit
    // skips that lifecycle entirely.
    exit(0);
  }

  Future<void> _forceDeploy() async {
    final url = _releaseCheck?.manifest?.downloadUrl;
    if (url == null || url.isEmpty) return;
    try {
      await openInSystemBrowser(url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = 'Could not open the download URL.');
    }
  }

  List<_ProviderCard> _buildProviderCards() {
    final aiSettings = context.read<AiSettingsState>();
    final apiKeys = aiSettings.apiKeys;
    // Derived from ai.dart's _cliProviderSpecs — no hardcoded set.
    final cliIds = cliProviderIds;

    final cards = <_ProviderCard>[];

    if (_aiProviders.isEmpty) {
      cards.addAll(const [
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
      ]);
    } else {
      for (final provider in _aiProviders) {
        if (cliIds.contains(provider.id)) {
          cards.add(_ProviderCard(
            id: provider.id,
            binaryLabel: provider.resolvedBinary ?? provider.binary,
            status: provider.available
                ? provider.planName ?? 'Ready'
                : 'Not detected',
            detail: provider.healthCheck,
            ready: provider.available,
          ));
        }
      }
    }

    final configuredApiCount = aiApiProviderRegistry
        .where((p) => (apiKeys[p.id]?.apiKey.trim().isNotEmpty ?? false))
        .length;
    cards.add(_ProviderCard(
      id: 'api',
      binaryLabel: 'http',
      status: configuredApiCount > 0
          ? '$configuredApiCount configured'
          : 'Not configured',
      ready: configuredApiCount > 0,
      isApiProvider: true,
      apiProviderId: 'api',
    ));

    return cards;
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

    return ListView(
      // Settings is the other place users frequently switch themes —
      // PageStorageKey survives the widget-tree restructure (glass↔solid
      // shape flip in MaterialSurface) so the scroll position doesn't
      // snap to top each time the active theme changes.
      key: const PageStorageKey('settings.scroll'),
      padding: const EdgeInsets.all(12),
      children: [
        const _FeatureHeader(),
        if (_actionError != null) ...[
          const SizedBox(height: 10),
          _SettingsNotice(
            message: _actionError!,
            error: true,
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
                    'Includes diagnostics, performance timings, and metadata.',
                    color: t.textMuted,
                  ),
                  const SizedBox(height: 8),
                  _HybridRetentionActions(
                    busy: _dataMaintenanceBusy,
                    onClearDiagnostics: () {
                      _clearDiagnostics();
                    },
                    onClearAudit: preferences.hideAiFeatures
                        ? null
                        : () {
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
              _ShortcutsReference(profile: themeState.keybindingProfile),
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
              const _UndoWindowControl(),
              const SizedBox(height: 10),
              if (!preferences.hideAiFeatures) ...[
                _CheckboxRow(
                  label: 'AI read-only mode',
                  description: 'Prevents AI from writing or staging changes automatically.',
                  value: true, // Forced enabled
                  enabled: false, // Grayed out
                  onChanged: (_) {},
                ),
                const SizedBox(height: 10),
              ],
              _CheckboxRow(
                label: 'Logo animates when tabbed out',
                description: preferences.logoAnimatesWhenUnfocused
                    ? "It's designed to be efficient, don't hurt its feelings"
                    : ":(",
                value: preferences.logoAnimatesWhenUnfocused,
                trailing: _LogoMotionMiniIndicator(
                  animates: preferences.logoAnimatesWhenUnfocused,
                  tokens: t,
                ),
                onChanged: (value) {
                  _setLogoAnimatesWhenUnfocused(value);
                },
              ),
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'Remember work in progress',
                description:
                    'Keep your commit drafts and file selection between sessions.',
                value: preferences.rememberWorkInProgress,
                trailing: _WipMemoryMiniIndicator(
                  remembered: preferences.rememberWorkInProgress,
                  tokens: t,
                ),
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setRememberWorkInProgress(value));
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
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'Auto select new changes',
                description:
                    'Newly tracked or changed files are added to the commit selection automatically.',
                value: preferences.autoSelectNewChanges,
                trailing: _AutoSelectMiniIndicator(
                  active: preferences.autoSelectNewChanges,
                  tokens: t,
                ),
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setAutoSelectNewChanges(value));
                },
              ),
              const SizedBox(height: 10),
              _CheckboxRow(
                label: 'Fetch online issues on branch load',
                description:
                    'Pull PR and issue details from your git provider in the background when the branches page opens.',
                value: preferences.fetchOnlineIssuesOnBranchLoad,
                trailing: _OnlineFetchMiniIndicator(
                  active: preferences.fetchOnlineIssuesOnBranchLoad,
                  tokens: t,
                ),
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setFetchOnlineIssuesOnBranchLoad(value));
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
              _CheckboxRow(
                label: 'I hate AI',
                description:
                    "Banish all LLM-backed features. Logos keeps running "
                    "because it's spectral math, not a model.",
                value: preferences.hideAiFeatures,
                trailing: _AiHiddenMiniIndicator(
                  hidden: preferences.hideAiFeatures,
                  tokens: t,
                ),
                onChanged: (value) {
                  unawaited(context
                      .read<PreferencesState>()
                      .setHideAiFeatures(value));
                },
              ),
              if (!preferences.hideAiFeatures) ...[
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
              _ProviderGrid(
                providers: providerCards,
                aiSettings: aiSettings,
                onApiKeyChanged: () {
                  _refreshAiDiagnostics(forceRefresh: true);
                },
              ),
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
              ], // end of `if (!preferences.hideAiFeatures) ...[` AI subtree
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionFlashFrame(
          key: _sectionKeys[SettingsSection.externalTools],
          flash: _flashingSection == SettingsSection.externalTools
              ? _focusFlash
              : null,
          child: const _ExternalToolsCard(),
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
          summary: 'Update related settings.',
          wide: true,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onOpenReleaseNotes != null)
                _ReleaseNotesButton(onTap: widget.onOpenReleaseNotes!),
              if (widget.onOpenReleaseNotes != null)
                const SizedBox(width: 6),
              _ReplayOnboardingButton(
                onTap: () => context.read<OnboardingState>().replay(),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BuildInfoRow(),
              const SizedBox(height: 16),
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
                    label: _releaseChecking
                        ? 'CHECKING…'
                        : 'POLL FOR UPDATES',
                    icon: Icons.radar_outlined,
                    enabled: !_releaseChecking,
                    onTap: () => unawaited(_pollForUpdates()),
                  ),
                  const SizedBox(width: 8),
                  _DeckButton(
                    label: 'OPEN DOWNLOAD',
                    icon: Icons.system_update_alt_outlined,
                    enabled: _releaseCheck?.hasUpdate == true &&
                        (_releaseCheck?.manifest?.downloadUrl?.isNotEmpty ??
                            false),
                    onTap: () => unawaited(_forceDeploy()),
                  ),
                  const Spacer(),
                  _ResetQuitControl(
                    onKeepRepos: () =>
                        unawaited(_resetLocalData(wipeRecents: false)),
                    onWipeAll: () =>
                        unawaited(_resetLocalData(wipeRecents: true)),
                  ),
                ],
              ),
              if (_releaseCheck != null) ...[
                const SizedBox(height: 12),
                _ReleaseCheckBanner(result: _releaseCheck!),
              ],
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
                  fontFamily: AppFonts.mono,
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
                      fontFamily: AppFonts.mono,
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
                fontFamily: AppFonts.mono,
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
class _ReleaseNotesButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ReleaseNotesButton({required this.onTap});

  @override
  State<_ReleaseNotesButton> createState() => _ReleaseNotesButtonState();
}

class _ReleaseNotesButtonState extends State<_ReleaseNotesButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: 'Release notes',
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
              Icons.article_outlined,
              size: 14,
              color: _hover ? t.accentBright : t.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

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
                  fontFamily: AppFonts.mono,
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
  /// Null when AI features are hidden — the "Audit" segment is
  /// elided entirely in that case so the pill reads "Diag · All".
  final VoidCallback? onClearAudit;
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
    final hasAudit = onClearAudit != null;
    final labels = hasAudit
        ? const ['Diag', 'Audit', 'All']
        : const ['Diag', 'All'];
    final actions = hasAudit
        ? <VoidCallback>[onClearDiagnostics, onClearAudit!, onClearAll]
        : <VoidCallback>[onClearDiagnostics, onClearAll];
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
            fontFamily: AppFonts.mono,
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
    // The DEV feed is real only for users running a dev build — beta
    // and stable releases shouldn't expose an in-development update
    // stream they can't actually consume. On those builds the slot
    // looks disabled by default but secretly toggles into a contact
    // link when clicked — see [_DevSlotEasterEgg].
    final isDevBuild = BuildInfo.channel == BuildChannel.dev;
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
          _ChannelRibbonItem(
            label: 'STABLE',
            active: value == 'stable',
            onTap: () => onChanged('stable'),
          ),
          _ChannelRibbonItem(
            label: 'BETA',
            active: value == 'beta',
            onTap: () => onChanged('beta'),
          ),
          if (isDevBuild)
            _ChannelRibbonItem(
              label: 'DEV',
              active: value == 'dev',
              onTap: () => onChanged('dev'),
            )
          else
            const _DevSlotEasterEgg(url: 'https://woflo.dev'),
        ],
      ),
    );
  }
}

class _ChannelRibbonItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = context.tokens;
    final activeColor = t.accentBright;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.35,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? activeColor : activeColor.withValues(alpha: 0),
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
                      label,
                      style: TextStyle(
                        color: active ? activeColor : t.textNormal,
                        fontSize: 10,
                        fontFamily: AppFonts.mono,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (active) ...[
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

/// The DEV ribbon slot, on non-dev builds, doubles as an Easter-egg
/// contact link. By default it looks indistinguishable from a normal
/// disabled DEV channel item — same dim opacity, same DEV label, same
/// uninviting cursor — so it doesn't telegraph itself or get in the
/// way of the normal deployment-channel UX. Click it once and it
/// secretly toggles into a `WOFLO.DEV ↗` link affordance with
/// hoverable brightness; click that and the maintainer's site opens
/// in the system browser, the slot reverts back to its dormant DEV
/// disguise.
///
/// Outside-taps (TapRegion) also revert it. The toggle state is
/// per-instance and never persisted — every visit to settings starts
/// from the dormant face.
class _DevSlotEasterEgg extends StatefulWidget {
  final String url;

  const _DevSlotEasterEgg({required this.url});

  @override
  State<_DevSlotEasterEgg> createState() => _DevSlotEasterEggState();
}

class _DevSlotEasterEggState extends State<_DevSlotEasterEgg> {
  bool _revealed = false;
  bool _hovered = false;
  // One-shot OS-scheduled timer — fires a single event when the
  /// 5s budget elapses, no per-frame polling. Lives only while the
  /// egg is revealed and not actively hovered; cancelled on every
  /// state transition that supersedes it.
  Timer? _autoConcealTimer;

  static const _autoConcealDelay = Duration(seconds: 5);

  void _scheduleAutoConceal() {
    _autoConcealTimer?.cancel();
    _autoConcealTimer = Timer(_autoConcealDelay, () {
      if (!mounted) return;
      _conceal();
    });
  }

  void _cancelAutoConceal() {
    _autoConcealTimer?.cancel();
    _autoConcealTimer = null;
  }

  void _conceal() {
    _cancelAutoConceal();
    if (_revealed || _hovered) {
      setState(() {
        _revealed = false;
        _hovered = false;
      });
    }
  }

  void _onTap() {
    if (!_revealed) {
      // First click: discovery — the dormant DEV disguise reveals
      // itself as the link affordance. Start the auto-conceal countdown
      // so the egg quietly puts its mask back on if the user moves on.
      setState(() => _revealed = true);
      _scheduleAutoConceal();
      return;
    }
    // Second click: actually visit. Conceal first so the slot is
    // back to its dormant face by the time the browser steals focus.
    _cancelAutoConceal();
    setState(() {
      _revealed = false;
      _hovered = false;
    });
    unawaited(openInSystemBrowser(widget.url).catchError((_) {}));
  }

  @override
  void dispose() {
    _autoConcealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // TapRegion gives the egg its escape hatch — anywhere the user
    // clicks outside the slot snaps the disguise back on, so a
    // half-revealed link doesn't linger after they look away.
    return TapRegion(
      onTapOutside: (_) => _conceal(),
      child: MouseRegion(
        // Cursor stays as `basic` while dormant so nothing about the
        // slot whispers "I'm clickable" — that preserves the easter
        // egg. Once revealed, the link cursor sells the affordance.
        cursor: _revealed
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) {
          if (!_revealed) return;
          // User is engaging — pause the auto-conceal so it doesn't
          // snap closed mid-hover. Re-armed on exit below.
          _cancelAutoConceal();
          setState(() => _hovered = true);
        },
        onExit: (_) {
          if (!_hovered) return;
          setState(() => _hovered = false);
          if (_revealed) _scheduleAutoConceal();
        },
        child: GestureDetector(
          onTap: _onTap,
          // AnimatedContainer + AnimatedSwitcher keep the swap snappy
          // and on-brand with the rest of the ribbon: 120ms ease, the
          // same heartbeat the channel items use for active-state
          // transitions.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _revealed
                ? _buildRevealed(t)
                : _buildDormant(t),
          ),
        ),
      ),
    );
  }

  /// Dormant face: pixel-identical to a disabled `_ChannelRibbonItem`
  /// labelled DEV. Mirrors that widget's structure so the ribbon
  /// underline gutter aligns and nothing about the slot betrays the
  /// egg.
  Widget _buildDormant(AppTokens t) {
    return Opacity(
      key: const ValueKey('dormant'),
      opacity: 0.35,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.transparent, width: 2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'DEV',
              style: TextStyle(
                color: t.textNormal,
                fontSize: 10,
                fontFamily: AppFonts.mono,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  /// Revealed face: the contact-link affordance. Same alignment as
  /// the dormant face, but a `WOFLO.DEV` label, a trailing
  /// `open_in_new` glyph, and a hover-driven brightness shift to
  /// signal interactivity.
  Widget _buildRevealed(AppTokens t) {
    final color = _hovered ? t.accentBright : t.textMuted;
    return Container(
      key: const ValueKey('revealed'),
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.transparent, width: 2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 120),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                child: const Text('WOFLO.DEV'),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 9, color: color),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Status row at the top of the Release Deployment card.
/// Shows what binary the user is actually running — version, channel,
/// and short sha when available — so DEV vs BETA vs STABLE is honest.
class _BuildInfoRow extends StatelessWidget {
  const _BuildInfoRow();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final channel = BuildInfo.channel;
    final channelLabel = channel.id.toUpperCase();
    final version = BuildInfo.version.isEmpty ? 'dev' : BuildInfo.version;
    final sha = BuildInfo.gitSha;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: t.chromeAccent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.chromeAccent.withValues(alpha: 0.30)),
          ),
          child: Text(
            channelLabel,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontFamily: AppFonts.mono,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          version,
          style: TextStyle(
            color: t.textStrong,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: AppFonts.mono,
          ),
        ),
        if (sha != null) ...[
          const SizedBox(width: 6),
          Text(
            sha,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontFamily: AppFonts.mono,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReleaseCheckBanner extends StatelessWidget {
  final ReleaseCheckResult result;

  const _ReleaseCheckBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isError = result.status == ReleaseCheckStatus.networkError ||
        result.status == ReleaseCheckStatus.parseError;
    final isUpdate = result.status == ReleaseCheckStatus.updateAvailable;
    final color = isError
        ? t.stateDeleted
        : isUpdate
            ? t.accentBright
            : t.stateAdded;
    final message = _messageFor(result);
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
          color: isError ? t.textStrong : color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _messageFor(ReleaseCheckResult r) {
    final channel = r.channel.toUpperCase();
    switch (r.status) {
      case ReleaseCheckStatus.upToDate:
        return 'Up to date on $channel.';
      case ReleaseCheckStatus.updateAvailable:
        final m = r.manifest!;
        return '$channel ${m.version} is available.';
      case ReleaseCheckStatus.notConfigured:
        // errorDetail surfaces deployment-specific reasons (e.g. an
        // HTTP base URL got rejected for not being HTTPS). The plain
        // case is "no MANIFOLD_UPDATE_BASE_URL was set at build time."
        final detail = r.errorDetail;
        return detail != null && detail.isNotEmpty
            ? 'Update server not configured: $detail'
            : 'No update server configured for this build.';
      case ReleaseCheckStatus.notFound:
        return 'No releases on the $channel channel yet.';
      case ReleaseCheckStatus.networkError:
        final detail = r.errorDetail ?? 'unreachable';
        return 'Update check failed: $detail';
      case ReleaseCheckStatus.parseError:
        final detail = r.errorDetail ?? 'invalid manifest';
        return 'Update check failed: $detail';
    }
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

class _ShortcutsReference extends StatelessWidget {
  final KeybindingProfile profile;

  const _ShortcutsReference({required this.profile});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sections = <(String, List<(String, String)>)>[
      (
        'navigate',
        profile == KeybindingProfile.classic
            ? const [
                ('Changes', 'G C'),
                ('History', 'G H'),
                ('Branches', 'G B'),
                ('X-Ray', 'G S'),
                ('Switch (always)', '⌘ 1/2/3'),
                ('Search', '/'),
                ('Dismiss', 'Esc'),
                ('Refresh', 'F5'),
                ('Shortcuts', '?'),
              ]
            : const [
                ('Changes', '1'),
                ('History', '2'),
                ('Branches', '3'),
                ('X-Ray', '4'),
                ('Switch (always)', '⌘ 1/2/3'),
                ('Search', '/'),
                ('Dismiss', 'Esc'),
                ('Refresh', 'F5'),
                ('Shortcuts', '?'),
              ],
      ),
      (
        'staging',
        const [
          ('Next change', 'J'),
          ('Prev change', 'K'),
          ('Toggle line', 'Space'),
          ('Toggle hunk', 'S'),
          ('Toggle file', 'F'),
          ('Pin context', 'P'),
          ('Commit', '⌘ Enter'),
          ('Commit', '⌘ S'),
          ('Accept hint', 'Tab'),
          ('Undo', '⌘ Z'),
        ],
      ),
      (
        'branches & PRs',
        const [
          ('Navigate', 'J / K'),
          ('Expand', 'Enter'),
          ('Checkout', 'C'),
          ('Approve', 'A'),
          ('Request changes', 'R'),
        ],
      ),
      (
        'modifiers',
        const [
          ('Select range', 'Shift+Click'),
          ('Extended menu', 'Shift+Right click'),
        ],
      ),
    ];

    final accent = t.accentBright.withValues(alpha: 0.40);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var s = 0; s < sections.length; s++) ...[
          if (s > 0) const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                sections[s].$1,
                style: TextStyle(
                  color: t.accentBright,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final row in sections[s].$2)
                _KeybindChip(tokens: t, label: row.$1, key_: row.$2),
            ],
          ),
        ],
      ],
    );
  }
}

class _KeybindChip extends StatelessWidget {
  final AppTokens tokens;
  final String label;
  final String key_;

  const _KeybindChip({
    required this.tokens,
    required this.label,
    required this.key_,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.chromeBorder.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11,
              fontFamily: AppFonts.mono,
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
              key_,
              style: TextStyle(
                color: t.textStrong,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
        ],
      ),
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
  final bool isApiProvider;
  final bool expanded;
  final VoidCallback? onTap;

  const _ProviderNode({
    required this.id,
    required this.status,
    required this.binaryLabel,
    this.detail,
    this.ready = false,
    this.placeholder = false,
    this.isApiProvider = false,
    this.expanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final statusColor = placeholder
        ? t.textMuted
        : ready
            ? t.stateAdded
            : t.stateConflicted;
    final node = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.rowBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: expanded
              ? t.chromeAccent.withValues(alpha: 0.35)
              : t.chromeBorder.withValues(alpha: 0.12),
        ),
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
                  fontFamily: AppFonts.mono,
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
    if (isApiProvider) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: node),
      );
    }
    return node;
  }
}

class _ApiUsageBar extends StatelessWidget {
  final AppTokens tokens;
  final AiApiKeyInfo? info;

  const _ApiUsageBar({required this.tokens, this.info});

  @override
  Widget build(BuildContext context) {
    if (info == null || info!.fraction == null) return const SizedBox.shrink();
    final frac = info!.fraction!;
    final t = tokens;
    final barColor = frac > 0.85
        ? t.stateConflicted
        : frac > 0.6
            ? t.stateModified
            : t.chromeAccent;
    final usedLabel = info!.used != null
        ? '\$${info!.used!.toStringAsFixed(2)}'
        : '';
    final limitLabel = info!.limit != null
        ? ' / \$${info!.limit!.toStringAsFixed(2)}'
        : '';

    return Tooltip(
      message: '$usedLabel$limitLabel this month',
      child: SizedBox(
        height: 12,
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(1.5),
                  child: SizedBox(
                    height: 3,
                    child: CustomPaint(
                      size: const Size(double.infinity, 3),
                      painter: _UsageTrackPainter(
                        fraction: frac,
                        trackColor: t.chromeBorder.withValues(alpha: 0.15),
                        fillColor: barColor.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              usedLabel,
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.6),
                fontSize: 8,
                fontFamily: AppFonts.mono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageTrackPainter extends CustomPainter {
  final double fraction;
  final Color trackColor;
  final Color fillColor;

  _UsageTrackPainter({
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(2),
    );
    canvas.drawRRect(r, Paint()..color = trackColor);
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width * fraction, size.height),
      const Radius.circular(2),
    );
    canvas.drawRRect(fillRect, Paint()..color = fillColor);
  }

  @override
  bool shouldRepaint(_UsageTrackPainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor;
}

class _ProviderCard {
  final String id;
  final String binaryLabel;
  final String status;
  final String? detail;
  final bool ready;
  final bool placeholder;
  final bool isApiProvider;
  final String? apiProviderId;

  const _ProviderCard({
    required this.id,
    required this.binaryLabel,
    required this.status,
    this.detail,
    this.ready = false,
    this.placeholder = false,
    this.isApiProvider = false,
    this.apiProviderId,
  });
}

class _ProviderGrid extends StatefulWidget {
  final List<_ProviderCard> providers;
  final AiSettingsState aiSettings;
  final VoidCallback onApiKeyChanged;

  const _ProviderGrid({
    required this.providers,
    required this.aiSettings,
    required this.onApiKeyChanged,
  });

  @override
  State<_ProviderGrid> createState() => _ProviderGridState();
}

class _ProviderGridState extends State<_ProviderGrid>
    with SingleTickerProviderStateMixin {
  bool _apiExpanded = false;
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandCurve;
  final _keyControllers = <String, TextEditingController>{};
  final _baseUrlControllers = <String, TextEditingController>{};
  final _testing = <String>{};
  final _testResults = <String, bool>{};
  final _keyInfo = <String, AiApiKeyInfo>{};
  final Set<String> _fetchedKeyFingerprints = {};

  TextEditingController _keyController(String providerId) {
    return _keyControllers.putIfAbsent(providerId, () {
      final entry = widget.aiSettings.apiKeyFor(providerId);
      return TextEditingController(text: entry?.apiKey ?? '');
    });
  }

  TextEditingController _baseUrlController(String providerId) {
    return _baseUrlControllers.putIfAbsent(providerId, () {
      final entry = widget.aiSettings.apiKeyFor(providerId);
      final saved = entry?.baseUrl ?? '';
      if (saved.isNotEmpty) return TextEditingController(text: saved);
      final provider = aiApiProviderById(providerId);
      return TextEditingController(text: provider?.defaultBaseUrl ?? '');
    });
  }

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expandCurve = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fetchKeyInfo();
  }

  @override
  void didUpdateWidget(covariant _ProviderGrid old) {
    super.didUpdateWidget(old);
    if (widget.aiSettings != old.aiSettings) _fetchKeyInfo();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    for (final c in _baseUrlControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fetchKeyInfo() {
    final activeIds = <String>{};
    for (final provider in aiApiProviderRegistry) {
      final entry = widget.aiSettings.apiKeyFor(provider.id);
      if (entry == null || entry.apiKey.trim().isEmpty) {
        _keyInfo.remove(provider.id);
        _fetchedKeyFingerprints.remove(provider.id);
        continue;
      }
      activeIds.add(provider.id);
      final fp = '${provider.id}:${entry.apiKey}';
      if (_fetchedKeyFingerprints.contains(fp)) continue;
      final creds = AiApiCredentials(
          apiKey: entry.apiKey, baseUrl: entry.baseUrl);
      provider.fetchKeyInfo(creds).then((info) {
        if (!mounted) return;
        if (info != null) {
          _fetchedKeyFingerprints.add(fp);
          setState(() => _keyInfo[provider.id] = info);
        }
      });
    }
    _keyInfo.removeWhere((id, _) => !activeIds.contains(id));
  }

  void _toggleApi() {
    final dur = context.motionRead(const Duration(milliseconds: 220));
    _expandCtrl.duration = dur;
    setState(() => _apiExpanded = !_apiExpanded);
    if (_apiExpanded) {
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  Future<void> _saveKey(String providerId) async {
    final key = _keyController(providerId).text.trim();
    final baseUrl = _baseUrlController(providerId).text.trim();
    if (key.isEmpty) {
      await widget.aiSettings.clearApiKey(providerId);
    } else {
      await widget.aiSettings.setApiKey(
        providerId,
        key,
        baseUrl: baseUrl.isEmpty ? null : baseUrl,
      );
    }
    setState(() => _testResults.remove(providerId));
    widget.onApiKeyChanged();
    _fetchKeyInfo();
  }

  Future<void> _testKey(String providerId) async {
    final key = _keyController(providerId).text.trim();
    if (key.isEmpty) return;
    setState(() {
      _testing.add(providerId);
      _testResults.remove(providerId);
    });
    final provider = aiApiProviderById(providerId);
    if (provider == null) {
      setState(() {
        _testing.remove(providerId);
        _testResults[providerId] = false;
      });
      return;
    }
    final baseUrl = _baseUrlController(providerId).text.trim();
    final creds = AiApiCredentials(
      apiKey: key,
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
    );
    try {
      final models = await provider.listModels(creds);
      if (!mounted) return;
      setState(() {
        _testing.remove(providerId);
        _testResults[providerId] = models.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testing.remove(providerId);
        _testResults[providerId] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520
            ? 1
            : constraints.maxWidth < 800
                ? 2
                : 3;
        final apiIndex = widget.providers.indexWhere((p) => p.isApiProvider);

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.providers.length; i++)
              if (i == apiIndex)
                _buildApiTile(context, constraints, columns)
              else
                SizedBox(
                  width: _tileWidth(constraints.maxWidth, columns),
                  height: 64,
                  child: _buildNode(widget.providers[i]),
                ),
          ],
        );
      },
    );
  }

  double _tileWidth(double total, int columns) {
    final gaps = (columns - 1) * 8.0;
    return (total - gaps) / columns;
  }

  Widget _buildNode(_ProviderCard p) {
    return _ProviderNode(
      id: p.id,
      binaryLabel: p.binaryLabel,
      status: p.status,
      detail: p.detail,
      ready: p.ready,
      placeholder: p.placeholder,
      isApiProvider: p.isApiProvider,
      expanded: p.isApiProvider && _apiExpanded,
      onTap: p.isApiProvider ? _toggleApi : null,
    );
  }

  Widget _buildApiTile(
      BuildContext context, BoxConstraints constraints, int columns) {
    final t = context.tokens;
    final p = widget.providers.firstWhere((p) => p.isApiProvider);
    final tileW = _tileWidth(constraints.maxWidth, columns);

    return AnimatedBuilder(
      animation: _expandCurve,
      builder: (context, child) {
        final progress = _expandCurve.value;
        final width = tileW + (constraints.maxWidth - tileW) * progress;
        final borderColor = Color.lerp(
          t.chromeBorder.withValues(alpha: 0.12),
          t.chromeAccent.withValues(alpha: 0.35),
          progress,
        )!;

        return SizedBox(
          width: width,
          child: Container(
            decoration: BoxDecoration(
              color: t.rowBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _toggleApi,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.id,
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
                                p.status.toUpperCase(),
                                style: TextStyle(
                                  color: p.ready
                                      ? t.stateAdded
                                      : t.stateConflicted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                p.binaryLabel,
                                style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: 10,
                                  fontFamily: AppFonts.mono,
                                ),
                              ),
                              if (_keyInfo.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ApiUsageBar(
                                    tokens: t,
                                    info: _keyInfo.values
                                        .where((i) => i.fraction != null)
                                        .firstOrNull,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: progress,
                    child: Opacity(
                      opacity: progress,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          children: [
                            for (final provider in aiApiProviderRegistry)
                              _buildProviderRow(t, provider),
                          ],
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

  static String _keyHint(String id) => switch (id) {
        'openrouter' => 'sk-or-...',
        'openai' => 'sk-...',
        'anthropic' => 'sk-ant-...',
        'xai' => 'xai-...',
        _ => 'api key',
      };

  Widget _buildProviderRow(AppTokens t, AiApiProvider provider) {
    final keyCtrl = _keyController(provider.id);
    final urlCtrl = _baseUrlController(provider.id);
    final hasKey = keyCtrl.text.trim().isNotEmpty;
    final isTesting = _testing.contains(provider.id);
    final testResult = _testResults[provider.id];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    provider.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasKey ? t.textNormal : t.textMuted,
                      fontSize: 10,
                      fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isTesting) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(
                      strokeWidth: 1,
                      color: t.textMuted,
                    ),
                  ),
                ] else if (testResult != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: testResult
                          ? t.stateAdded
                          : t.stateConflicted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ApiTextField(
              controller: keyCtrl,
              tokens: t,
              hint: _keyHint(provider.id),
              obscure: true,
              fontSize: 10,
              onSubmitted: () => _saveKey(provider.id),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 100,
            child: _ApiTextField(
              controller: urlCtrl,
              tokens: t,
              hint: 'endpoint',
              fontSize: 9,
              onSubmitted: () => _saveKey(provider.id),
            ),
          ),
          const SizedBox(width: 4),
          _MicroButton(
            label: 'Save',
            tokens: t,
            onTap: () => _saveKey(provider.id),
          ),
          const SizedBox(width: 3),
          _MicroButton(
            label: 'Test',
            tokens: t,
            onTap: hasKey ? () => _testKey(provider.id) : null,
          ),
        ],
      ),
    );
  }
}

class _ApiTextField extends StatefulWidget {
  final TextEditingController controller;
  final AppTokens tokens;
  final String hint;
  final bool obscure;
  final double fontSize;
  final VoidCallback? onSubmitted;

  const _ApiTextField({
    required this.controller,
    required this.tokens,
    required this.hint,
    this.obscure = false,
    this.fontSize = 11,
    this.onSubmitted,
  });

  @override
  State<_ApiTextField> createState() => _ApiTextFieldState();
}

class _ApiTextFieldState extends State<_ApiTextField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final isObscured = widget.obscure && !_revealed;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            obscureText: isObscured,
            style: TextStyle(
              color: t.textNormal,
              fontSize: widget.fontSize,
              fontFamily: AppFonts.mono,
            ),
            cursorColor: t.accentBright,
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: t.textFaint.withValues(alpha: 0.5),
                fontSize: widget.fontSize,
                fontFamily: AppFonts.mono,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: t.textFaint.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: t.textFaint.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: t.chromeAccent),
              ),
            ),
            onSubmitted: widget.onSubmitted != null
                ? (_) => widget.onSubmitted!()
                : null,
          ),
        ),
        if (widget.obscure) ...[
          const SizedBox(width: 6),
          _MicroButton(
            label: _revealed ? 'Hide' : 'Show',
            tokens: t,
            onTap: () => setState(() => _revealed = !_revealed),
          ),
        ],
      ],
    );
  }
}

class _MicroButton extends StatelessWidget {
  final String label;
  final AppTokens tokens;
  final VoidCallback? onTap;

  const _MicroButton({
    required this.label,
    required this.tokens,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: enabled
                ? tokens.chromeAccent.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: enabled
                  ? tokens.chromeAccent.withValues(alpha: 0.25)
                  : tokens.textFaint.withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? tokens.textNormal : tokens.textFaint,
              fontSize: 10,
              fontFamily: AppFonts.mono,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
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
class _ReasoningEffortRow extends StatefulWidget {
  final AppTokens tokens;
  final String modelValue;
  final String categoryId;
  final bool showFastToggle;
  final void Function(int direction)? onVerticalDetent;
  final VoidCallback? onVerticalStart;
  final VoidCallback? onVerticalEnd;

  const _ReasoningEffortRow({
    required this.tokens,
    required this.modelValue,
    required this.categoryId,
    this.showFastToggle = false,
    this.onVerticalDetent,
    this.onVerticalStart,
    this.onVerticalEnd,
  });

  @override
  State<_ReasoningEffortRow> createState() => _ReasoningEffortRowState();
}

class _ReasoningEffortRowState extends State<_ReasoningEffortRow> {
  static const double _verticalDetent = 28.0;
  double _panAccumY = 0.0;

  void _onVerticalDragStart(DragStartDetails _) {
    _panAccumY = 0.0;
    widget.onVerticalStart?.call();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (widget.onVerticalDetent == null) return;
    _panAccumY += d.delta.dy;
    while (_panAccumY >= _verticalDetent) {
      widget.onVerticalDetent!(1);
      _panAccumY -= _verticalDetent;
    }
    while (_panAccumY <= -_verticalDetent) {
      widget.onVerticalDetent!(-1);
      _panAccumY += _verticalDetent;
    }
  }

  void _onVerticalDragEnd(DragEndDetails _) {
    widget.onVerticalEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final aiSettings = context.watch<AiSettingsState>();
    final effortKey = '${widget.categoryId}:${widget.modelValue}';
    final fastKey = 'fast:${widget.categoryId}:${widget.modelValue}';
    final current = aiSettings.reasoningEffortFor(effortKey);
    final isFast = aiSettings.reasoningEffortFor(fastKey) == 'fast';
    final currentIndex = current != null
        ? effortLevels.indexOf(current)
        : -1;
    final trackColor = current != null
        ? t.accentBright.withValues(alpha: 0.45)
        : t.textFaint.withValues(alpha: 0.18);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (_) {},
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.showFastToggle) ...[
              GestureDetector(
                onTap: () => aiSettings.setReasoningEffort(
                    fastKey, isFast ? null : 'fast'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isFast
                          ? t.accentBright.withValues(alpha: 0.12)
                          : Colors.transparent,
                      border: Border.all(
                        color: isFast
                            ? t.accentBright.withValues(alpha: 0.35)
                            : t.chromeBorder.withValues(alpha: 0.18),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'fast',
                      style: TextStyle(
                        color: isFast
                            ? t.accentBright.withValues(alpha: 0.9)
                            : t.textMuted.withValues(alpha: 0.4),
                        fontSize: 9,
                        fontFamily: AppFonts.mono,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: trackColor,
                  inactiveTrackColor: t.chromeBorder.withValues(alpha: 0.14),
                  overlayColor: t.accentBright.withValues(alpha: 0.10),
                  tickMarkShape:
                      const RoundSliderTickMarkShape(tickMarkRadius: 1.5),
                  activeTickMarkColor:
                      t.textMuted.withValues(alpha: 0.5),
                  inactiveTickMarkColor:
                      t.chromeBorder.withValues(alpha: 0.22),
                ),
                child: Slider(
                  value: currentIndex >= 0
                      ? currentIndex.toDouble()
                      : effortLevels.indexOf('medium').toDouble(),
                  min: 0,
                  max: (effortLevels.length - 1).toDouble(),
                  divisions: effortLevels.length - 1,
                  onChanged: (v) {
                    final level = effortLevels[v.round()];
                    aiSettings.setReasoningEffort(effortKey, level);
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 42,
              child: Text(
                current ?? 'default',
                style: TextStyle(
                  color: current != null
                      ? t.textMuted.withValues(alpha: 0.6)
                      : t.textFaint.withValues(alpha: 0.3),
                  fontSize: 8,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ),
            if (current != null)
              GestureDetector(
                onTap: () =>
                    aiSettings.setReasoningEffort(effortKey, null),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.close,
                    size: 10,
                    color: t.textFaint.withValues(alpha: 0.35),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
  double _borderGlow = 0.0;
  int _detentCount = 0;

  void _onPropagateDetent(int _) {
    _detentCount++;
    final aiSettings = context.read<AiSettingsState>();
    final effortKey = '${widget.category.id}:${widget.selectedValue}';
    final current =
        aiSettings.reasoningEffortFor(effortKey) ?? 'medium';

    if (_detentCount == 1) {
      aiSettings.setReasoningEffortForCategory(
          widget.category.id, current);
      setState(() => _borderGlow = 0.5);
    } else if (_detentCount == 2) {
      aiSettings.setReasoningEffortGlobal(current);
      setState(() => _borderGlow = 1.0);
    }
  }

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

    final glowColor = Color.lerp(
      t.chromeBorder.withValues(alpha: 0.14),
      t.accentBright.withValues(alpha: 0.6),
      _borderGlow,
    )!;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: glowColor, width: 1.0 + _borderGlow),
        boxShadow: _borderGlow > 0.3
            ? [
                BoxShadow(
                  color: t.accentBright
                      .withValues(alpha: (_borderGlow - 0.3) * 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
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
                fontFamily: AppFonts.mono,
              ),
            ),
          ],
          if (selectedModel != null &&
              (selectedModel.supportsReasoning || selectedModel.hasFastTier))
            _ReasoningEffortRow(
              tokens: t,
              modelValue: widget.selectedValue,
              categoryId: widget.category.id,
              showFastToggle: selectedModel.hasFastTier,
              onVerticalDetent: _onPropagateDetent,
              onVerticalStart: () {
                _detentCount = 0;
              },
              onVerticalEnd: () =>
                  setState(() => _borderGlow = 0.0),
            ),
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
              fontFamily: AppFonts.mono,
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
              fontFamily: AppFonts.mono,
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
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomModelChin extends StatefulWidget {
  final List<({String providerId, String providerLabel})> providers;
  final Map<String, TextEditingController> customControllers;
  final void Function(String providerId) onCustomSubmit;

  const _CustomModelChin({
    required this.providers,
    required this.customControllers,
    required this.onCustomSubmit,
  });

  @override
  State<_CustomModelChin> createState() => _CustomModelChinState();
}

class _CustomModelChinState extends State<_CustomModelChin>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _ctrl;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    final dur = context.motionRead(const Duration(milliseconds: 180));
    _ctrl.duration = dur;
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final progress = _curve.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _toggle,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    children: [
                      Text(
                        'custom model id',
                        style: TextStyle(
                          color: t.textMuted.withValues(alpha: 0.45),
                          fontSize: 10,
                          fontFamily: AppFonts.mono,
                        ),
                      ),
                      const Spacer(),
                      Transform.rotate(
                        angle: progress * 3.14159 * 0.5,
                        child: Icon(
                          Icons.chevron_right,
                          size: 12,
                          color: t.textMuted.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: progress,
                child: Opacity(
                  opacity: progress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < widget.providers.length;
                            i++) ...[
                          _CustomModelRow(
                            providerLabel:
                                widget.providers[i].providerLabel,
                            controller: widget.customControllers[
                                widget.providers[i].providerId]!,
                            onSubmit: () => widget.onCustomSubmit(
                                widget.providers[i].providerId),
                          ),
                          if (i < widget.providers.length - 1)
                            const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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

class _ModelPickerOverlay extends StatefulWidget {
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
  State<_ModelPickerOverlay> createState() => _ModelPickerOverlayState();
}

class _ModelPickerOverlayState extends State<_ModelPickerOverlay> {
  final _filterCtrl = TextEditingController();
  final _filterFocus = FocusNode();
  String _query = '';
  String? _providerFilter;

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _filterCtrl.removeListener(_onQueryChanged);
    _filterCtrl.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final next = _filterCtrl.text.trim().toLowerCase();
    if (next != _query) setState(() => _query = next);
  }

  List<AiModelOptionData> get _filtered {
    var list = widget.models;
    if (_providerFilter != null) {
      list = list
          .where((m) => m.providerId == _providerFilter)
          .toList();
    }
    if (_query.isEmpty) return list;
    final terms = _query.split(RegExp(r'\s+'));
    return list.where((m) {
      final haystack = '${m.modelId} ${m.providerId} ${m.label} '
              '${m.description} ${m.providerLabel}'
          .toLowerCase();
      return terms.every((t) => haystack.contains(t));
    }).toList();
  }

  Set<String> get _activeProviderIds {
    final ids = <String>{};
    for (final m in widget.models) {
      ids.add(m.providerId);
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius =
        themeDefinitionFor(t.id).shader.geometry.radius.clamp(0, 18).toDouble();
    final filtered = _filtered;
    final providerIds = _activeProviderIds;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: t.shadowElev.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilterBar(t, providerIds, filtered.length),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: t.chromeBorder.withValues(alpha: 0.10),
                ),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 14),
                          child: Text(
                            _query.isNotEmpty
                                ? 'no models match "$_query"'
                                : 'no models available',
                            style: TextStyle(
                              color: t.textMuted.withValues(alpha: 0.5),
                              fontSize: 11,
                              fontFamily: AppFonts.mono,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          children: [
                            for (final model in filtered)
                              _ModelPickerItem(
                                model: model,
                                selected:
                                    model.value == widget.selectedValue,
                                onTap: () =>
                                    widget.onSelect(model.value),
                              ),
                          ],
                        ),
                ),
                if (widget.providers.isNotEmpty) ...[
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: t.chromeBorder.withValues(alpha: 0.12),
                  ),
                  _CustomModelChin(
                    providers: widget.providers,
                    customControllers: widget.customControllers,
                    onCustomSubmit: widget.onCustomSubmit,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(
      AppTokens t, Set<String> providerIds, int matchCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _filterCtrl,
              focusNode: _filterFocus,
              maxLines: 1,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: AppFonts.mono,
              ),
              cursorColor: t.accentBright,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                hintText: 'filter models...',
                hintStyle: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.35),
                  fontSize: 11,
                  fontFamily: AppFonts.mono,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (_query.isNotEmpty || _providerFilter != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '$matchCount',
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.4),
                  fontSize: 9,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ),
          if (providerIds.length > 1)
            for (final pid in providerIds)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: _FilterChip(
                  label: _providerShort(pid),
                  active: _providerFilter == pid,
                  tokens: t,
                  onTap: () {
                    setState(() {
                      _providerFilter =
                          _providerFilter == pid ? null : pid;
                    });
                  },
                ),
              ),
        ],
      ),
    );
  }

  static String _providerShort(String id) {
    const shorts = {
      'codex': 'cdx',
      'claude': 'cld',
      'gemini': 'gem',
      'opencode': 'oc',
      'openrouter': 'or',
      'openai': 'oai',
      'anthropic': 'ant',
      'xai': 'xai',
    };
    return shorts[id] ?? id.substring(0, id.length.clamp(0, 3));
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final AppTokens tokens;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: active
                ? tokens.accentBright.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active
                  ? tokens.accentBright.withValues(alpha: 0.4)
                  : tokens.textFaint.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active
                  ? tokens.accentBright
                  : tokens.textMuted.withValues(alpha: 0.5),
              fontSize: 8,
              fontFamily: AppFonts.mono,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
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

  static String? _formatPrice(AiModelOptionData m) {
    if (!m.hasPricing) return null;
    final i = m.promptPricePer1m;
    final o = m.completionPricePer1m;
    if ((i == null || i == 0) && (o == null || o == 0)) return 'free';
    final iStr = i != null ? '\$${_compact(i)}' : '?';
    final oStr = o != null ? '\$${_compact(o)}' : '?';
    return '$iStr/$oStr';
  }

  static String _compact(double v) {
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 10) return v.toStringAsFixed(1);
    if (v >= 1) return v.toStringAsFixed(2);
    if (v >= 0.01) return v.toStringAsFixed(3);
    return v.toStringAsFixed(4);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final price = _formatPrice(model);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        color: selected ? t.accentBright.withValues(alpha: 0.08) : null,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: price != null ? 0 : 0),
              child: Text(
                model.label,
                style: TextStyle(
                  color: selected ? t.accentBright : t.textNormal,
                  fontSize: 12,
                ),
              ),
            ),
            if (price != null)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          (selected
                                  ? t.accentBright.withValues(alpha: 0.08)
                                  : t.surface1)
                              .withValues(alpha: 0.0),
                          selected
                              ? t.accentBright.withValues(alpha: 0.08)
                              : t.surface1,
                        ],
                        stops: const [0.0, 0.25],
                      ),
                    ),
                    child: Text(
                      price,
                      style: TextStyle(
                        color: t.textFaint.withValues(alpha: 0.45),
                        fontSize: 9,
                        fontFamily: AppFonts.mono,
                        letterSpacing: -0.2,
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
          // Narrowed to a single record-select rather than three
          // whole-PreferencesState watches. Dart records use
          // structural equality, so the stage rebuilds only when one
          // of these three fields genuinely changes.
          structure: context.select<PreferencesState, CommitStructure>(
              (s) => s.commitStructure),
          voice: context.select<PreferencesState, CommitVoice>(
              (s) => s.commitVoice),
          coverage: context.select<PreferencesState, CommitCoverage>(
              (s) => s.commitCoverage),
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

// Logos pad + live lens readout. The pad's knob position (padX, padY)
// drives the actual Logos relevance engine against the user's repo: dots
// on the pad are real file neighbours of the recent-activity focus, not
// static decoration, and the side panel reports the current lens as
// live signal instead of hardcoded spec-sheet strings.

/// One file projected into the lens. Position is deterministic from the
/// file's structural/history axis scores, size/opacity track current
/// phi (heat-kernel support) at the puck-selected temperature.
class _LensNeighbor {
  final String path;
  final double bx; // 0..1 pad-space X
  final double by; // 0..1 pad-space Y
  final double phi; // 0..1 current heat-kernel support
  final bool reachable; // above the current coherence gate
  const _LensNeighbor({
    required this.path,
    required this.bx,
    required this.by,
    required this.phi,
    required this.reachable,
  });
}

/// Snapshot of the lens at a given puck position. Produced by
/// [_computeLens] and threaded to both the pad painter and the
/// readout — single source of truth so the two stay in sync.
class _LensSnapshot {
  final List<_LensNeighbor> neighbours;
  final double tTemperature; // heat-kernel `t` the puck decoded to
  final double coherenceGate; // the gate threshold the puck decoded to
  final int reachableCount; // count of neighbours above the gate
  final bool ready; // false = engine not available, still show pad chrome
  const _LensSnapshot({
    required this.neighbours,
    required this.tTemperature,
    required this.coherenceGate,
    required this.reachableCount,
    required this.ready,
  });

  static const _LensSnapshot empty = _LensSnapshot(
    neighbours: [],
    tTemperature: 1.0,
    coherenceGate: 0.25,
    reachableCount: 0,
    ready: false,
  );
}

/// Resolve puck → (t, coherenceGate) using the same mapping the
/// changes page's rerank already uses (`changes_page.dart:4806-4808`).
/// Matters for integrity: the preview has to be the same function of
/// padX/padY that the real feature applies, or the lens would lie.
({double t, double gate}) _padToLensParams(double padX, double padY) {
  final t = 0.5 * math.pow(4.0, padY).toDouble();
  final gate = (0.35 - (padX.clamp(0.0, 1.0) * 0.20)).toDouble();
  return (t: t, gate: gate);
}

/// Deterministic angle for a path. Same path always lands at the same
/// angular home so dots don't rotate on every recompute — only their
/// radial distance changes as the puck moves.
double _pathAngle(String path) {
  var h = 0x811c9dc5;
  for (final c in path.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return (h & 0xffff) / 0xffff * 2 * math.pi;
}

/// Evaluate the lens at the current puck using the engine's own
/// diffuse API. One `chebyshevDiffuse` call per puck movement — the
/// same path `changes_page`'s rerank uses, minus the gathering of
/// secondary summaries we don't need. Sub-millisecond on warm graphs
/// at our scale (500-ish files, k≈20 Chebyshev terms).
///
/// No manual `_buildRho` / `project` / `recombine`: that was me
/// reinventing what `diffuseWeighted` already does, and missing a
/// bunch of wiring (derived-path phi, coherence gating) along the way.
_LensSnapshot _evaluateLens({
  required LogosGit engine,
  required Map<String, double> focusWeights,
  required double padX,
  required double padY,
  int topK = 18,
}) {
  final params = _padToLensParams(padX, padY);
  // NO excludePaths: recentActivityWeights returns weights for every
  // touched file (every file, on a live repo), and passing that set as
  // excludePaths would zero out the entire diffusion result. We want
  // the diffusion over the full graph and then rank by phi — seeds
  // naturally sit on top because they're the sources, which is fine
  // for a visual "what does the lens see" preview.
  final results = engine.diffuseWeighted(
    focusWeights,
    t: params.t,
    topK: topK,
  );
  if (results.isEmpty) {
    return _LensSnapshot(
      neighbours: const [],
      tTemperature: params.t,
      coherenceGate: params.gate,
      reachableCount: 0,
      ready: true,
    );
  }
  // Normalise so phi ∈ [0, 1] across the visible slate. Keeps the
  // lens readable no matter what the raw diffusion magnitude looks
  // like at this temperature.
  var maxPhi = 0.0;
  for (final r in results) {
    if (r.phi > maxPhi) maxPhi = r.phi;
  }
  final norm = maxPhi > 1e-12 ? 1.0 / maxPhi : 1.0;

  final neighbours = <_LensNeighbor>[];
  var reachableCount = 0;
  for (final r in results) {
    final p = (r.phi * norm).clamp(0.0, 1.0).toDouble();
    final reachable = p >= params.gate;
    if (reachable) reachableCount++;
    final angle = _pathAngle(r.path);
    final radius = 0.10 + (1.0 - p) * 0.32;
    final bx = (0.5 + radius * math.cos(angle)).clamp(0.05, 0.95).toDouble();
    final by = (0.5 + radius * math.sin(angle)).clamp(0.08, 0.92).toDouble();
    neighbours.add(_LensNeighbor(
      path: r.path,
      bx: bx,
      by: by,
      phi: p,
      reachable: reachable,
    ));
  }
  return _LensSnapshot(
    neighbours: neighbours,
    tTemperature: params.t,
    coherenceGate: params.gate,
    reachableCount: reachableCount,
    ready: true,
  );
}

class _LogosDynamicsStage extends StatefulWidget {
  final double padX;
  final double padY;
  final void Function(double x, double y) onChanged;

  const _LogosDynamicsStage({
    required this.padX,
    required this.padY,
    required this.onChanged,
  });

  @override
  State<_LogosDynamicsStage> createState() => _LogosDynamicsStageState();
}

class _LogosDynamicsStageState extends State<_LogosDynamicsStage> {
  _LensSnapshot _snapshot = _LensSnapshot.empty;

  // Subscribed Provider handles. `didChangeDependencies` wires up the
  // listeners on first mount (and whenever our Provider scope changes);
  // `dispose` tears them down. Both notifiers fan out exactly once per
  // real change — no polling, no mount-timing trap.
  LogosGitState? _logosState;
  RepositoryState? _repoState;

  // Cached focus-weights per resolved engine. `recentActivityWeights`
  // is memoised inside the engine but still O(files × commits) on the
  // first call at this halfLife; no reason to redo it per puck tick.
  LogosGit? _engineCache;
  Map<String, double>? _focusCache;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final logosState = context.read<LogosGitState>();
    final repoState = context.read<RepositoryState>();
    if (!identical(logosState, _logosState)) {
      _logosState?.removeListener(_syncFromState);
      _logosState = logosState;
      _logosState!.addListener(_syncFromState);
    }
    if (!identical(repoState, _repoState)) {
      _repoState?.removeListener(_syncFromState);
      _repoState = repoState;
      _repoState!.addListener(_syncFromState);
    }
    _syncFromState();
  }

  @override
  void didUpdateWidget(covariant _LogosDynamicsStage old) {
    super.didUpdateWidget(old);
    if (old.padX != widget.padX || old.padY != widget.padY) {
      _reEvaluate();
    }
  }

  @override
  void dispose() {
    _logosState?.removeListener(_syncFromState);
    _repoState?.removeListener(_syncFromState);
    super.dispose();
  }

  /// React to engine / repo-path transitions. When there's a repo with
  /// no engine yet, kick off `loadForRepo` (idempotent — the state
  /// guards against duplicate loads internally and the shared resolver
  /// dedupes across callers). When the engine arrives, cache its focus
  /// seeds and evaluate the lens at the current puck.
  void _syncFromState() {
    if (!mounted) return;
    final repoPath = _repoState?.activePath;
    if (repoPath == null) {
      if (_engineCache != null || _snapshot.ready) {
        _engineCache = null;
        _focusCache = null;
        setState(() => _snapshot = _LensSnapshot.empty);
      }
      return;
    }
    final engine = _logosState?.engineFor(repoPath);
    if (engine == null) {
      // Trigger the resolve — this is what was missing. Other
      // consumers (changes_page) do the same thing; without it, a user
      // landing on settings directly never causes the engine to load.
      if (_logosState != null && !_logosState!.isLoading(repoPath)) {
        // ignore: discarded_futures
        _logosState!.loadForRepo(repoPath);
      }
      if (_engineCache != null || _snapshot.ready) {
        _engineCache = null;
        _focusCache = null;
        setState(() => _snapshot = _LensSnapshot.empty);
      }
      return;
    }
    // Engine available. Cache focus seeds once per engine instance.
    if (!identical(engine, _engineCache)) {
      _engineCache = engine;
      _focusCache = engine.recentActivityWeights(halfLifeCommits: 30);
    }
    _reEvaluate();
  }

  /// Compute the snapshot from the cached engine + focus weights at
  /// the current puck. Called on both engine-arrival and puck-change.
  void _reEvaluate() {
    final engine = _engineCache;
    final focus = _focusCache;
    if (engine == null || focus == null || focus.isEmpty) {
      if (_snapshot.ready || _snapshot.neighbours.isNotEmpty) {
        setState(() => _snapshot = _LensSnapshot.empty);
      }
      return;
    }
    final snapshot = _evaluateLens(
      engine: engine,
      focusWeights: focus,
      padX: widget.padX,
      padY: widget.padY,
    );
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      // Pad uses the remaining width; grip stays fixed at 128px.
      const gripW = 128.0;
      const gap = 12.0;
      final totalW = c.maxWidth.clamp(420.0, 720.0).toDouble();
      final padW = (totalW - gripW - gap).clamp(280.0, 600.0).toDouble();
      final padH = (padW / 1.7).clamp(220.0, 360.0).toDouble();
      // Motion-aware resize easing. When the window is live-resized,
      // the LayoutBuilder rebuilds per frame with a slightly new
      // maxWidth — snapping the stage dimensions each rebuild felt
      // jittery. AnimatedContainer smooths the transition so the
      // stage reads as a single object settling into its new size
      // rather than redrawing itself per frame. Duration routed
      // through `context.motion` so reduce-motion users get Duration
      // .zero and the old snap behavior.
      final resizeDur = ctx.motion(const Duration(milliseconds: 320));
      const resizeCurve = Curves.easeOutCubic;
      // Use IntrinsicHeight so whichever child is taller sets the row height.
      return AnimatedContainer(
        duration: resizeDur,
        curve: resizeCurve,
        width: totalW,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: resizeDur,
                curve: resizeCurve,
                width: padW,
                height: padH,
                child: _LogosPad(
                  x: widget.padX,
                  y: widget.padY,
                  snapshot: _snapshot,
                  onChanged: widget.onChanged,
                ),
              ),
              const SizedBox(width: gap),
              SizedBox(
                width: gripW,
                child: _LogosLensReadout(snapshot: _snapshot),
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
  final _LensSnapshot snapshot;
  final void Function(double x, double y) onChanged;

  const _LogosPad({
    required this.x,
    required this.y,
    required this.snapshot,
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
    with SingleTickerProviderStateMixin, WindowAwakeMixin {
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
    );
    _syncAmbient();
  }

  @override
  void onWindowAwakeChanged() => _syncAmbient();

  // Toggle the ambient pulse on window focus. Without this gate the
  // 2.6 s loop keeps ticking + invalidating the AnimatedBuilder every
  // frame even when the user has alt-tabbed away — idle-GPU contributor
  // on the Bibble theme even though the settings pad isn't visible
  // on every page.
  void _syncAmbient() {
    if (!mounted) return;
    final shouldRun = WindowActivity.instance.awake;
    if (shouldRun && !_ambient.isAnimating) {
      _ambient.repeat();
    } else if (!shouldRun && _ambient.isAnimating) {
      _ambient.stop();
    }
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
                  snapshot: widget.snapshot,
                ),
              );
            },
          ),
        ),
      );
    });
  }
}

class _LogosPadPainter extends CustomPainter {
  final double x;
  final double y;
  final bool hovered;
  final double ambient; // 0..1, driven by AnimationController
  final Offset parallax; // -1..1 normalized cursor offset from center
  final List<_TrailDot> trail;
  final DateTime now;
  final AppTokens tokens;
  final _LensSnapshot snapshot;

  _LogosPadPainter({
    required this.x,
    required this.y,
    required this.hovered,
    required this.ambient,
    required this.parallax,
    required this.trail,
    required this.now,
    required this.tokens,
    required this.snapshot,
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
  // Live lens neighbours. Size + opacity track phi (heat-kernel support
  // at the puck's current temperature) so moving the puck visibly
  // reweights every file. Unreachable neighbours (below the coherence
  // gate the puck decoded) render at reduced alpha as a "just outside
  // the ring" hint — they're candidates that would appear if you
  // relaxed the gate by dragging toward HISTORY.
  void _paintNodes(Canvas canvas, double w, double h) {
    final px = x * w;
    final py = y * h;
    final dot = Paint()..style = PaintingStyle.fill;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final neighbours = [...snapshot.neighbours]
      // Draw low-phi first so strong neighbours composite on top.
      ..sort((a, b) => a.phi.compareTo(b.phi));

    for (final n in neighbours) {
      final nx = n.bx * w;
      final ny = n.by * h;
      // Unreachable neighbours fade to a hint; reachable ones land
      // solid accent. This is the visible consequence of the
      // coherence-gate setting (padX).
      final effectivePhi = n.reachable ? n.phi : n.phi * 0.45;
      final r = 1.6 + 3.2 * effectivePhi;
      final alpha = (0.15 + 0.80 * effectivePhi).clamp(0.0, 1.0);
      final col = Color.lerp(
        tokens.textMuted.withValues(alpha: alpha * 0.55),
        tokens.accentBright.withValues(alpha: alpha),
        effectivePhi,
      )!;
      dot.color = col;
      canvas.drawCircle(Offset(nx, ny), r, dot);
      if (n.reachable && n.phi > 0.55) {
        ring.color = tokens.accentBright
            .withValues(alpha: ((n.phi - 0.55) / 0.45 * 0.55).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(nx, ny), r + 3, ring);
      }
    }

    // Label top 3 reachable neighbours — those are the files the user
    // should recognise as "what my current lens is actually seeing".
    final topN = neighbours.where((n) => n.reachable).toList()
      ..sort((a, b) => b.phi.compareTo(a.phi));
    for (final n in topN.take(3)) {
      final labelAlpha = ((n.phi - 0.2) / 0.5).clamp(0.0, 1.0);
      if (labelAlpha <= 0) continue;
      _drawNodeLabel(canvas, n.path, Offset(n.bx * w, n.by * h),
          Offset(px, py),
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
      old.trail.length != trail.length ||
      !identical(old.snapshot, snapshot);
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

/// Live readout sibling of the Logos pad. Replaces the old static
/// "method/graph/axes/t/k/range" spec-sheet with the lens's *current*
/// view of the user's repo: how many files are within reach at the
/// puck's tuning, which three are most central, and the decoded `t` /
/// gate values. Everything here derives from the same [_LensSnapshot]
/// the pad painter uses, so dragging the puck moves dots and updates
/// this readout in lockstep.
class _LogosLensReadout extends StatelessWidget {
  final _LensSnapshot snapshot;
  const _LogosLensReadout({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ready = snapshot.ready;
    final top = [...snapshot.neighbours]
      ..sort((a, b) => b.phi.compareTo(a.phi));
    final topReachable =
        top.where((n) => n.reachable).take(3).toList(growable: false);
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
          const SizedBox(height: 10),
          Text(
            'reads how files move together '
            'across structure, history, and '
            'rhythm, so reviews see what '
            'matters, not just what changed.',
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.6),
              fontSize: 10,
              letterSpacing: 0.15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _GripDivider(t: t),
          const SizedBox(height: 12),
          // The count IS the story: dragging the puck changes this
          // number in real time. That's the feedback loop the old
          // hardcoded grip never gave.
          _GripStat(
            label: 'within reach',
            value: ready ? '${snapshot.reachableCount}' : '—',
            t: t,
            mono: true,
          ),
          _GripStat(
            label: 't',
            value: snapshot.tTemperature.toStringAsFixed(2),
            t: t,
            mono: true,
          ),
          _GripStat(
            label: 'gate',
            value: snapshot.coherenceGate.toStringAsFixed(2),
            t: t,
            mono: true,
          ),
          const SizedBox(height: 10),
          _GripDivider(t: t),
          const SizedBox(height: 10),
          Text(
            ready ? 'nearest' : 'warming',
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.55),
              fontSize: 8.5,
              letterSpacing: 1.4,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          if (!ready)
            Text(
              'open a repo to\nsee the lens live',
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.55),
                fontSize: 9.5,
                letterSpacing: 0.3,
                height: 1.55,
              ),
            )
          else if (topReachable.isEmpty)
            Text(
              'no files within\nreach — drag\ntoward HISTORY',
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.55),
                fontSize: 9.5,
                letterSpacing: 0.3,
                height: 1.55,
              ),
            )
          else
            for (final n in topReachable) ...[
              _NeighbourRow(path: n.path, phi: n.phi, t: t),
              const SizedBox(height: 4),
            ],
        ],
      ),
    );
  }
}

/// One row in the readout's "nearest" section. Path shown short-form
/// (filename) and full-form on hover via Tooltip; phi rendered as a
/// 2-char monospace reading so the column aligns.
class _NeighbourRow extends StatelessWidget {
  final String path;
  final double phi;
  final AppTokens t;
  const _NeighbourRow(
      {required this.path, required this.phi, required this.t});

  @override
  Widget build(BuildContext context) {
    // Show the last two path segments so both file name and parent
    // folder are visible in the narrow column (e.g. "backend/git.dart").
    final parts = path.split('/');
    final shortPath =
        parts.length <= 2 ? path : '${parts[parts.length - 2]}/${parts.last}';
    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 350),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 10,
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            phi.toStringAsFixed(2),
            style: TextStyle(
              color: t.accentBright.withValues(alpha: 0.85),
              fontSize: 9.5,
              fontFamily: 'monospace',
              letterSpacing: 0.2,
              height: 1.2,
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
        fontFamily: AppFonts.mono,
      ),
    );
  }
}

class _GhostMiniButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool dimmed;

  const _GhostMiniButton({
    required this.label,
    required this.onTap,
    this.dimmed = false,
  });

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
              child: Opacity(
                opacity: widget.dimmed ? 0.45 : 1.0,
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
                        fontFamily: AppFonts.mono,
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
            fontFamily: AppFonts.mono,
          ),
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          Text(
            'No command timings captured yet. Run normal actions to populate diagnostics.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          _TelemetryTable(
            headers: const ['command', 'p50', 'reliability', 'range'],
            rows: [
              for (final s in summaries)
                _TelemetryTableRow(
                  label: s.command,
                  values: [
                    '${s.p50Ms.toStringAsFixed(1)}ms',
                    '${((s.successCount / s.count) * 100).round()}%',
                    '${s.minMs.round()}–${s.maxMs.round()}ms',
                  ],
                ),
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
            fontFamily: AppFonts.mono,
          ),
        ),
        const SizedBox(height: 10),
        if (backendReport.summaries.isEmpty)
          Text(
            'No backend command samples captured yet. Run git and settings actions to populate this log.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          _TelemetryTable(
            headers: const ['scope', 'p50', 'p95', 'failures'],
            rows: [
              for (final s in backendReport.summaries.take(10))
                _TelemetryTableRow(
                  label: '${s.scope}:${s.command}',
                  values: [
                    '${s.p50Ms}ms',
                    '${s.p95Ms}ms',
                    '${s.failureCount}/${s.sampleCount}',
                  ],
                ),
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
            fontFamily: AppFonts.mono,
          ),
        ),
        const SizedBox(height: 12),
        if (report.modeSummaries.isEmpty)
          Text(
            'No diff render sessions captured yet. Open and scroll file diffs to populate this panel.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          _TelemetryTable(
            headers: const ['renderer', 'first paint', 'frame p95', 'raster p95', 'jank'],
            rows: [
              for (final s in report.modeSummaries)
                _TelemetryTableRow(
                  label: s.rendererMode,
                  values: [
                    '${s.firstPaintP50Ms.toStringAsFixed(0)}ms',
                    '${s.frameTimeP95Ms.toStringAsFixed(1)}ms',
                    '${s.rasterTimeP95Ms.toStringAsFixed(1)}ms',
                    '${(s.jankyFrameRate * 100).toStringAsFixed(0)}%',
                  ],
                ),
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
            fontFamily: AppFonts.mono,
          ),
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          Text(
            'No UI timing sessions captured yet. Open panels and navigate routes to populate this panel.',
            style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
          )
        else
          _TelemetryTable(
            headers: const ['event', 'p50', 'failures', 'range'],
            rows: [
              for (final s in summaries)
                _TelemetryTableRow(
                  label: '${s.phase}:${s.event}',
                  values: [
                    '${s.p50Ms.toStringAsFixed(1)}ms',
                    '${s.failureCount}',
                    '${s.minMs.round()}–${s.maxMs.round()}ms',
                  ],
                ),
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
                    fontFamily: AppFonts.mono,
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

/// Two-stage destructive control. Collapsed it shows a single
/// `RESET & QUIT` button; tapping it reveals two inline sub-buttons
/// — KEEP REPOS (soft reset, preserves recent repos list) and WIPE
/// ALL (hard reset, also nukes SharedPreferences). Outside-tap or a
/// second toggle collapses without committing.
class _ResetQuitControl extends StatefulWidget {
  final VoidCallback onKeepRepos;
  final VoidCallback onWipeAll;

  const _ResetQuitControl({
    required this.onKeepRepos,
    required this.onWipeAll,
  });

  @override
  State<_ResetQuitControl> createState() => _ResetQuitControlState();
}

class _ResetQuitControlState extends State<_ResetQuitControl> {
  bool _expanded = false;

  void _collapse() {
    if (_expanded) setState(() => _expanded = false);
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    // TapRegion gives us the "click anywhere outside to dismiss" affordance
    // without needing a manual overlay. The animated wrapper handles the
    // width transition between the single-button and two-button states;
    // the AnimatedSwitcher inside cross-fades the contents in step.
    return TapRegion(
      onTapOutside: (_) => _collapse(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        alignment: Alignment.centerRight,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _expanded
              ? _buildExpanded(context)
              : _buildCollapsed(context),
        ),
      ),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    return _DeckButton(
      label: 'RESET & QUIT',
      icon: Icons.delete_sweep_outlined,
      isDestructive: true,
      onTap: _toggle,
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DeckButton(
          label: 'KEEP REPOS',
          icon: Icons.history_outlined,
          isDestructive: true,
          onTap: () {
            _collapse();
            widget.onKeepRepos();
          },
        ),
        const SizedBox(width: 6),
        _DeckButton(
          label: 'WIPE ALL',
          icon: Icons.delete_forever_outlined,
          isDestructive: true,
          onTap: () {
            _collapse();
            widget.onWipeAll();
          },
        ),
      ],
    );
  }
}

class _TelemetryTableRow {
  final String label;
  final List<String> values;
  const _TelemetryTableRow({required this.label, required this.values});
}

class _TelemetryTable extends StatelessWidget {
  final List<String> headers;
  final List<_TelemetryTableRow> rows;

  const _TelemetryTable({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colCount = headers.length;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: t.accentBright.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildRow(
            t,
            cells: headers,
            isHeader: true,
            colCount: colCount,
          ),
          for (var i = 0; i < rows.length; i++)
            _buildRow(
              t,
              cells: [rows[i].label, ...rows[i].values],
              isHeader: false,
              colCount: colCount,
              tinted: i.isOdd,
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    dynamic t, {
    required List<String> cells,
    required bool isHeader,
    required int colCount,
    bool tinted = false,
  }) {
    final padded = List<String>.generate(
      colCount,
      (i) => i < cells.length ? cells[i] : '',
    );
    return Container(
      color: tinted && !isHeader
          ? (t.rowBg as Color).withValues(alpha: 0.10)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              padded[0],
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isHeader ? t.textMuted : t.textStrong,
                fontSize: isHeader ? 9 : 10,
                fontWeight: isHeader ? FontWeight.w600 : FontWeight.w600,
                fontFamily: isHeader ? null : AppFonts.mono,
                letterSpacing: isHeader ? 0.4 : 0,
              ),
            ),
          ),
          for (var i = 1; i < colCount; i++)
            Expanded(
              flex: 2,
              child: Text(
                padded[i],
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isHeader ? t.textMuted : t.textNormal,
                  fontSize: isHeader ? 9 : 10,
                  fontWeight: isHeader ? FontWeight.w600 : FontWeight.w500,
                  fontFamily: isHeader ? null : AppFonts.mono,
                  letterSpacing: isHeader ? 0.4 : 0,
                ),
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
                    fontFamily: AppFonts.mono,
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
          fontFamily: AppFonts.mono,
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
                          fontFamily: AppFonts.mono,
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
              fontFamily: AppFonts.mono,
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
              fontFamily: AppFonts.mono,
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

/// Interactive "semi-stage" row — taller than a checkbox, shorter than
/// a full control stage. Renders a small tick-stop slider on the right
/// side with N labeled stops. The last stop's label is an inline
/// [TextField] with every visible decoration stripped: identical to
/// the sibling `Text` labels at rest, quietly editable on tap.
///
/// Editing the last label with an integer strictly greater than
/// [topStopBaseline] unlocks a custom value that becomes the top stop.
/// Any invalid input reverts — no error chrome, it just doesn't take.
/// Selecting a lower stop resets the top stop back to [topStopBaseline]
/// (forgetting the custom unlock), matching the "while you're there"
/// semantics that keep the easter-egg playful rather than permanent.
class _StepperRow extends StatefulWidget {
  final String label;
  final String? description;
  final Widget? descriptionWidget;
  final int value;
  final ValueChanged<int> onChanged;
  /// Fixed discrete stops displayed left-to-right (e.g. [0, 3, 6, 10]).
  /// The top stop is rendered separately and is editable.
  final List<int> fixedStops;
  /// Default value of the top stop. Also the minimum edited-value
  /// ceiling — edits must be strictly greater than this.
  final int topStopBaseline;

  /// Optional vertical-detent callback. Fires with +1 when the user
  /// drags down past a detent threshold, -1 when up. Callers use this
  /// to cycle an orthogonal dimension (e.g. the scope selector on the
  /// undo-window control). When null, vertical drags on the stepper
  /// do nothing and fall through to the enclosing scrollable.
  final void Function(int direction)? onVerticalDetent;

  const _StepperRow({
    required this.label,
    this.description,
    this.descriptionWidget,
    required this.value,
    required this.onChanged,
    required this.fixedStops,
    required this.topStopBaseline,
    this.onVerticalDetent,
  });

  @override
  State<_StepperRow> createState() => _StepperRowState();
}

class _StepperRowState extends State<_StepperRow> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  // GestureDetector below uses `onHorizontalDragUpdate` +
  // `onVerticalDragUpdate` (not `onPanUpdate`). A GestureDetector
  // configured with those two callbacks internally registers
  // independent HorizontalDragGestureRecognizer and
  // VerticalDragGestureRecognizer participants in the gesture arena.
  // The inner vertical recognizer wins against the enclosing
  // scrollable's vertical recognizer when the drag starts on the
  // stepper — so y-drag cycles scopes here while preserving page
  // scroll everywhere else. A single pan recognizer (onPanUpdate)
  // would claim the whole gesture arena and hijack scroll, which is
  // why this is axis-split.
  static const double _stepperWidth = 200.0;
  static const double _stepperHPad = 12.0;
  static const double _verticalDetent = 24.0;
  double _panAccumY = 0.0;

  int get _topStopValue => widget.value >= widget.topStopBaseline
      ? widget.value
      : widget.topStopBaseline;


  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _topStopValue.toString());
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _StepperRow old) {
    super.didUpdateWidget(old);
    // Keep the field text in sync with the model when the parent
    // pushes a new value (e.g. slider moved elsewhere). Don't clobber
    // what the user is actively typing.
    if (!_focus.hasFocus && _ctrl.text != _topStopValue.toString()) {
      _ctrl.text = _topStopValue.toString();
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commitEdit();
  }

  void _commitEdit() {
    final parsed = int.tryParse(_ctrl.text.trim());
    if (parsed != null && parsed > widget.topStopBaseline) {
      widget.onChanged(parsed);
    } else {
      // Invalid or too-small — silently revert. No error state; the
      // field just refuses the edit. The whole point is that it's a
      // seamless label that happens to be editable when you coax it.
      _ctrl.text = _topStopValue.toString();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _formatStop(int s) => s == 0 ? 'Off' : '${s}s';

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    _snapToPointer(d.localPosition.dx);
  }

  void _onVerticalDragStart(DragStartDetails _) {
    _panAccumY = 0.0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (widget.onVerticalDetent == null) return;
    _panAccumY += d.delta.dy;
    while (_panAccumY >= _verticalDetent) {
      widget.onVerticalDetent!(1);
      _panAccumY -= _verticalDetent;
    }
    while (_panAccumY <= -_verticalDetent) {
      widget.onVerticalDetent!(-1);
      _panAccumY += _verticalDetent;
    }
  }

  /// Resolve a pointer x inside the stepper to a continuous integer
  /// value. Drag is free — users can land on 5s, 7s, 12s, whatever —
  /// because personal preference doesn't match the canonical stops.
  /// The track stays evenly divided between stops so a 5s value sits
  /// visibly 2/3 of the way from the "3" stop to the "6" stop (not at
  /// 5/15 = 33% absolute, which'd misalign the dot from the stops).
  /// Clamped into `[0, _topStopValue]` — drag can't unlock a new
  /// custom ceiling; only label edits do.
  void _snapToPointer(double localX) {
    final stops = [...widget.fixedStops, _topStopValue];
    final trackStart = _stepperHPad;
    final trackEnd = _stepperWidth - _stepperHPad;
    final clamped = localX.clamp(trackStart, trackEnd);
    final frac = (clamped - trackStart) / (trackEnd - trackStart);
    // Piecewise-linear: each [stop[i], stop[i+1]] pair fills one
    // equal slice of the track. `seg` is the fractional position in
    // "segments"; `i` is the left stop, `t` is how far into that
    // segment the pointer is.
    final seg = (frac * (stops.length - 1))
        .clamp(0.0, (stops.length - 1).toDouble());
    final i = seg.floor().clamp(0, stops.length - 2);
    final t = seg - i;
    final valueDouble = stops[i] + t * (stops[i + 1] - stops[i]);
    final target = valueDouble.round().clamp(0, _topStopValue);
    if (widget.value != target) {
      if (_focus.hasFocus) _focus.unfocus();
      widget.onChanged(target);
    }
  }

  /// Inverse of `_snapToPointer`: given a value, return the local x
  /// position the dot should render at on the track. Uses the same
  /// piecewise-linear mapping so a tap-snap to 6s and a drag-land on
  /// 6s end up at pixel-identical positions.
  double _xForValue(int v) {
    final stops = [...widget.fixedStops, _topStopValue];
    final trackStart = _stepperHPad;
    final trackEnd = _stepperWidth - _stepperHPad;
    final span = trackEnd - trackStart;
    if (v <= stops.first) return trackStart;
    if (v >= stops.last) return trackEnd;
    var i = 0;
    while (i < stops.length - 1 && stops[i + 1] <= v) {
      i++;
    }
    final t = (v - stops[i]) / (stops[i + 1] - stops[i]);
    final frac = (i + t) / (stops.length - 1);
    return trackStart + frac * span;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Leading spacer matches the 18px checkbox + 8px gap used by
            // `_CheckboxRow`, so this row aligns with its neighbors.
            const SizedBox(width: 26),
            Text(widget.label,
                style: TextStyle(color: t.textNormal, fontSize: 13)),
            const Spacer(),
            _buildStepper(t),
          ],
        ),
        if (widget.descriptionWidget != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: widget.descriptionWidget!,
          ),
        ] else if (widget.description != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              widget.description!,
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.65),
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepper(AppTokens t) {
    // Top stop uses the current value when it's already past the
    // baseline (a custom-unlocked value), otherwise the baseline.
    // Mirrors `_topStopValue`, which drag snapping reads too.
    final stops = [...widget.fixedStops, _topStopValue];
    final trackStart = _stepperHPad;
    final trackEnd = _stepperWidth - _stepperHPad;
    final trackSpan = trackEnd - trackStart;
    final isOnStop = stops.contains(widget.value);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onVerticalDragStart:
          widget.onVerticalDetent == null ? null : _onVerticalDragStart,
      onVerticalDragUpdate:
          widget.onVerticalDetent == null ? null : _onVerticalDragUpdate,
      child: SizedBox(
        width: _stepperWidth,
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Track line under the tick marks.
            Positioned(
              left: trackStart,
              right: _stepperHPad,
              top: 6,
              child: Container(
                height: 1,
                color: t.textMuted.withValues(alpha: 0.30),
              ),
            ),
            for (var i = 0; i < stops.length; i++)
              _buildStop(
                t,
                stops[i],
                isLast: i == stops.length - 1,
                cx: trackStart + (i / (stops.length - 1)) * trackSpan,
              ),
            // Floating "thumb" for off-stop values (e.g. 5s, 7s, 12s).
            // Renders a filled accent dot at the interpolated x plus a
            // tiny value label tucked under it. When the value happens
            // to match a stop exactly, the stop's own "active" styling
            // handles the highlight — no extra thumb needed.
            if (!isOnStop) ..._buildFloatingThumb(t),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFloatingThumb(AppTokens t) {
    final dotX = _xForValue(widget.value);
    final valueText = widget.value == 0 ? 'Off' : '${widget.value}s';
    return [
      Positioned(
        left: dotX - 5,
        top: 2,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: t.sliderThumb,
            shape: BoxShape.circle,
            border: Border.all(color: t.sliderThumbBorder, width: 1.5),
          ),
        ),
      ),
      Positioned(
        left: dotX - 18,
        top: 16,
        width: 36,
        child: Text(
          valueText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: t.accentBright,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
  }

  Widget _buildStop(
    AppTokens t,
    int stopValue, {
    required bool isLast,
    required double cx,
  }) {
    // Exact-match only — off-stop values render as a floating thumb
    // elsewhere, so the stops never "steal" the highlight when the
    // user has landed between them.
    final isActive = widget.value == stopValue;
    final labelColor = isActive ? t.accentBright : t.textMuted;
    final tickColor = isActive ? t.sliderThumb : t.inputBg;
    final tickBorder =
        isActive ? t.sliderThumbBorder : t.textMuted.withValues(alpha: 0.5);
    Widget circle = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: tickColor,
        shape: BoxShape.circle,
        border: Border.all(color: tickBorder, width: 1.5),
      ),
    );
    if (isLast) {
      return Positioned(
        left: cx - 18,
        top: 0,
        child: SizedBox(
          width: 36,
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_focus.hasFocus) _focus.unfocus();
                  widget.onChanged(_topStopValue);
                },
                child: SizedBox(
                  width: 36,
                  height: 14,
                  child: Center(child: circle),
                ),
              ),
              const SizedBox(height: 1),
              _buildLastLabelRow(labelColor),
            ],
          ),
        ),
      );
    }
    return Positioned(
      left: cx - 18,
      top: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(stopValue),
        child: SizedBox(
          width: 36,
          child: Column(
            children: [
              SizedBox(width: 36, height: 14, child: Center(child: circle)),
              const SizedBox(height: 1),
              Text(
                _formatStop(stopValue),
                style: TextStyle(color: labelColor, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastLabelRow(Color labelColor) {
    final style = TextStyle(color: labelColor, fontSize: 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // No decoration: the field is invisible at rest, same glyphs as
        // the sibling Text labels. Discovery happens by accident — you
        // click where you didn't expect a field and find one.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 6, maxWidth: 28),
          child: IntrinsicWidth(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: style,
              cursorWidth: 1,
              cursorHeight: 10,
              cursorColor: labelColor,
              decoration: const InputDecoration(
                isCollapsed: true,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: null,
              ),
              onSubmitted: (_) => _commitEdit(),
            ),
          ),
        ),
        Text('s', style: style),
      ],
    );
  }
}

/// Scope dimension for the undo-window stepper. The "all" scope edits
/// the default seconds; specific scopes write per-kind overrides.
/// Kept as an ordered enum so y-drag can cycle through them cleanly.
enum _UndoScope {
  all,
  discard,
  commit,
  commitAndPush,
}

extension _UndoScopeInfo on _UndoScope {
  /// Human-readable scope name for the description line.
  String get descriptionLabel {
    switch (this) {
      case _UndoScope.all:
        return 'destructive actions';
      case _UndoScope.discard:
        return 'discards';
      case _UndoScope.commit:
        return 'commits';
      case _UndoScope.commitAndPush:
        return 'commit + push';
    }
  }

  /// Short label for the scope chip below the stepper.
  String get chipLabel {
    switch (this) {
      case _UndoScope.all:
        return 'all';
      case _UndoScope.discard:
        return 'discards';
      case _UndoScope.commit:
        return 'commits';
      case _UndoScope.commitAndPush:
        return 'commit + push';
    }
  }

  /// Map back to the underlying `UndoActionKind` for pref lookup.
  /// `all` has no single kind — callers handle it separately.
  UndoActionKind? get kind {
    switch (this) {
      case _UndoScope.all:
        return null;
      case _UndoScope.discard:
        return UndoActionKind.discard;
      case _UndoScope.commit:
        return UndoActionKind.commit;
      case _UndoScope.commitAndPush:
        return UndoActionKind.commitAndPush;
    }
  }
}

/// Wraps `_StepperRow` with scope awareness. The stepper's horizontal
/// axis picks seconds for the current scope; vertical drag cycles
/// through scopes. Reads values from [PreferencesState] and writes
/// via [PreferencesState.setUndoWindowSeconds] / [setUndoWindowFor].
///
/// Shows a small sync glyph inline in the description when per-kind
/// overrides exist — clicking it clears every override so all kinds
/// fall back to the default again. Glyph hides when no overrides are
/// set (nothing to sync).
class _UndoWindowControl extends StatefulWidget {
  const _UndoWindowControl();

  @override
  State<_UndoWindowControl> createState() => _UndoWindowControlState();
}

class _UndoWindowControlState extends State<_UndoWindowControl> {
  _UndoScope _scope = _UndoScope.all;

  static const _orderedScopes = [
    _UndoScope.all,
    _UndoScope.discard,
    _UndoScope.commit,
    _UndoScope.commitAndPush,
  ];

  int _valueFor(PreferencesState prefs) {
    final kind = _scope.kind;
    if (kind == null) return prefs.undoWindowSeconds;
    return prefs.undoWindowFor(kind);
  }

  void _write(PreferencesState prefs, int seconds) {
    final kind = _scope.kind;
    if (kind == null) {
      unawaited(prefs.setUndoWindowSeconds(seconds));
    } else {
      unawaited(prefs.setUndoWindowFor(kind, seconds));
    }
  }

  void _cycleScope(int direction) {
    final idx = _orderedScopes.indexOf(_scope);
    // Dart's `%` returns a non-negative result for positive divisor,
    // so wrap-around for negative direction just works. Adding
    // `_orderedScopes.length` before the mod lets callers pass -1 /
    // +1 or larger magnitudes without an extra branch.
    final next =
        (idx + direction + _orderedScopes.length) % _orderedScopes.length;
    setState(() => _scope = _orderedScopes[next]);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesState>();
    final t = context.tokens;
    final value = _valueFor(prefs);
    final scopeLabel = _scope.descriptionLabel;
    final description = value == 0
        ? '${scopeLabel.substring(0, 1).toUpperCase()}${scopeLabel.substring(1)} finalize instantly.'
        : '${value}s before $scopeLabel finalize.';
    return _StepperRow(
      label: 'Undo window',
      value: value,
      fixedStops: const [0, 3, 6, 10],
      topStopBaseline: 15,
      onChanged: (v) => _write(prefs, v),
      onVerticalDetent: _cycleScope,
      descriptionWidget: _UndoWindowDescription(
        description: description,
        scope: _scope,
        hasOverrides: prefs.hasUndoWindowOverrides,
        tokens: t,
        onResync: () => unawaited(prefs.resyncUndoWindows()),
        onCycleScope: () => _cycleScope(1),
      ),
    );
  }
}

/// Description line for `_UndoWindowControl`. Shows the scope + time
/// sentence, a tiny scope chip (so y-drag has a visible anchor), and
/// conditionally a sync glyph when overrides exist.
class _UndoWindowDescription extends StatelessWidget {
  final String description;
  final _UndoScope scope;
  final bool hasOverrides;
  final AppTokens tokens;
  final VoidCallback onResync;
  final VoidCallback onCycleScope;

  const _UndoWindowDescription({
    required this.description,
    required this.scope,
    required this.hasOverrides,
    required this.tokens,
    required this.onResync,
    required this.onCycleScope,
  });

  @override
  Widget build(BuildContext context) {
    final mutedStyle = TextStyle(
      color: tokens.textMuted.withValues(alpha: 0.65),
      fontSize: 10.5,
      height: 1.4,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(description, style: mutedStyle)),
        const SizedBox(width: 8),
        // Tiny scope chip — makes the y-drag anchor visible AND
        // serves as a tap-to-cycle alternative for folks who don't
        // think to drag vertically on a slider.
        _ScopeChip(
          scope: scope,
          tokens: tokens,
          onTap: onCycleScope,
        ),
        if (hasOverrides) ...[
          const SizedBox(width: 6),
          _SyncGlyph(tokens: tokens, onTap: onResync),
        ],
      ],
    );
  }
}

/// Tiny chip showing the current scope. Tap to cycle forward — a
/// faster path than the y-drag on the stepper when the user wants to
/// jump through a few scopes quickly. The y-drag is still the primary
/// gesture; the chip is the click-only alternative.
class _ScopeChip extends StatelessWidget {
  final _UndoScope scope;
  final AppTokens tokens;
  final VoidCallback onTap;
  const _ScopeChip({
    required this.scope,
    required this.tokens,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    return Tooltip(
      message: 'Click to cycle scope · drag up/down on the slider too',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: muted, width: 0.8),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              scope.chipLabel,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 9,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny sync glyph. Tap to clear all per-kind overrides so every
/// action falls back to the default window again. Tooltip explains.
class _SyncGlyph extends StatelessWidget {
  final AppTokens tokens;
  final VoidCallback onTap;
  const _SyncGlyph({required this.tokens, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Reset every action to use the default window',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Icon(
            Icons.sync,
            size: 12,
            color: tokens.accentBright.withValues(alpha: 0.85),
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
                        fontFamily: AppFonts.mono,
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

/// Mini-viz for "remember work in progress." A little note-card with
/// content lines and a tab-flag that reads as "kept for later" when ON.
/// When OFF the card is blank and the flag is gone — the draft was not
/// saved. Mirrors the on/off contract of the cabinet + blame indicators.
class _WipMemoryMiniIndicator extends StatelessWidget {
  final bool remembered;
  final AppTokens tokens;
  const _WipMemoryMiniIndicator({
    required this.remembered,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dur = context.motion(const Duration(milliseconds: 220));
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    final active = tokens.accentBright;
    final borderColor = remembered ? active : muted;
    return SizedBox(
      width: 32,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The note-card itself — a small rounded rectangle centered
          // in the slot. Border color shifts with the active state so
          // the whole card reads as "lit" when remembered.
          Positioned(
            top: 3,
            bottom: 3,
            left: 3,
            right: 6,
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: remembered
                    ? active.withValues(alpha: 0.10)
                    : Colors.transparent,
                border: Border.all(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Two content lines inside the card — they appear only when
          // remembered. Absent = blank card = nothing saved.
          Positioned(
            top: 7,
            left: 6,
            right: 10,
            child: AnimatedOpacity(
              duration: dur,
              curve: Curves.easeOutCubic,
              opacity: remembered ? 1.0 : 0.0,
              child: Container(height: 1, color: active),
            ),
          ),
          Positioned(
            top: 12,
            left: 6,
            right: 14,
            child: AnimatedOpacity(
              duration: dur,
              curve: Curves.easeOutCubic,
              opacity: remembered ? 1.0 : 0.0,
              child: Container(height: 1, color: active),
            ),
          ),
          // Bookmark tab — a small flag hanging off the card's top-
          // right corner. Present iff remembered; scales in so the
          // "kept" state reads as a deliberate bookmark action.
          Positioned(
            top: 0,
            right: 4,
            child: AnimatedScale(
              duration: dur,
              curve: Curves.easeOutCubic,
              scale: remembered ? 1.0 : 0.0,
              alignment: Alignment.topCenter,
              child: Container(
                width: 4,
                height: 7,
                decoration: BoxDecoration(
                  color: active,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(1),
                    bottomRight: Radius.circular(1),
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

/// Mini-viz for "logo animates when tabbed out." Two nested squares
/// (inner rotated 45° to read as a cube/hypercube projection). When ON,
/// the pair slowly rotates continuously — the indicator itself demos
/// the setting. When OFF, frozen at 0° in a muted color.
class _LogoMotionMiniIndicator extends StatefulWidget {
  final bool animates;
  final AppTokens tokens;
  const _LogoMotionMiniIndicator({
    required this.animates,
    required this.tokens,
  });

  @override
  State<_LogoMotionMiniIndicator> createState() =>
      _LogoMotionMiniIndicatorState();
}

class _LogoMotionMiniIndicatorState extends State<_LogoMotionMiniIndicator>
    with SingleTickerProviderStateMixin, WindowAwakeGuardedMixin {
  // Authored base duration — actual runtime rotation period is
  // `_authoredPeriod / motionRate` so the indicator literally demos
  // the preference it represents. At rate=1 it's 4s/revolution;
  // at rate=2 it's 2s/rev; at rate=0.5 it's 8s; at rate≈0 it halts.
  static const Duration _authoredPeriod = Duration(seconds: 4);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _authoredPeriod,
  );

  PreferencesState? _prefs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesState>();
    if (!identical(_prefs, prefs)) {
      _prefs?.removeListener(_onPrefsChanged);
      _prefs = prefs;
      prefs.addListener(_onPrefsChanged);
    }
    _syncAnimation();
  }

  @override
  void onWindowAwakeChanged() => _onPrefsChanged();

  @override
  void didUpdateWidget(covariant _LogoMotionMiniIndicator old) {
    super.didUpdateWidget(old);
    _syncAnimation();
  }

  void _onPrefsChanged() {
    if (mounted) _syncAnimation();
  }

  void _syncAnimation() {
    final rate = _prefs?.motionRate ?? 1.0;
    final awake = WindowActivity.instance.awake;
    final reduce = rate <= kMotionRateOff || !awake;
    if (!reduce) {
      // Scale period inversely with rate so higher rate = faster spin.
      final periodUs =
          (_authoredPeriod.inMicroseconds / rate).round().clamp(
                const Duration(milliseconds: 120).inMicroseconds,
                const Duration(seconds: 60).inMicroseconds,
              );
      _ctrl.duration = Duration(microseconds: periodUs);
    }
    if (widget.animates && !reduce) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      if (_ctrl.isAnimating) _ctrl.stop();
      if (reduce) _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.tokens.textMuted.withValues(alpha: 0.55);
    final active = widget.tokens.accentBright;
    final color = widget.animates ? active : muted;
    return SizedBox(
      width: 32,
      height: 20,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: SizedBox(
                width: 14,
                height: 14,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer square outline.
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        border: Border.all(color: color, width: 1),
                      ),
                    ),
                    // Inner diamond — an offset-rotated square suggesting
                    // a hypercube's nested-faces projection.
                    Transform.rotate(
                      angle: math.pi / 4,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          border: Border.all(color: color, width: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Mini-viz for "auto select new changes." Two file rows stacked: the
/// top one (existing file) is always checked; the bottom one (the
/// "new" arrival) becomes checked when ON to show the auto-select
/// behavior, unchecked when OFF.
class _AutoSelectMiniIndicator extends StatelessWidget {
  final bool active;
  final AppTokens tokens;
  const _AutoSelectMiniIndicator({
    required this.active,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dur = context.motion(const Duration(milliseconds: 240));
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    final accent = tokens.accentBright;
    Widget row({required bool checked, required bool isNew}) {
      final boxColor = checked ? accent : Colors.transparent;
      final borderColor = checked ? accent : muted;
      final lineColor =
          checked ? accent.withValues(alpha: 0.75) : muted;
      return Row(
        children: [
          AnimatedContainer(
            duration: dur,
            curve: Curves.easeOutCubic,
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: boxColor,
              border: Border.all(color: borderColor, width: 0.8),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              height: 1,
              color: lineColor,
            ),
          ),
          if (isNew) ...[
            const SizedBox(width: 2),
            // Tiny sparkle mark indicating "new." Always visible so
            // the bottom row reads as the new arrival regardless of
            // whether it's been auto-selected.
            Text(
              '+',
              style: TextStyle(
                color: active ? accent : muted,
                fontSize: 8,
                height: 1.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      );
    }
    return SizedBox(
      width: 32,
      height: 20,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          row(checked: true, isNew: false),
          const SizedBox(height: 4),
          row(checked: active, isNew: true),
        ],
      ),
    );
  }
}

/// Mini-viz for "I hate AI." A tiny chip glyph (meant to read as a
/// silicon model chip). When HIDDEN is on, a diagonal stroke crosses
/// the chip in muted ink — the silicon is "off." When HIDDEN is off,
/// the chip is intact + accent-coloured with faint leg-dots glowing,
/// matching the app's other on-state indicator voices.
class _AiHiddenMiniIndicator extends StatelessWidget {
  final bool hidden;
  final AppTokens tokens;
  const _AiHiddenMiniIndicator({
    required this.hidden,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dur = context.motion(const Duration(milliseconds: 240));
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    final accent = tokens.accentBright;
    final chipColor = hidden ? muted : accent;
    return SizedBox(
      width: 32,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Chip body — rounded rect center.
          Positioned(
            left: 8,
            top: 5,
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              width: 16,
              height: 10,
              decoration: BoxDecoration(
                color: hidden
                    ? Colors.transparent
                    : accent.withValues(alpha: 0.14),
                border: Border.all(color: chipColor, width: 1),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          // Chip legs — three tiny dots on each side. Faded when
          // hidden, accent when active.
          for (final y in const [7.0, 11.0])
            Positioned(
              left: 4,
              top: y,
              child: Container(
                width: 4,
                height: 1,
                color: chipColor,
              ),
            ),
          for (final y in const [7.0, 11.0])
            Positioned(
              left: 24,
              top: y,
              child: Container(
                width: 4,
                height: 1,
                color: chipColor,
              ),
            ),
          // Strike — a diagonal line crossing the chip when hidden.
          // Animates in / out with opacity.
          Positioned(
            left: 3,
            top: 3,
            child: AnimatedOpacity(
              duration: dur,
              curve: Curves.easeOutCubic,
              opacity: hidden ? 1.0 : 0.0,
              child: Transform.rotate(
                angle: -math.pi / 5,
                alignment: Alignment.center,
                child: Container(
                  width: 26,
                  height: 1.5,
                  color: muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini-viz for "fetch online issues on branch load." A tiny cloud
/// glyph with a drop falling into an issue tray beneath. When ON, the
/// drop is present and colored accent; when OFF, the cloud is there
/// but empty — nothing's flowing down.
class _OnlineFetchMiniIndicator extends StatelessWidget {
  final bool active;
  final AppTokens tokens;
  const _OnlineFetchMiniIndicator({
    required this.active,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final dur = context.motion(const Duration(milliseconds: 240));
    final muted = tokens.textMuted.withValues(alpha: 0.55);
    final accent = tokens.accentBright;
    final cloudColor = active ? accent : muted;
    return SizedBox(
      width: 32,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cloud — two overlapping circles + a capping rounded rect
          // along the bottom, all outlined. Reads as a cloud at 32×20
          // without needing a vector asset.
          Positioned(
            top: 2,
            left: 6,
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cloudColor, width: 1),
              ),
            ),
          ),
          Positioned(
            top: 1,
            left: 10,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cloudColor, width: 1),
              ),
            ),
          ),
          Positioned(
            top: 4,
            left: 5,
            child: Container(
              width: 15,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border.all(color: cloudColor, width: 1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(2),
                  bottomRight: Radius.circular(2),
                ),
              ),
            ),
          ),
          // Drop falling from cloud to tray — opacity is the on/off
          // signal so the tray still reads as a destination even when
          // nothing's flowing.
          Positioned(
            top: 10,
            left: 12,
            child: AnimatedOpacity(
              duration: dur,
              curve: Curves.easeOutCubic,
              opacity: active ? 1.0 : 0.0,
              child: Container(
                width: 2,
                height: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
          // Issue tray — a small rounded rect at the bottom. Fills
          // with accent when ON, outlined when OFF.
          Positioned(
            left: 4,
            bottom: 2,
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              width: 17,
              height: 5,
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                border: Border.all(color: cloudColor, width: 1),
                borderRadius: BorderRadius.circular(1.5),
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
    final guardrailStage = context.select<PreferencesState, int>(
      (s) => s.guardrailStage,
    );
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
                        fontFamily: AppFonts.mono,
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
                fontFamily: AppFonts.mono,
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

/// Section wrapper that paints a brief border pulse when [flash] is
/// non-null and animating. Used by the deep-link flow to confirm a
/// scroll-to-section landing — the user sees the section header
/// briefly outlined in accent so the focus is unmissable.
///
/// The pulse fades from accent at full alpha to transparent over the
/// controller's duration, so the visual disturbance is short-lived.
class _SectionFlashFrame extends StatelessWidget {
  final Widget child;
  final Animation<double>? flash;

  const _SectionFlashFrame({
    super.key,
    required this.child,
    this.flash,
  });

  @override
  Widget build(BuildContext context) {
    final f = flash;
    if (f == null) return child;
    final t = context.tokens;
    return AnimatedBuilder(
      animation: f,
      builder: (context, c) {
        // Pulse: ramps in fast, fades out slow. sin(pi * t) gives a
        // 0→1→0 envelope; raised to 0.7 to keep the peak visible
        // longer than a pure sine.
        final v = f.value;
        final env = math.pow(math.sin(math.pi * v), 0.7).toDouble();
        final alpha = (0.55 * env).clamp(0.0, 1.0);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: t.accentBright.withValues(alpha: alpha),
              width: 1.5,
            ),
          ),
          child: c,
        );
      },
      child: child,
    );
  }
}

/// External Tools settings card. Top: preset one-click adds plus a
/// blank "custom" preset for users who want to start from scratch.
/// Below: editable list of currently-configured tools — each row
/// owns its own TextEditingControllers and persists changes via
/// [ExternalToolsState].
class _ExternalToolsCard extends StatelessWidget {
  const _ExternalToolsCard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ExternalToolsState>();
    final detection = context.watch<ToolDetectionState>();
    final t = context.tokens;
    final tools = state.tools;
    // Only show presets that are (a) actually installed on PATH AND
    // (b) not already configured. Dedup uses label (not just
    // executable) because multiple presets can share the same
    // executable with different args (e.g. the git-based "eldritch"
    // operations all use `git` but have different labels/args).
    final addedLabels = <String>{
      for (final tool in tools) tool.label.trim().toLowerCase(),
    };
    final addedExecutables = <String>{
      for (final tool in tools) tool.executable.trim().toLowerCase(),
    };
    final availablePresets = detection.isLoaded
        ? [
            for (final p in ExternalToolPresets.all)
              if (detection.has(p.executable) &&
                  !addedLabels.contains(
                      p.label.replaceFirst('+ ', '').toLowerCase()) &&
                  // For unique-executable presets (editors, AI tools),
                  // also suppress if the executable is already added
                  // under a different label (manual rename). Git-based
                  // presets share `git` as executable, so they skip
                  // this check — each is differentiated by label.
                  (p.executable == 'git' ||
                      !addedExecutables.contains(
                          p.executable.toLowerCase())))
                p,
          ]
        : <ExternalToolPreset>[];
    return _StateCard(
      title: 'External Tools',
      summary:
          'Right-click a project in the sidebar to open it with one of these. Args use {path} for the project folder.',
      wide: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!detection.isLoaded)
            Text(
              'Detecting installed tools…',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            )
          else
            ..._buildPresetShelves(context, availablePresets, t),
          if (detection.isLoaded && availablePresets.isEmpty && tools.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'All known presets are already added. Use “+ Custom” to add more.',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
          if (tools.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final tool in tools) ...[
              _ExternalToolRow(
                key: ValueKey(tool.id),
                tool: tool,
              ),
              const SizedBox(height: 8),
            ],
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'No tools configured yet. Add one above.',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  static const _categoryLabels = {
    ExternalToolCategory.ai: 'ai',
    ExternalToolCategory.editors: 'editors',
    ExternalToolCategory.explore: 'explore',
    ExternalToolCategory.ops: 'ops',
    ExternalToolCategory.gitOps: 'git ops',
  };

  static List<Widget> _buildPresetShelves(
    BuildContext context,
    List<ExternalToolPreset> available,
    dynamic t,
  ) {
    final grouped = <ExternalToolCategory, List<ExternalToolPreset>>{};
    for (final p in available) {
      (grouped[p.category] ??= []).add(p);
    }
    final accent = (t.accentBright as Color).withValues(alpha: 0.40);
    final shelves = <Widget>[];
    for (final cat in ExternalToolCategory.values) {
      final presets = grouped[cat];
      if (presets == null || presets.isEmpty) continue;
      if (shelves.isNotEmpty) shelves.add(const SizedBox(height: 10));
      shelves.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _categoryLabels[cat] ?? cat.name,
                style: TextStyle(
                  color: t.accentBright,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
      shelves.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in presets)
              _GhostMiniButton(
                label: preset.label,
                onTap: () => context
                    .read<ExternalToolsState>()
                    .add(preset.build()),
              ),
          ],
        ),
      );
    }
    shelves.add(const SizedBox(height: 10));
    shelves.add(
      _GhostMiniButton(
        label: '+ Custom',
        onTap: () => context
            .read<ExternalToolsState>()
            .add(ExternalToolPresets.blank()),
      ),
    );
    return shelves;
  }
}

/// Single editable tool row. Manages its own text controllers + a
/// debounced persist so typing doesn't fire a disk write on every
/// keystroke. Owned controllers are seeded from the [tool] passed in
/// and reseeded whenever an external mutation changes the bound id.
class _ExternalToolRow extends StatefulWidget {
  final ExternalTool tool;
  const _ExternalToolRow({super.key, required this.tool});

  @override
  State<_ExternalToolRow> createState() => _ExternalToolRowState();
}

class _ExternalToolRowState extends State<_ExternalToolRow> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _execCtrl;
  late final TextEditingController _argsCtrl;
  Timer? _persistDebounce;
  bool _testInFlight = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.tool.label);
    _execCtrl = TextEditingController(text: widget.tool.executable);
    _argsCtrl =
        TextEditingController(text: _argsToDisplay(widget.tool.args));
  }

  static String _argsToDisplay(List<String> args) =>
      argsToDisplayForRoundTrip(args);

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _labelCtrl.dispose();
    _execCtrl.dispose();
    _argsCtrl.dispose();
    super.dispose();
  }

  /// Debounced persist. Fires 500ms after the last keystroke so the
  /// user can finish typing before the disk write hits.
  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), _persistNow);
  }

  Future<void> _persistNow() async {
    if (!mounted) return;
    final next = widget.tool.copyWith(
      label: _labelCtrl.text,
      executable: _execCtrl.text,
      args: _parseArgs(_argsCtrl.text),
    );
    await context
        .read<ExternalToolsState>()
        .update(widget.tool.id, next);
  }

  List<String> _parseArgs(String raw) => parseArgsForRoundTrip(raw);

  Future<void> _runTest() async {
    if (_testInFlight) return;
    final repoPath = context.read<RepositoryState>().activePath;
    if (repoPath == null) return;
    setState(() => _testInFlight = true);
    final args = _parseArgs(_argsCtrl.text)
        .map((a) => a.replaceAll('{path}', repoPath))
        .toList();
    try {
      if (widget.tool.mode == ToolLaunchMode.detached) {
        await runDetached(
          executable: _execCtrl.text.trim(),
          args: args,
          workingDirectory: repoPath,
        );
      } else {
        await runInTerminal(
          executable: _execCtrl.text.trim(),
          args: args,
          workingDirectory: repoPath,
        );
      }
    } catch (_) {
      // Failure is silent — same rationale as system_paths.dart.
    } finally {
      if (mounted) setState(() => _testInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label field — narrow.
        SizedBox(
          width: 120,
          child: AppTextField(
            controller: _labelCtrl,
            hintText: 'Name',
            onChanged: (_) => _schedulePersist(),
          ),
        ),
        const SizedBox(width: 6),
        // Executable field — narrow + monospace for command names.
        SizedBox(
          width: 110,
          child: AppTextField(
            controller: _execCtrl,
            hintText: 'command',
            mono: true,
            onChanged: (_) => _schedulePersist(),
          ),
        ),
        const SizedBox(width: 6),
        // Args field — wide, monospace, takes remaining space.
        Expanded(
          child: AppTextField(
            controller: _argsCtrl,
            hintText: '{path}',
            mono: true,
            onChanged: (_) => _schedulePersist(),
          ),
        ),
        const SizedBox(width: 6),
        // Mode toggle — segmented control. Two values fit a small chip.
        _ToolModeToggle(
          mode: widget.tool.mode,
          onChanged: (m) => context
              .read<ExternalToolsState>()
              .update(
                widget.tool.id,
                widget.tool.copyWith(mode: m),
              ),
        ),
        const SizedBox(width: 6),
        _GhostMiniButton(
          label: _testInFlight ? '…' : 'test',
          onTap: _testInFlight ? null : () => unawaited(_runTest()),
        ),
        const SizedBox(width: 4),
        // Delete affordance — the only destructive action on the row.
        // Tooltip + close icon to match the "Forget this project"
        // affordance in the project context menu.
        Tooltip(
          message: 'Remove tool',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context
                  .read<ExternalToolsState>()
                  .remove(widget.tool.id),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: t.textFaint,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-state toggle for [ToolLaunchMode]. Compact — labels are short
/// and the chip lives in a horizontal tool row alongside several
/// other inputs.
class _ToolModeToggle extends StatelessWidget {
  final ToolLaunchMode mode;
  final ValueChanged<ToolLaunchMode> onChanged;

  const _ToolModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget seg(ToolLaunchMode value, String label) {
      final active = mode == value;
      return GestureDetector(
        onTap: active ? null : () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.snap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? t.accentBright.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? t.textStrong : t.textMuted,
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.chromeBorder.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ToolLaunchMode.newTerminal, 'terminal'),
          seg(ToolLaunchMode.detached, 'detached'),
        ],
      ),
    );
  }
}

/// Round-trip safe display of [args]. Tokens containing whitespace
/// are wrapped in double quotes; literal `"` and `\` inside any
/// quoted token are backslash-escaped so [parseArgsForRoundTrip] can
/// decode them back to their original form. Without that escaping a
/// persisted arg like `--msg="hello world"` would render as
/// `"--msg="hello world""` and the next parse would silently lose
/// the inner quotes — a contract violation since the field exists
/// to edit a list of strings, not interpret shell syntax.
@visibleForTesting
String argsToDisplayForRoundTrip(List<String> args) {
  return args.map((a) {
    if (RegExp(r'\s|"|\\').hasMatch(a)) {
      // Escape backslashes first so the quote-escape we add next
      // doesn't get its own backslash re-escaped on re-parse.
      final escaped = a.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '"$escaped"';
    }
    return a;
  }).join(' ');
}

/// Parse the args field — space-separated tokens, with simple
/// double-quote support so `"a b"` becomes one arg. Inside a quoted
/// span, `\\` decodes to `\` and `\"` decodes to `"`, matching the
/// escaping [argsToDisplayForRoundTrip] produces. Other backslashes
/// are passed through untouched so the common `--path=C:\foo\bar`
/// style of arg doesn't need any escaping from the user. Not full
/// shell quoting — the field exists at edit time only; at launch
/// time argv is already typed.
@visibleForTesting
List<String> parseArgsForRoundTrip(String raw) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuote = false;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (inQuote && ch == r'\' && i + 1 < raw.length) {
      final next = raw[i + 1];
      if (next == '"' || next == r'\') {
        buf.write(next);
        i++;
        continue;
      }
    }
    if (ch == '"') {
      inQuote = !inQuote;
      continue;
    }
    if (ch == ' ' && !inQuote) {
      if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}
