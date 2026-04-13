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
  bool _reduceMotion = false;
  double _reduceMotionPhase = 0.0;
  bool _stashCabinetDefaultExpanded = false;
  bool _instantBlameHover = false;
  FileSortGuide _fileSortGuide = FileSortGuide.relatedProximity;
  bool _fileSortInverted = false;
  CommitStructure _commitStructure = kDefaultCommitStructure;
  CommitVoice _commitVoice = kDefaultCommitVoice;
  CommitCoverage _commitCoverage = kDefaultCommitCoverage;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  double get guardrailValue => _guardrailValue;
  int get guardrailStage => _guardrailStageFromValue(_guardrailValue);
  String get updateChannel => _updateChannel;
  bool get crashReportingEnabled => _crashReportingEnabled;
  bool get aiReadOnlyDefault => _aiReadOnlyDefault;
  bool get logoAnimatesWhenUnfocused => _logoAnimatesWhenUnfocused;
  bool get reduceMotion => _reduceMotion;
  double get reduceMotionPhase => _reduceMotionPhase;
  bool get stashCabinetDefaultExpanded => _stashCabinetDefaultExpanded;
  bool get instantBlameHover => _instantBlameHover;
  FileSortGuide get fileSortGuide => _fileSortGuide;
  bool get fileSortInverted => _fileSortInverted;
  CommitStructure get commitStructure => _commitStructure;
  CommitVoice get commitVoice => _commitVoice;
  CommitCoverage get commitCoverage => _commitCoverage;

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
    _reduceMotion = settings.reduceMotion;
    _reduceMotionPhase = settings.reduceMotionPhase;
    _stashCabinetDefaultExpanded = settings.stashCabinetDefaultExpanded;
    _instantBlameHover = settings.instantBlameHover;
    _fileSortGuide = _sortGuideFromString(settings.fileSortGuide);
    _fileSortInverted = settings.fileSortInverted;
    _commitStructure = commitStructureFromKey(settings.commitStructure);
    _commitVoice = commitVoiceFromKey(settings.commitVoice);
    _commitCoverage = commitCoverageFromKey(settings.commitCoverage);
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
    double? reduceMotionPhase,
    bool? stashCabinetDefaultExpanded,
    bool? instantBlameHover,
    String? fileSortGuide,
    bool? fileSortInverted,
    String? commitStructure,
    String? commitVoice,
    String? commitCoverage,
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
        reduceMotionPhase: reduceMotionPhase,
        stashCabinetDefaultExpanded: stashCabinetDefaultExpanded,
        instantBlameHover: instantBlameHover,
        fileSortGuide: fileSortGuide,
        fileSortInverted: fileSortInverted,
        commitStructure: commitStructure,
        commitVoice: commitVoice,
        commitCoverage: commitCoverage,
      ),
    );
  }

  Future<void> setReduceMotion(bool value) async {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    await _persistWith(reduceMotion: value);
    notifyListeners();
  }

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
