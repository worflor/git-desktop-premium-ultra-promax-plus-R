import 'package:flutter/foundation.dart';

import '../backend/commit_format.dart';
import '../backend/file_coupling.dart';
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
  double _motionRate = 1.0;
  double _reduceMotionPhase = 0.0;
  bool _stashCabinetDefaultExpanded = false;
  bool _instantBlameHover = false;
  bool _autoSelectNewChanges = false;
  bool _fetchOnlineIssuesOnBranchLoad = true;
  bool _rememberWorkInProgress = true;
  int _undoWindowSeconds = 6;
  FileSortGuide _fileSortGuide = FileSortGuide.relatedProximity;
  bool _fileSortInverted = false;
  CommitStructure _commitStructure = kDefaultCommitStructure;
  CommitVoice _commitVoice = kDefaultCommitVoice;
  CommitCoverage _commitCoverage = kDefaultCommitCoverage;
  double _logosPadX = 0.5;
  double _logosPadY = 0.5;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  double get guardrailValue => _guardrailValue;
  int get guardrailStage => _guardrailStageFromValue(_guardrailValue);
  String get updateChannel => _updateChannel;
  bool get crashReportingEnabled => _crashReportingEnabled;
  bool get aiReadOnlyDefault => _aiReadOnlyDefault;
  bool get logoAnimatesWhenUnfocused => _logoAnimatesWhenUnfocused;

  /// Global motion-rate scalar in [0.0, 2.0]. 0 = no motion (reduce-motion
  /// equivalent), 1 = authored speed, 2 = double-time. Animations compute
  /// their actual duration as `authored / motionRate`, and skip entirely
  /// (Duration.zero) when the rate is at or below [_kMotionRateOff].
  double get motionRate => _motionRate;

  /// Legacy boolean view of [motionRate]. Returns true when the rate is at
  /// or below the "off" threshold — preserved so callers that only cared
  /// about the binary flip continue to work unchanged.
  bool get reduceMotion => _motionRate <= _kMotionRateOff;

  double get reduceMotionPhase => _reduceMotionPhase;

  /// Rates at or below this threshold are treated as "no motion". Chosen
  /// slightly above zero so a rounding artifact from persistence doesn't
  /// accidentally re-enable animations when the user meant OFF.
  static const double _kMotionRateOff = 0.0001;
  bool get stashCabinetDefaultExpanded => _stashCabinetDefaultExpanded;
  bool get instantBlameHover => _instantBlameHover;
  bool get autoSelectNewChanges => _autoSelectNewChanges;
  bool get fetchOnlineIssuesOnBranchLoad => _fetchOnlineIssuesOnBranchLoad;
  bool get rememberWorkInProgress => _rememberWorkInProgress;
  int get undoWindowSeconds => _undoWindowSeconds;
  FileSortGuide get fileSortGuide => _fileSortGuide;
  bool get fileSortInverted => _fileSortInverted;
  CommitStructure get commitStructure => _commitStructure;
  CommitVoice get commitVoice => _commitVoice;
  CommitCoverage get commitCoverage => _commitCoverage;
  double get logosPadX => _logosPadX;
  double get logosPadY => _logosPadY;

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
    _motionRate = settings.motionRate.clamp(0.0, 2.0);
    _reduceMotionPhase = settings.reduceMotionPhase;
    _stashCabinetDefaultExpanded = settings.stashCabinetDefaultExpanded;
    _instantBlameHover = settings.instantBlameHover;
    _autoSelectNewChanges = settings.autoSelectNewChanges;
    _fetchOnlineIssuesOnBranchLoad = settings.fetchOnlineIssuesOnBranchLoad;
    _rememberWorkInProgress = settings.rememberWorkInProgress;
    _undoWindowSeconds = settings.undoWindowSeconds.clamp(0, 3600);
    _fileSortGuide = _sortGuideFromString(settings.fileSortGuide);
    _fileSortInverted = settings.fileSortInverted;
    _commitStructure = commitStructureFromKey(settings.commitStructure);
    _commitVoice = commitVoiceFromKey(settings.commitVoice);
    _commitCoverage = commitCoverageFromKey(settings.commitCoverage);
    _logosPadX = settings.logosPadX;
    _logosPadY = settings.logosPadY;
    _loaded = true;
    notifyListeners();
  }

  /// Read the current on-disk snapshot and persist a copy with the provided
  /// fields overwritten. Avoids spelling out every field at every setter
  /// callsite — new preferences only need to extend this helper's signature.
  Future<void> _persistWith({
    double? guardrailValue,
    bool? aiReadOnlyDefault,
    bool? logoAnimatesWhenUnfocused,
    String? updateChannel,
    bool? crashReportingEnabled,
    bool? reduceMotion,
    double? motionRate,
    double? reduceMotionPhase,
    bool? stashCabinetDefaultExpanded,
    bool? instantBlameHover,
    bool? autoSelectNewChanges,
    bool? fetchOnlineIssuesOnBranchLoad,
    bool? rememberWorkInProgress,
    int? undoWindowSeconds,
    String? fileSortGuide,
    bool? fileSortInverted,
    String? commitStructure,
    String? commitVoice,
    String? commitCoverage,
    double? logosPadX,
    double? logosPadY,
  }) async {
    final s = await SettingsStore.load();
    await SettingsStore.persist(
      s.copyWith(
        guardrailValue: guardrailValue,
        aiReadOnlyDefault: aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: logoAnimatesWhenUnfocused,
        updateChannel: updateChannel,
        crashReportingEnabled: crashReportingEnabled,
        reduceMotion: reduceMotion,
        motionRate: motionRate,
        reduceMotionPhase: reduceMotionPhase,
        stashCabinetDefaultExpanded: stashCabinetDefaultExpanded,
        instantBlameHover: instantBlameHover,
        autoSelectNewChanges: autoSelectNewChanges,
        fetchOnlineIssuesOnBranchLoad: fetchOnlineIssuesOnBranchLoad,
        rememberWorkInProgress: rememberWorkInProgress,
        undoWindowSeconds: undoWindowSeconds,
        fileSortGuide: fileSortGuide,
        fileSortInverted: fileSortInverted,
        commitStructure: commitStructure,
        commitVoice: commitVoice,
        commitCoverage: commitCoverage,
        logosPadX: logosPadX,
        logosPadY: logosPadY,
      ),
    );
  }

  /// Write the pad's XY position. Drag updates can fire many times per
  /// second, so we coalesce writes: [notifyListeners] happens on every
  /// call (the UI needs the re-render), but the persist is fire-and-
  /// forget. The on-disk file is a small JSON blob so back-to-back
  /// writes are cheap enough — a debouncer would add code without
  /// visible benefit here.
  Future<void> setLogosPad(double x, double y) async {
    final cx = x.clamp(0.0, 1.0);
    final cy = y.clamp(0.0, 1.0);
    if (_logosPadX == cx && _logosPadY == cy) return;
    _logosPadX = cx;
    _logosPadY = cy;
    notifyListeners();
    await _persistWith(logosPadX: cx, logosPadY: cy);
  }

  /// Write a new [motionRate]. Value is clamped to [0, 2]. Persists both
  /// `motionRate` (authoritative) AND the derived `reduceMotion` boolean
  /// so on-disk downgrades keep working — an older build reading this
  /// settings file will see `reduceMotion = rate <= 0` and behave
  /// correctly even without knowing about the rate field.
  Future<void> setMotionRate(double value) async {
    final clamped = value.clamp(0.0, 2.0);
    if (_motionRate == clamped) return;
    _motionRate = clamped;
    await _persistWith(
      motionRate: clamped,
      reduceMotion: clamped <= _kMotionRateOff,
    );
    notifyListeners();
  }

  /// Convenience toggle for callers that only care about the binary flip.
  /// Maps `true → 0.0` (off), `false → 1.0` (normal). Callers that want
  /// a tuned rate use [setMotionRate] directly.
  Future<void> setReduceMotion(bool value) => setMotionRate(value ? 0.0 : 1.0);

  /// Persist the pulse-wave phase that the reduce-motion toggle froze
  /// at. Intentionally does NOT call [notifyListeners] — nothing in the
  /// app watches this value reactively; it's only read once in the
  /// toggle widget's initState to seed the phase on restart. Skipping
  /// the broadcast avoids pointless rebuilds across every preference
  /// watcher each time the wave comes to rest.
  Future<void> setReduceMotionPhase(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_reduceMotionPhase == clamped) return;
    _reduceMotionPhase = clamped;
    await _persistWith(reduceMotionPhase: clamped);
  }

  Future<void> setStashCabinetDefaultExpanded(bool value) async {
    if (_stashCabinetDefaultExpanded == value) return;
    _stashCabinetDefaultExpanded = value;
    await _persistWith(stashCabinetDefaultExpanded: value);
    notifyListeners();
  }

  Future<void> setInstantBlameHover(bool value) async {
    if (_instantBlameHover == value) return;
    _instantBlameHover = value;
    await _persistWith(instantBlameHover: value);
    notifyListeners();
  }

  Future<void> setAutoSelectNewChanges(bool value) async {
    if (_autoSelectNewChanges == value) return;
    _autoSelectNewChanges = value;
    await _persistWith(autoSelectNewChanges: value);
    notifyListeners();
  }

  Future<void> setFetchOnlineIssuesOnBranchLoad(bool value) async {
    if (_fetchOnlineIssuesOnBranchLoad == value) return;
    _fetchOnlineIssuesOnBranchLoad = value;
    await _persistWith(fetchOnlineIssuesOnBranchLoad: value);
    notifyListeners();
  }

  Future<void> setRememberWorkInProgress(bool value) async {
    if (_rememberWorkInProgress == value) return;
    _rememberWorkInProgress = value;
    await _persistWith(rememberWorkInProgress: value);
    notifyListeners();
  }

  /// Set the discard-file undo window, in seconds. Accepts 0 (off) or
  /// any of the canonical stops {3, 6, 10, 15}; values strictly greater
  /// than 15 are custom user-typed unlocks and get clamped to a sane
  /// ceiling so a bogus paste can't nerf the flow.
  Future<void> setUndoWindowSeconds(int value) async {
    final clamped = value < 0 ? 0 : (value > 3600 ? 3600 : value);
    if (_undoWindowSeconds == clamped) return;
    _undoWindowSeconds = clamped;
    await _persistWith(undoWindowSeconds: clamped);
    notifyListeners();
  }

  Future<void> setFileSortGuide(FileSortGuide value) async {
    if (_fileSortGuide == value) return;
    _fileSortGuide = value;
    await _persistWith(fileSortGuide: _sortGuideToString(value));
    notifyListeners();
  }

  Future<void> setFileSortInverted(bool value) async {
    if (_fileSortInverted == value) return;
    _fileSortInverted = value;
    await _persistWith(fileSortInverted: value);
    notifyListeners();
  }

  Future<void> setCommitStructure(CommitStructure value) async {
    if (_commitStructure == value) return;
    _commitStructure = value;
    await _persistWith(commitStructure: commitStructureKey(value));
    notifyListeners();
  }

  Future<void> setCommitVoice(CommitVoice value) async {
    if (_commitVoice == value) return;
    _commitVoice = value;
    await _persistWith(commitVoice: commitVoiceKey(value));
    notifyListeners();
  }

  Future<void> setCommitCoverage(CommitCoverage value) async {
    if (_commitCoverage == value) return;
    _commitCoverage = value;
    await _persistWith(commitCoverage: commitCoverageKey(value));
    notifyListeners();
  }

  static FileSortGuide _sortGuideFromString(String s) {
    switch (s.trim().toLowerCase()) {
      case 'alphabetical':
        return FileSortGuide.alphabetical;
      case 'impact':
        return FileSortGuide.impact;
      default:
        return FileSortGuide.relatedProximity;
    }
  }

  static String _sortGuideToString(FileSortGuide g) {
    switch (g) {
      case FileSortGuide.alphabetical:
        return 'alphabetical';
      case FileSortGuide.impact:
        return 'impact';
      case FileSortGuide.relatedProximity:
        return 'related';
    }
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
      await _persistWith(guardrailValue: _guardrailValue);
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
      await _persistWith(updateChannel: _updateChannel);
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
      await _persistWith(crashReportingEnabled: _crashReportingEnabled);
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
    await _persistWith(aiReadOnlyDefault: _aiReadOnlyDefault);
    notifyListeners();
  }

  Future<void> setLogoAnimatesWhenUnfocused(bool value) async {
    if (_logoAnimatesWhenUnfocused == value) {
      return;
    }
    _logoAnimatesWhenUnfocused = value;
    await _persistWith(logoAnimatesWhenUnfocused: _logoAnimatesWhenUnfocused);
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
