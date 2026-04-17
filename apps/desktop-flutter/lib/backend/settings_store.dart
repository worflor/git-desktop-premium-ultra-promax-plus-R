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
  /// Global motion-rate scalar in [0.0, 2.0]. Multiplies animation
  /// frequency — 0.0 stops motion entirely (same as reduceMotion=true),
  /// 1.0 is normal speed, 2.0 runs animations at twice their authored Hz.
  /// Durations are scaled reciprocally: `duration / motionRate`.
  /// [reduceMotion] is retained for migration of older on-disk settings;
  /// when motionRate is absent, it's derived as `reduceMotion ? 0.0 : 1.0`.
  /// On fresh writes both fields are persisted so downgrades still work
  /// (older code reads `reduceMotion = motionRate <= 0.0`).
  final double motionRate;
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
  /// Logos XY pad — the 2D puck that describes how the user conceives
  /// "related". X ∈ [0,1] is FOLDER (0) ↔ HISTORY (1); Y ∈ [0,1] is
  /// FAR (0) ↔ NEAR (1). Defaults to 0.5/0.5 = balanced, matching the
  /// information-theoretic default weights inside Logos itself.
  final double logosPadX;
  final double logosPadY;
  /// User-customizable short name for the app, set during onboarding.
  /// The full identity is reconstructed from this single field.
  final String appShortName;
  /// True once the user has finished (or dismissed) the onboarding flow.
  /// Defaults to false — first launch with a missing key shows onboarding.
  final bool onboardingComplete;
  /// Experimental bond surface gate. Defaults false so older installs do
  /// not light up the feature accidentally.
  final bool bondExperimentEnabled;
  /// One-shot affordance bit: once the bond dock has been opened, discovery
  /// UI should stay silent.
  final bool bondDockOpenedOnce;

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
    required this.motionRate,
    required this.reduceMotionPhase,
    required this.stashCabinetDefaultExpanded,
    required this.instantBlameHover,
    required this.fileSortGuide,
    required this.fileSortInverted,
    required this.commitStructure,
    required this.commitVoice,
    required this.commitCoverage,
    required this.logosPadX,
    required this.logosPadY,
    required this.appShortName,
    required this.onboardingComplete,
    required this.bondExperimentEnabled,
    required this.bondDockOpenedOnce,
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
        'motionRate': motionRate,
        'reduceMotionPhase': reduceMotionPhase,
        'stashCabinetDefaultExpanded': stashCabinetDefaultExpanded,
        'instantBlameHover': instantBlameHover,
        'fileSortGuide': fileSortGuide,
        'fileSortInverted': fileSortInverted,
        'commitStructure': commitStructure,
        'commitVoice': commitVoice,
        'commitCoverage': commitCoverage,
        'logosPadX': logosPadX,
        'logosPadY': logosPadY,
        'appShortName': appShortName,
        'onboardingComplete': onboardingComplete,
        'bondExperimentEnabled': bondExperimentEnabled,
        'bondDockOpenedOnce': bondDockOpenedOnce,
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
        motionRate: 1.0,
        reduceMotionPhase: 0.0,
        stashCabinetDefaultExpanded: false,
        instantBlameHover: false,
        fileSortGuide: 'related',
        fileSortInverted: false,
        commitStructure: 'title_body',
        commitVoice: 'verb_led',
        commitCoverage: 'balanced',
        logosPadX: 0.5,
        logosPadY: 0.5,
        appShortName: 'Manifold',
        onboardingComplete: false,
        bondExperimentEnabled: false,
        bondDockOpenedOnce: false,
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
      // motionRate migration: if the new field is present, use it. Else
      // fall back to the legacy bool — reduceMotion=true ⇒ rate=0.0 (no
      // motion), reduceMotion=false ⇒ rate=1.0 (normal). New writes
      // always emit both fields so a downgrade still behaves correctly.
      motionRate: json.containsKey('motionRate')
          ? SettingsStore._doubleOr(json['motionRate'], defaults.motionRate)
              .clamp(0.0, 2.0)
          : (SettingsStore._boolOr(json['reduceMotion'], defaults.reduceMotion)
              ? 0.0
              : 1.0),
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
      logosPadX: SettingsStore._doubleOr(
        json['logosPadX'],
        defaults.logosPadX,
      ).clamp(0.0, 1.0),
      logosPadY: SettingsStore._doubleOr(
        json['logosPadY'],
        defaults.logosPadY,
      ).clamp(0.0, 1.0),
      appShortName: SettingsStore._normalizeAppShortName(
        SettingsStore._stringOr(json['appShortName'], defaults.appShortName),
      ),
      onboardingComplete: SettingsStore._boolOr(
        json['onboardingComplete'],
        defaults.onboardingComplete,
      ),
      bondExperimentEnabled: SettingsStore._boolOr(
        json['bondExperimentEnabled'],
        defaults.bondExperimentEnabled,
      ),
      bondDockOpenedOnce: SettingsStore._boolOr(
        json['bondDockOpenedOnce'],
        defaults.bondDockOpenedOnce,
      ),
    );
  }

  AppSettingsSnapshot copyWith({
    double? guardrailValue,
    bool? aiReadOnlyDefault,
    bool? logoAnimatesWhenUnfocused,
    int? telemetryRetentionDays,
    int? telemetryRetentionMb,
    String? updateChannel,
    bool? crashReportingEnabled,
    String? themeId,
    String? keybindingProfile,
    int? sidebarWidthPx,
    String? sidebarPosition,
    bool? utilityDrawerDefaultExpanded,
    int? utilityDrawerHeightPx,
    bool? reduceMotion,
    double? motionRate,
    double? reduceMotionPhase,
    bool? stashCabinetDefaultExpanded,
    bool? instantBlameHover,
    String? fileSortGuide,
    bool? fileSortInverted,
    String? commitStructure,
    String? commitVoice,
    String? commitCoverage,
    double? logosPadX,
    double? logosPadY,
    String? appShortName,
    bool? onboardingComplete,
    bool? bondExperimentEnabled,
    bool? bondDockOpenedOnce,
  }) {
    return AppSettingsSnapshot(
      guardrailValue: guardrailValue ?? this.guardrailValue,
      aiReadOnlyDefault: aiReadOnlyDefault ?? this.aiReadOnlyDefault,
      logoAnimatesWhenUnfocused:
          logoAnimatesWhenUnfocused ?? this.logoAnimatesWhenUnfocused,
      telemetryRetentionDays:
          telemetryRetentionDays ?? this.telemetryRetentionDays,
      telemetryRetentionMb: telemetryRetentionMb ?? this.telemetryRetentionMb,
      updateChannel: updateChannel ?? this.updateChannel,
      crashReportingEnabled:
          crashReportingEnabled ?? this.crashReportingEnabled,
      themeId: themeId ?? this.themeId,
      keybindingProfile: keybindingProfile ?? this.keybindingProfile,
      sidebarWidthPx: sidebarWidthPx ?? this.sidebarWidthPx,
      sidebarPosition: sidebarPosition ?? this.sidebarPosition,
      utilityDrawerDefaultExpanded:
          utilityDrawerDefaultExpanded ?? this.utilityDrawerDefaultExpanded,
      utilityDrawerHeightPx:
          utilityDrawerHeightPx ?? this.utilityDrawerHeightPx,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      motionRate: motionRate ?? this.motionRate,
      reduceMotionPhase: reduceMotionPhase ?? this.reduceMotionPhase,
      stashCabinetDefaultExpanded:
          stashCabinetDefaultExpanded ?? this.stashCabinetDefaultExpanded,
      instantBlameHover: instantBlameHover ?? this.instantBlameHover,
      fileSortGuide: fileSortGuide ?? this.fileSortGuide,
      fileSortInverted: fileSortInverted ?? this.fileSortInverted,
      commitStructure: commitStructure ?? this.commitStructure,
      commitVoice: commitVoice ?? this.commitVoice,
      commitCoverage: commitCoverage ?? this.commitCoverage,
      logosPadX: logosPadX ?? this.logosPadX,
      logosPadY: logosPadY ?? this.logosPadY,
      appShortName: appShortName ?? this.appShortName,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      bondExperimentEnabled:
          bondExperimentEnabled ?? this.bondExperimentEnabled,
      bondDockOpenedOnce: bondDockOpenedOnce ?? this.bondDockOpenedOnce,
    );
  }
}

class SettingsStore {
  static const String _settingsFileName = 'settings.json';

  /// Process-scoped memoised snapshot. Every per-feature state class
  /// (`ThemeState`, `PreferencesState`, `AiSettingsState`,
  /// `DiagnosticsState`) used to call [load] independently, each
  /// issuing its own disk read + JSON parse + `persist` round-trip.
  /// The file is functionally global per-process, so read once and
  /// hand the same snapshot to every caller.
  static AppSettingsSnapshot? _cached;
  static Future<AppSettingsSnapshot>? _loading;

  static Future<AppSettingsSnapshot> load() {
    final cached = _cached;
    if (cached != null) return Future<AppSettingsSnapshot>.value(cached);
    final inflight = _loading;
    if (inflight != null) return inflight;
    final future = _loadImpl();
    _loading = future;
    return future;
  }

  static Future<AppSettingsSnapshot> _loadImpl() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        final defaults = AppSettingsSnapshot.defaults();
        // First-launch case: create the file now so subsequent writes
        // don't race on create. Previously `persist` ran on every
        // `load` regardless of whether the snapshot had changed.
        await persist(defaults);
        _cached = defaults;
        return defaults;
      }
      final raw = await file.readAsString();
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        final snapshot = AppSettingsSnapshot.fromJson(parsed);
        _cached = snapshot;
        return snapshot;
      }
      // Malformed file — overwrite with defaults.
      final defaults = AppSettingsSnapshot.defaults();
      await persist(defaults);
      _cached = defaults;
      return defaults;
    } catch (_) {
      final defaults = AppSettingsSnapshot.defaults();
      _cached = defaults;
      return defaults;
    } finally {
      _loading = null;
    }
  }

  /// Drop the process-scoped snapshot so the next [load] re-reads from
  /// disk. Exists for tests + the settings page's explicit "reset to
  /// defaults" flow.
  static void invalidateCache() {
    _cached = null;
  }

  static Future<void> persist(AppSettingsSnapshot snapshot) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      flush: true,
    );
    // Keep the memoised snapshot coherent with what's on disk.
    _cached = snapshot;
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

  static String _normalizeAppShortName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Manifold';
    return trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
  }
}
