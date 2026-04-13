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
  final bool reduceMotion;
  /// Last-known phase (0..1) of the reduce-motion toggle's pulse wave.
  /// Persisted so the bump resumes from where it was frozen on the
  /// previous session instead of snapping back to zero on restart.
  final double reduceMotionPhase;
  final bool stashCabinetDefaultExpanded;
  final bool instantBlameHover;
  /// Change list sort guide: 'related' | 'alphabetical' | 'impact'.
  final String fileSortGuide;
  /// When true, the active sort guide is applied in reverse per its own
  /// notion of "opposite". See `FileCoupling.clusterFiles(inverted:)`.
  final bool fileSortInverted;
  /// Commit-message format preferences. Consumed by the AI prompt
  /// builder and by the manual commit composer to shape defaults.
  final String commitStructure; // 'title_body' | 'title_only' | 'freeform'
  final String commitVoice;     // 'verb_led' | 'descriptive' | 'narrative'
  final String commitCoverage;  // 'essentials' | 'balanced' | 'everything'

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
    required this.reduceMotion,
    required this.reduceMotionPhase,
    required this.stashCabinetDefaultExpanded,
    required this.instantBlameHover,
    required this.fileSortGuide,
    required this.fileSortInverted,
    required this.commitStructure,
    required this.commitVoice,
    required this.commitCoverage,
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
        'reduceMotion': reduceMotion,
        'reduceMotionPhase': reduceMotionPhase,
        'stashCabinetDefaultExpanded': stashCabinetDefaultExpanded,
        'instantBlameHover': instantBlameHover,
        'fileSortGuide': fileSortGuide,
        'fileSortInverted': fileSortInverted,
        'commitStructure': commitStructure,
        'commitVoice': commitVoice,
        'commitCoverage': commitCoverage,
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
        reduceMotion: false,
        reduceMotionPhase: 0.0,
        stashCabinetDefaultExpanded: false,
        instantBlameHover: false,
        fileSortGuide: 'related',
        fileSortInverted: false,
        commitStructure: 'title_body',
        commitVoice: 'verb_led',
        commitCoverage: 'balanced',
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
      reduceMotion: SettingsStore._boolOr(
        json['reduceMotion'],
        defaults.reduceMotion,
      ),
      reduceMotionPhase: SettingsStore._doubleOr(
        json['reduceMotionPhase'],
        defaults.reduceMotionPhase,
      ).clamp(0.0, 1.0),
      stashCabinetDefaultExpanded: SettingsStore._boolOr(
        json['stashCabinetDefaultExpanded'],
        defaults.stashCabinetDefaultExpanded,
      ),
      instantBlameHover: SettingsStore._boolOr(
        json['instantBlameHover'],
        defaults.instantBlameHover,
      ),
      fileSortGuide: SettingsStore._normalizeSortGuide(
        SettingsStore._stringOr(
          json['fileSortGuide'],
          defaults.fileSortGuide,
        ),
      ),
      fileSortInverted: SettingsStore._boolOr(
        json['fileSortInverted'],
        defaults.fileSortInverted,
      ),
      commitStructure: SettingsStore._normalizeCommitStructure(
        SettingsStore._stringOr(
          json['commitStructure'],
          defaults.commitStructure,
        ),
      ),
      commitVoice: SettingsStore._normalizeCommitVoice(
        SettingsStore._stringOr(
          json['commitVoice'],
          defaults.commitVoice,
        ),
      ),
      commitCoverage: SettingsStore._normalizeCommitCoverage(
        SettingsStore._stringOr(
          json['commitCoverage'],
          defaults.commitCoverage,
        ),
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

  static String _normalizeSortGuide(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'alphabetical' || v == 'impact') return v;
    return 'related';
  }

  static String _normalizeCommitStructure(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'title_only' || v == 'freeform') return v;
    return 'title_body';
  }

  static String _normalizeCommitVoice(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'descriptive' || v == 'narrative') return v;
    return 'verb_led';
  }

  static String _normalizeCommitCoverage(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'essentials' || v == 'everything') return v;
    return 'balanced';
  }
}
