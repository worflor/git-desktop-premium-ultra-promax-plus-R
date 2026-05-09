import 'dart:convert';
import 'dart:io';

import '../app/build_info.dart';
import 'external_tools.dart';
import 'storage_paths.dart';

class AppSettingsSnapshot {
  final double guardrailValue;
  final bool aiReadOnlyDefault;
  final bool logoAnimatesWhenUnfocused;
  final int telemetryRetentionDays;
  final int telemetryRetentionMb;
  final String updateChannel;
  /// True once the user has actively chosen an update channel via the
  /// ribbon. False means [updateChannel] is whatever the binary's build
  /// channel was at the time the snapshot was written — i.e. an auto
  /// default, not a preference. Loaders treat false as "ignore the
  /// stored value, use the *current* binary's channel instead", so a
  /// user upgrading from a stable binary to a beta binary sees BETA
  /// selected automatically rather than being stuck on a legacy 'stable'
  /// auto-default they never picked.
  final bool updateChannelExplicit;
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
  /// When true, newly tracked or changed files appearing in a status
  /// refresh are automatically added to the commit selection. Off by
  /// default — historical behavior is purely subtractive reconciliation.
  final bool autoSelectNewChanges;
  /// When true, the branches page fires a background prefetch of PR /
  /// issue metadata on load. Off = pull on demand (when the user
  /// switches to that lens). Default on to preserve existing behavior.
  final bool fetchOnlineIssuesOnBranchLoad;
  /// When true, in-progress commit drafts (per branch) and the file
  /// selection snapshot (per branch/upstream context) persist across
  /// sessions. Off = both get wiped on save and load — clean slate
  /// each time. Default on to preserve existing behavior.
  final bool rememberWorkInProgress;
  /// Master AI kill-switch. When true, every LLM-backed feature is
  /// hidden + disabled (review, muse, generate-message, ask/shape,
  /// AI patch-resolve, AI settings subtree). Logos stays — it's
  /// spectral math, not a model. Default false.
  final bool hideAiFeatures;
  /// Default undo-window seconds — applies to any action kind that
  /// doesn't have an override in [undoWindowOverrides]. 0 = off (no
  /// pill, action is immediately final). Canonical UI stops are
  /// {0, 3, 6, 10, 15}; any value > 15 is a user-typed custom.
  final int undoWindowSeconds;
  /// Per-action-kind overrides for the undo window. Keys are the
  /// string names of `UndoActionKind` enum values (e.g. "commit",
  /// "discard"). When a key is present, its value replaces the
  /// default for that specific kind — so a user can have e.g. 3s
  /// discards and 15s commits in the same install. Empty by default:
  /// every kind follows [undoWindowSeconds].
  final Map<String, int> undoWindowOverrides;
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
  /// User-configured external tools surfaced by the project row's
  /// "Open with…" submenu. Empty list = zero-state, the menu shows a
  /// single "Open with…" item that deep-links into the settings page.
  /// See `external_tools.dart` for the model + preset starters.
  final List<ExternalTool> externalTools;
  final int changesPanelWidthPx;

  const AppSettingsSnapshot({
    required this.guardrailValue,
    required this.aiReadOnlyDefault,
    required this.logoAnimatesWhenUnfocused,
    required this.telemetryRetentionDays,
    required this.telemetryRetentionMb,
    required this.updateChannel,
    required this.updateChannelExplicit,
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
    required this.autoSelectNewChanges,
    required this.fetchOnlineIssuesOnBranchLoad,
    required this.rememberWorkInProgress,
    required this.hideAiFeatures,
    required this.undoWindowSeconds,
    required this.undoWindowOverrides,
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
    required this.externalTools,
    required this.changesPanelWidthPx,
  });

  Map<String, dynamic> toJson() => {
        'guardrailValue': guardrailValue,
        'aiReadOnlyDefault': aiReadOnlyDefault,
        'logoAnimatesWhenUnfocused': logoAnimatesWhenUnfocused,
        'telemetryRetentionDays': telemetryRetentionDays,
        'telemetryRetentionMb': telemetryRetentionMb,
        'updateChannel': updateChannel,
        'updateChannelExplicit': updateChannelExplicit,
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
        'autoSelectNewChanges': autoSelectNewChanges,
        'fetchOnlineIssuesOnBranchLoad': fetchOnlineIssuesOnBranchLoad,
        'rememberWorkInProgress': rememberWorkInProgress,
        'hideAiFeatures': hideAiFeatures,
        'undoWindowSeconds': undoWindowSeconds,
        'undoWindowOverrides': undoWindowOverrides,
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
        'externalTools': [for (final t in externalTools) t.toJson()],
        'changesPanelWidthPx': changesPanelWidthPx,
      };

  factory AppSettingsSnapshot.defaults() => AppSettingsSnapshot(
        guardrailValue: 0.5,
        aiReadOnlyDefault: true,
        logoAnimatesWhenUnfocused: true,
        telemetryRetentionDays: 30,
        telemetryRetentionMb: 128,
        // First-run default tracks whatever build the user installed —
        // they can re-pin from the deployment-channel ribbon.
        updateChannel: BuildInfo.channel.id,
        updateChannelExplicit: false,
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
        autoSelectNewChanges: false,
        fetchOnlineIssuesOnBranchLoad: true,
        rememberWorkInProgress: true,
        hideAiFeatures: false,
        undoWindowSeconds: 6,
        undoWindowOverrides: const {},
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
        externalTools: const [],
        changesPanelWidthPx: 320,
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
      // Pre-flag installs (no `updateChannelExplicit` field) need a
      // best-effort migration: we can't ask the user, but the old
      // schema gives us enough signal to keep deliberate choices.
      //
      // Pre-flag, every fresh install defaulted to 'stable' and the
      // old normalizer coerced anything-other-than-'beta' to 'stable'.
      // So:
      //   * persisted 'beta'   — could ONLY have been set by the user
      //                          tapping the ribbon. Treat as explicit
      //                          so an upgrade to a beta/stable binary
      //                          doesn't silently revert their pin.
      //   * persisted 'stable' — ambiguous (default OR explicit). We
      //                          treat it as defaulted so post-upgrade
      //                          users naturally track their new build
      //                          channel rather than getting stuck on
      //                          a stale auto-default.
      //   * persisted 'dev'    — couldn't have been written by pre-flag
      //                          code; if it does appear, it can only
      //                          come from a hand-edited file, so keep
      //                          it as explicit.
      updateChannelExplicit: json.containsKey('updateChannelExplicit')
          ? SettingsStore._boolOr(json['updateChannelExplicit'], false)
          : SettingsStore._inferLegacyChannelExplicit(json['updateChannel']),
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
      autoSelectNewChanges: SettingsStore._boolOr(
        json['autoSelectNewChanges'],
        defaults.autoSelectNewChanges,
      ),
      fetchOnlineIssuesOnBranchLoad: SettingsStore._boolOr(
        json['fetchOnlineIssuesOnBranchLoad'],
        defaults.fetchOnlineIssuesOnBranchLoad,
      ),
      rememberWorkInProgress: SettingsStore._boolOr(
        json['rememberWorkInProgress'],
        defaults.rememberWorkInProgress,
      ),
      hideAiFeatures: SettingsStore._boolOr(
        json['hideAiFeatures'],
        defaults.hideAiFeatures,
      ),
      undoWindowSeconds: SettingsStore._intOr(
        json['undoWindowSeconds'],
        defaults.undoWindowSeconds,
      ).clamp(0, 3600),
      undoWindowOverrides:
          SettingsStore._intMapOr(json['undoWindowOverrides']),
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
      externalTools: SettingsStore._externalToolsOr(json['externalTools']),
      changesPanelWidthPx: SettingsStore._intOr(
        json['changesPanelWidthPx'],
        defaults.changesPanelWidthPx,
      ).clamp(220, 520),
    );
  }

  AppSettingsSnapshot copyWith({
    double? guardrailValue,
    bool? aiReadOnlyDefault,
    bool? logoAnimatesWhenUnfocused,
    int? telemetryRetentionDays,
    int? telemetryRetentionMb,
    String? updateChannel,
    bool? updateChannelExplicit,
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
    bool? autoSelectNewChanges,
    bool? fetchOnlineIssuesOnBranchLoad,
    bool? rememberWorkInProgress,
    bool? hideAiFeatures,
    int? undoWindowSeconds,
    Map<String, int>? undoWindowOverrides,
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
    List<ExternalTool>? externalTools,
    int? changesPanelWidthPx,
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
      updateChannelExplicit:
          updateChannelExplicit ?? this.updateChannelExplicit,
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
      autoSelectNewChanges:
          autoSelectNewChanges ?? this.autoSelectNewChanges,
      fetchOnlineIssuesOnBranchLoad: fetchOnlineIssuesOnBranchLoad ??
          this.fetchOnlineIssuesOnBranchLoad,
      rememberWorkInProgress:
          rememberWorkInProgress ?? this.rememberWorkInProgress,
      hideAiFeatures: hideAiFeatures ?? this.hideAiFeatures,
      undoWindowSeconds:
          undoWindowSeconds ?? this.undoWindowSeconds,
      undoWindowOverrides:
          undoWindowOverrides ?? this.undoWindowOverrides,
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
      externalTools: externalTools ?? this.externalTools,
      changesPanelWidthPx: changesPanelWidthPx ?? this.changesPanelWidthPx,
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

  /// Parse the persisted external-tools list. Drops malformed entries
  /// silently — same best-effort approach the other parsers take. An
  /// entry is malformed when [ExternalTool.fromJson] returns null
  /// (typically: missing executable).
  static List<ExternalTool> _externalToolsOr(dynamic value) {
    if (value is! List) return const [];
    final out = <ExternalTool>[];
    for (final entry in value) {
      final tool = ExternalTool.fromJson(entry);
      if (tool != null) out.add(tool);
    }
    return out;
  }

  /// Parse a JSON `Map<String, dynamic>` where every value is expected
  /// to be an int, clamped into a sane [0, 3600] range. Malformed
  /// entries (non-numeric values, garbage keys) are silently dropped
  /// — same best-effort approach the other parsers take.
  static Map<String, int> _intMapOr(dynamic value) {
    if (value is! Map) return const {};
    final out = <String, int>{};
    for (final entry in value.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is String && v is num) {
        final iv = v.toInt();
        if (iv >= 0 && iv <= 3600) out[k] = iv;
      }
    }
    return out;
  }

  static String _normalizeUpdateChannel(String value) =>
      BuildInfo.normalizeChannelId(value);

  /// Best-effort inference of whether a pre-flag persisted update
  /// channel was an explicit user choice. Pre-flag schema lacked the
  /// flag entirely, but the old normalizer's behaviour gives us
  /// enough signal: it coerced anything-other-than-'beta' to
  /// 'stable', so a stored 'beta' could ONLY have come from a user
  /// tapping the ribbon. 'stable' stays ambiguous and we lean
  /// toward auto-tracking the binary's channel post-upgrade.
  static bool _inferLegacyChannelExplicit(dynamic raw) {
    if (raw is! String) return false;
    final v = raw.trim().toLowerCase();
    return v == 'beta' || v == 'dev';
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
