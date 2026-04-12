import 'package:flutter/foundation.dart';

import '../backend/settings_store.dart';
import '../diagnostics/diagnostics_state.dart';

class PreferencesState extends ChangeNotifier {
  PreferencesState();

  static const List<double> _guardrailStageValues = [
    0.125,
    0.375,
    0.625,
    0.875,
  ];

  double _guardrailValue = 0.5;
  String _updateChannel = 'stable';
  bool _crashReportingEnabled = false;
  bool _aiReadOnlyDefault = true;
  bool _logoAnimatesWhenUnfocused = true;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  double get guardrailValue => _guardrailValue;
  int get guardrailStage => _guardrailStageFromValue(_guardrailValue);
  String get updateChannel => _updateChannel;
  bool get crashReportingEnabled => _crashReportingEnabled;
  bool get aiReadOnlyDefault => _aiReadOnlyDefault;
  bool get logoAnimatesWhenUnfocused => _logoAnimatesWhenUnfocused;

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final settings = await SettingsStore.load();
    _guardrailValue = _normalizeGuardrailValue(settings.guardrailValue);
    _updateChannel = _normalizeUpdateChannel(settings.updateChannel);
    _crashReportingEnabled = settings.crashReportingEnabled;
    _aiReadOnlyDefault = settings.aiReadOnlyDefault;
    _logoAnimatesWhenUnfocused = settings.logoAnimatesWhenUnfocused;
    _loaded = true;
    notifyListeners();
  }

  String get guardrailProfile {
    switch (guardrailStage) {
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

  Future<void> setGuardrailStage(int stage) async {
    final normalizedStage = stage.clamp(0, _guardrailStageValues.length - 1);
    final value = _guardrailStageValues[normalizedStage];
    if ((_guardrailValue - value).abs() < 0.0001) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'start',
      command: 'update_ai_guardrail',
    );
    try {
      _guardrailValue = value;
      final settings = await SettingsStore.load();
      await SettingsStore.persist(
        AppSettingsSnapshot(
          guardrailValue: _guardrailValue,
          aiReadOnlyDefault: _aiReadOnlyDefault,
          logoAnimatesWhenUnfocused: _logoAnimatesWhenUnfocused,
          telemetryRetentionDays: settings.telemetryRetentionDays,
          telemetryRetentionMb: settings.telemetryRetentionMb,
          updateChannel: settings.updateChannel,
          crashReportingEnabled: settings.crashReportingEnabled,
          themeId: settings.themeId,
          keybindingProfile: settings.keybindingProfile,
          sidebarWidthPx: settings.sidebarWidthPx,
          sidebarPosition: settings.sidebarPosition,
          utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
          utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        ),
      );
      notifyListeners();
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'success',
        command: 'update_ai_guardrail',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
      );
      await DiagnosticsState.instance.recordCommandLatency(
        command: 'update_ai_guardrail',
        ok: true,
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
      );
    } catch (error) {
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: 'update_ai_guardrail',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
        message: error.toString(),
      );
      await DiagnosticsState.instance.recordCommandLatency(
        command: 'update_ai_guardrail',
        ok: false,
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
      );
      rethrow;
    }
  }

  Future<void> setUpdateChannel(String value) async {
    final normalized = _normalizeUpdateChannel(value);
    if (_updateChannel == normalized) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'start',
      command: 'update_update_channel',
    );
    try {
      _updateChannel = normalized;
      final settings = await SettingsStore.load();
      await SettingsStore.persist(
        AppSettingsSnapshot(
          guardrailValue: settings.guardrailValue,
          aiReadOnlyDefault: _aiReadOnlyDefault,
          logoAnimatesWhenUnfocused: _logoAnimatesWhenUnfocused,
          telemetryRetentionDays: settings.telemetryRetentionDays,
          telemetryRetentionMb: settings.telemetryRetentionMb,
          updateChannel: _updateChannel,
          crashReportingEnabled: settings.crashReportingEnabled,
          themeId: settings.themeId,
          keybindingProfile: settings.keybindingProfile,
          sidebarWidthPx: settings.sidebarWidthPx,
          sidebarPosition: settings.sidebarPosition,
          utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
          utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        ),
      );
      notifyListeners();
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'success',
        command: 'update_update_channel',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
      );
      await DiagnosticsState.instance.recordCommandLatency(
        command: 'update_update_channel',
        ok: true,
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
      );
    } catch (error) {
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: 'update_update_channel',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
        message: error.toString(),
      );
      await DiagnosticsState.instance.recordCommandLatency(
        command: 'update_update_channel',
        ok: false,
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
      );
      rethrow;
    }
  }

  Future<void> setCrashReportingEnabled(bool value) async {
    if (_crashReportingEnabled == value) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'start',
      command: 'update_crash_reporting',
    );
    try {
      _crashReportingEnabled = value;
      final settings = await SettingsStore.load();
      await SettingsStore.persist(
        AppSettingsSnapshot(
          guardrailValue: settings.guardrailValue,
          aiReadOnlyDefault: _aiReadOnlyDefault,
          logoAnimatesWhenUnfocused: _logoAnimatesWhenUnfocused,
          telemetryRetentionDays: settings.telemetryRetentionDays,
          telemetryRetentionMb: settings.telemetryRetentionMb,
          updateChannel: settings.updateChannel,
          crashReportingEnabled: _crashReportingEnabled,
          themeId: settings.themeId,
          keybindingProfile: settings.keybindingProfile,
          sidebarWidthPx: settings.sidebarWidthPx,
          sidebarPosition: settings.sidebarPosition,
          utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
          utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        ),
      );
      notifyListeners();
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'success',
        command: 'update_crash_reporting',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
      );
      await DiagnosticsState.instance.recordCommandLatency(
        command: 'update_crash_reporting',
        ok: true,
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
      );
    } catch (error) {
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: 'update_crash_reporting',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
        message: error.toString(),
      );
      await DiagnosticsState.instance.recordCommandLatency(
        command: 'update_crash_reporting',
        ok: false,
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
      );
      rethrow;
    }
  }

  Future<void> setAiReadOnlyDefault(bool value) async {
    if (_aiReadOnlyDefault == value) {
      return;
    }

    _aiReadOnlyDefault = value;
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      AppSettingsSnapshot(
        guardrailValue: settings.guardrailValue,
        aiReadOnlyDefault: _aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: _logoAnimatesWhenUnfocused,
        telemetryRetentionDays: settings.telemetryRetentionDays,
        telemetryRetentionMb: settings.telemetryRetentionMb,
        updateChannel: settings.updateChannel,
        crashReportingEnabled: settings.crashReportingEnabled,
        themeId: settings.themeId,
        keybindingProfile: settings.keybindingProfile,
        sidebarWidthPx: settings.sidebarWidthPx,
        sidebarPosition: settings.sidebarPosition,
        utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
        utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
      ),
    );
    notifyListeners();
  }

  Future<void> setLogoAnimatesWhenUnfocused(bool value) async {
    if (_logoAnimatesWhenUnfocused == value) {
      return;
    }

    _logoAnimatesWhenUnfocused = value;
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      AppSettingsSnapshot(
        guardrailValue: settings.guardrailValue,
        aiReadOnlyDefault: _aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: _logoAnimatesWhenUnfocused,
        telemetryRetentionDays: settings.telemetryRetentionDays,
        telemetryRetentionMb: settings.telemetryRetentionMb,
        updateChannel: settings.updateChannel,
        crashReportingEnabled: settings.crashReportingEnabled,
        themeId: settings.themeId,
        keybindingProfile: settings.keybindingProfile,
        sidebarWidthPx: settings.sidebarWidthPx,
        sidebarPosition: settings.sidebarPosition,
        utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
        utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
      ),
    );
    notifyListeners();
  }

  int _guardrailStageFromValue(double value) {
    if (value < 0.25) {
      return 0;
    }
    if (value <= 0.5) {
      return 1;
    }
    if (value < 0.75) {
      return 2;
    }
    return 3;
  }

  double _normalizeGuardrailValue(double value) {
    if (!value.isFinite) {
      return 0.5;
    }
    return value.clamp(0.0, 1.0);
  }

  String _normalizeUpdateChannel(String value) {
    return value.trim().toLowerCase() == 'beta' ? 'beta' : 'stable';
  }
}
