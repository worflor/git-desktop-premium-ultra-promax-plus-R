import 'dart:convert';
import 'dart:io';

import 'storage_paths.dart';

class AppSettingsSnapshot {
  final double guardrailValue;
  final bool aiReadOnlyDefault;
  final bool logoAnimatesWhenUnfocused;
  final int telemetryRetentionDays;
  final int telemetryRetentionMb;
  final String updateChannel;
  final bool crashReportingEnabled;
  final String themeId;
  final String keybindingProfile;
  final int sidebarWidthPx;
  final String sidebarPosition;
  final bool utilityDrawerDefaultExpanded;
  final int utilityDrawerHeightPx;
  final bool autoExpandOperationLogs;

  const AppSettingsSnapshot({
    required this.guardrailValue,
    required this.aiReadOnlyDefault,
    required this.logoAnimatesWhenUnfocused,
    required this.telemetryRetentionDays,
    required this.telemetryRetentionMb,
    required this.updateChannel,
    required this.crashReportingEnabled,
    required this.themeId,
    required this.keybindingProfile,
    required this.sidebarWidthPx,
    required this.sidebarPosition,
    required this.utilityDrawerDefaultExpanded,
    required this.utilityDrawerHeightPx,
    required this.autoExpandOperationLogs,
  });

  Map<String, dynamic> toJson() => {
        'guardrailValue': guardrailValue,
        'aiReadOnlyDefault': aiReadOnlyDefault,
        'logoAnimatesWhenUnfocused': logoAnimatesWhenUnfocused,
        'telemetryRetentionDays': telemetryRetentionDays,
        'telemetryRetentionMb': telemetryRetentionMb,
        'updateChannel': updateChannel,
        'crashReportingEnabled': crashReportingEnabled,
        'themeId': themeId,
        'keybindingProfile': keybindingProfile,
        'sidebarWidthPx': sidebarWidthPx,
        'sidebarPosition': sidebarPosition,
        'utilityDrawerDefaultExpanded': utilityDrawerDefaultExpanded,
        'utilityDrawerHeightPx': utilityDrawerHeightPx,
        'autoExpandOperationLogs': autoExpandOperationLogs,
      };

  factory AppSettingsSnapshot.defaults() => const AppSettingsSnapshot(
        guardrailValue: 0.5,
        aiReadOnlyDefault: true,
        logoAnimatesWhenUnfocused: true,
        telemetryRetentionDays: 30,
        telemetryRetentionMb: 128,
        updateChannel: 'stable',
        crashReportingEnabled: false,
        themeId: 'aether',
        keybindingProfile: 'classic',
        sidebarWidthPx: 188,
        sidebarPosition: 'left',
        utilityDrawerDefaultExpanded: false,
        utilityDrawerHeightPx: 180,
        autoExpandOperationLogs: false,
      );

  factory AppSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettingsSnapshot.defaults();
    return AppSettingsSnapshot(
      guardrailValue: SettingsStore._doubleOr(
        json['guardrailValue'],
        defaults.guardrailValue,
      ).clamp(0.0, 1.0),
      aiReadOnlyDefault: SettingsStore._boolOr(
        json['aiReadOnlyDefault'],
        defaults.aiReadOnlyDefault,
      ),
      logoAnimatesWhenUnfocused: SettingsStore._boolOr(
        json['logoAnimatesWhenUnfocused'],
        defaults.logoAnimatesWhenUnfocused,
      ),
      telemetryRetentionDays: SettingsStore._intOr(
        json['telemetryRetentionDays'],
        defaults.telemetryRetentionDays,
      ).clamp(1, 365),
      telemetryRetentionMb: SettingsStore._intOr(
        json['telemetryRetentionMb'],
        defaults.telemetryRetentionMb,
      ).clamp(16, 4096),
      updateChannel: SettingsStore._normalizeUpdateChannel(
        SettingsStore._stringOr(json['updateChannel'], defaults.updateChannel),
      ),
      crashReportingEnabled: SettingsStore._boolOr(
        json['crashReportingEnabled'],
        defaults.crashReportingEnabled,
      ),
      themeId: SettingsStore._stringOr(json['themeId'], defaults.themeId),
      keybindingProfile: SettingsStore._stringOr(
        json['keybindingProfile'],
        defaults.keybindingProfile,
      ),
      sidebarWidthPx: SettingsStore._intOr(
        json['sidebarWidthPx'],
        defaults.sidebarWidthPx,
      ).clamp(140, 380),
      sidebarPosition: SettingsStore._normalizeSidebarPosition(
        SettingsStore._stringOr(
          json['sidebarPosition'],
          defaults.sidebarPosition,
        ),
      ),
      utilityDrawerDefaultExpanded: SettingsStore._boolOr(
        json['utilityDrawerDefaultExpanded'],
        defaults.utilityDrawerDefaultExpanded,
      ),
      utilityDrawerHeightPx: SettingsStore._intOr(
        json['utilityDrawerHeightPx'],
        defaults.utilityDrawerHeightPx,
      ).clamp(120, 420),
      autoExpandOperationLogs: SettingsStore._boolOr(
        json['autoExpandOperationLogs'],
        defaults.autoExpandOperationLogs,
      ),
    );
  }
}

class SettingsStore {
  static const String _settingsFileName = 'settings.json';

  static Future<AppSettingsSnapshot> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      final defaults = AppSettingsSnapshot.defaults();
      await persist(defaults);
      return defaults;
    }

    try {
      final raw = await file.readAsString();
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        final snapshot = AppSettingsSnapshot.fromJson(parsed);
        await persist(snapshot);
        return snapshot;
      }
    } catch (_) {}

    final defaults = AppSettingsSnapshot.defaults();
    await persist(defaults);
    return defaults;
  }

  static Future<void> persist(AppSettingsSnapshot snapshot) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      flush: true,
    );
  }

  static Future<File> _settingsFile() async {
    final dir = await StoragePaths.gdpuDataDir();
    return File('${dir.path}${Platform.pathSeparator}$_settingsFileName');
  }

  static int _intOr(dynamic value, int fallback) {
    return value is num ? value.toInt() : fallback;
  }

  static double _doubleOr(dynamic value, double fallback) {
    return value is num ? value.toDouble() : fallback;
  }

  static bool _boolOr(dynamic value, bool fallback) {
    return value is bool ? value : fallback;
  }

  static String _stringOr(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  static String _normalizeUpdateChannel(String value) {
    return value.trim().toLowerCase() == 'beta' ? 'beta' : 'stable';
  }

  static String _normalizeSidebarPosition(String value) {
    return value.trim().toLowerCase() == 'right' ? 'right' : 'left';
  }
}
