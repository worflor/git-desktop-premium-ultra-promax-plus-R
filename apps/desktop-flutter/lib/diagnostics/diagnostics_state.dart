import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/command_telemetry_store.dart';
import '../backend/local_telemetry_store.dart';
import '../backend/settings_store.dart';

class CommandLifecycleEvent {
  final int id;
  final String type;
  final String command;
  final String at;
  final double? durationMs;
  final String? requestId;
  final String? errorCode;
  final String? message;
  final int? attempt;

  const CommandLifecycleEvent({
    required this.id,
    required this.type,
    required this.command,
    required this.at,
    this.durationMs,
    this.requestId,
    this.errorCode,
    this.message,
    this.attempt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'command': command,
        'at': at,
        if (durationMs != null) 'durationMs': durationMs,
        if (requestId != null) 'requestId': requestId,
        if (errorCode != null) 'errorCode': errorCode,
        if (message != null) 'message': message,
        if (attempt != null) 'attempt': attempt,
      };
}

class CommandLatencySample {
  final String command;
  final bool ok;
  final String? errorCode;
  final String? requestId;
  final double roundTripMs;
  final double? backendDurationMs;
  final String recordedAt;

  const CommandLatencySample({
    required this.command,
    required this.ok,
    required this.roundTripMs,
    required this.recordedAt,
    this.errorCode,
    this.requestId,
    this.backendDurationMs,
  });

  Map<String, dynamic> toJson() => {
        'command': command,
        'ok': ok,
        if (errorCode != null) 'errorCode': errorCode,
        if (requestId != null) 'requestId': requestId,
        'roundTripMs': roundTripMs,
        if (backendDurationMs != null) 'backendDurationMs': backendDurationMs,
        'recordedAt': recordedAt,
      };
}

class CommandLatencySummary {
  final String command;
  final int count;
  final int successCount;
  final int failureCount;
  final double p50Ms;
  final double p95Ms;
  final double avgMs;
  final double minMs;
  final double maxMs;
  final double lastMs;

  const CommandLatencySummary({
    required this.command,
    required this.count,
    required this.successCount,
    required this.failureCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.lastMs,
  });

  Map<String, dynamic> toJson() => {
        'command': command,
        'count': count,
        'successCount': successCount,
        'failureCount': failureCount,
        'p50Ms': p50Ms,
        'p95Ms': p95Ms,
        'avgMs': avgMs,
        'minMs': minMs,
        'maxMs': maxMs,
        'lastMs': lastMs,
      };
}

class CommandLatencyReport {
  final String generatedAt;
  final int totalSamples;
  final int commandCount;
  final List<CommandLatencySummary> summaries;
  final List<CommandLatencySample> recentSamples;

  const CommandLatencyReport({
    required this.generatedAt,
    required this.totalSamples,
    required this.commandCount,
    required this.summaries,
    required this.recentSamples,
  });

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt,
        'totalSamples': totalSamples,
        'commandCount': commandCount,
        'summaries': summaries.map((summary) => summary.toJson()).toList(),
        'recentSamples':
            recentSamples.map((sample) => sample.toJson()).toList(),
      };
}

class DiffRenderMetricSample {
  final String diffId;
  final String path;
  final String rendererMode;
  final int changedLines;
  final int payloadBytes;
  final double firstPaintMs;
  final double sustainedScrollFps;
  final double memoryEstimateMb;
  final double frameTimeP95Ms;
  final double buildTimeP95Ms;
  final double rasterTimeP95Ms;
  final int frameCount;
  final int jankyFrameCount;
  final bool fallbackActivated;
  final String recordedAt;

  const DiffRenderMetricSample({
    required this.diffId,
    required this.path,
    required this.rendererMode,
    required this.changedLines,
    required this.payloadBytes,
    required this.firstPaintMs,
    required this.sustainedScrollFps,
    required this.memoryEstimateMb,
    required this.frameTimeP95Ms,
    required this.buildTimeP95Ms,
    required this.rasterTimeP95Ms,
    required this.frameCount,
    required this.jankyFrameCount,
    required this.fallbackActivated,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'diffId': diffId,
        'path': path,
        'rendererMode': rendererMode,
        'changedLines': changedLines,
        'payloadBytes': payloadBytes,
        'firstPaintMs': firstPaintMs,
        'sustainedScrollFps': sustainedScrollFps,
        'memoryEstimateMb': memoryEstimateMb,
        'frameTimeP95Ms': frameTimeP95Ms,
        'buildTimeP95Ms': buildTimeP95Ms,
        'rasterTimeP95Ms': rasterTimeP95Ms,
        'frameCount': frameCount,
        'jankyFrameCount': jankyFrameCount,
        'fallbackActivated': fallbackActivated,
        'recordedAt': recordedAt,
      };
}

class DiffRenderModeSummary {
  final String rendererMode;
  final int sessionCount;
  final int fallbackCount;
  final double fallbackRate;
  final double firstPaintP50Ms;
  final double firstPaintP95Ms;
  final double scrollFpsP50;
  final double scrollFpsP95;
  final double memoryP50Mb;
  final double memoryP95Mb;
  final double frameTimeP95Ms;
  final double buildTimeP95Ms;
  final double rasterTimeP95Ms;
  final double jankyFrameRate;

  const DiffRenderModeSummary({
    required this.rendererMode,
    required this.sessionCount,
    required this.fallbackCount,
    required this.fallbackRate,
    required this.firstPaintP50Ms,
    required this.firstPaintP95Ms,
    required this.scrollFpsP50,
    required this.scrollFpsP95,
    required this.memoryP50Mb,
    required this.memoryP95Mb,
    required this.frameTimeP95Ms,
    required this.buildTimeP95Ms,
    required this.rasterTimeP95Ms,
    required this.jankyFrameRate,
  });

  Map<String, dynamic> toJson() => {
        'rendererMode': rendererMode,
        'sessionCount': sessionCount,
        'fallbackCount': fallbackCount,
        'fallbackRate': fallbackRate,
        'firstPaintP50Ms': firstPaintP50Ms,
        'firstPaintP95Ms': firstPaintP95Ms,
        'scrollFpsP50': scrollFpsP50,
        'scrollFpsP95': scrollFpsP95,
        'memoryP50Mb': memoryP50Mb,
        'memoryP95Mb': memoryP95Mb,
        'frameTimeP95Ms': frameTimeP95Ms,
        'buildTimeP95Ms': buildTimeP95Ms,
        'rasterTimeP95Ms': rasterTimeP95Ms,
        'jankyFrameRate': jankyFrameRate,
      };
}

class DiffRenderMetricsReport {
  final String generatedAt;
  final int totalSessions;
  final int fallbackCount;
  final double fallbackRate;
  final double firstPaintP95Ms;
  final double scrollFpsP50;
  final double memoryP95Mb;
  final double frameTimeP95Ms;
  final double buildTimeP95Ms;
  final double rasterTimeP95Ms;
  final double jankyFrameRate;
  final List<DiffRenderModeSummary> modeSummaries;
  final List<DiffRenderMetricSample> recentSamples;

  const DiffRenderMetricsReport({
    required this.generatedAt,
    required this.totalSessions,
    required this.fallbackCount,
    required this.fallbackRate,
    required this.firstPaintP95Ms,
    required this.scrollFpsP50,
    required this.memoryP95Mb,
    required this.frameTimeP95Ms,
    required this.buildTimeP95Ms,
    required this.rasterTimeP95Ms,
    required this.jankyFrameRate,
    required this.modeSummaries,
    required this.recentSamples,
  });

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt,
        'totalSessions': totalSessions,
        'fallbackCount': fallbackCount,
        'fallbackRate': fallbackRate,
        'firstPaintP95Ms': firstPaintP95Ms,
        'scrollFpsP50': scrollFpsP50,
        'memoryP95Mb': memoryP95Mb,
        'frameTimeP95Ms': frameTimeP95Ms,
        'buildTimeP95Ms': buildTimeP95Ms,
        'rasterTimeP95Ms': rasterTimeP95Ms,
        'jankyFrameRate': jankyFrameRate,
        'modeSummaries':
            modeSummaries.map((summary) => summary.toJson()).toList(),
        'recentSamples':
            recentSamples.map((sample) => sample.toJson()).toList(),
      };
}

class UiTimingSample {
  final String event;
  final String phase;
  final bool ok;
  final String? errorCode;
  final double durationMs;
  final String recordedAt;

  const UiTimingSample({
    required this.event,
    required this.phase,
    required this.ok,
    required this.durationMs,
    required this.recordedAt,
    this.errorCode,
  });

  Map<String, dynamic> toJson() => {
        'event': event,
        'phase': phase,
        'ok': ok,
        if (errorCode != null) 'errorCode': errorCode,
        'durationMs': durationMs,
        'recordedAt': recordedAt,
      };
}

class UiTimingSummary {
  final String event;
  final String phase;
  final int count;
  final int failureCount;
  final double p50Ms;
  final double p95Ms;
  final double avgMs;
  final double minMs;
  final double maxMs;
  final double lastMs;

  const UiTimingSummary({
    required this.event,
    required this.phase,
    required this.count,
    required this.failureCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.lastMs,
  });

  Map<String, dynamic> toJson() => {
        'event': event,
        'phase': phase,
        'count': count,
        'failureCount': failureCount,
        'p50Ms': p50Ms,
        'p95Ms': p95Ms,
        'avgMs': avgMs,
        'minMs': minMs,
        'maxMs': maxMs,
        'lastMs': lastMs,
      };
}

class UiTimingReport {
  final String generatedAt;
  final int totalSamples;
  final int eventCount;
  final List<UiTimingSummary> summaries;
  final List<UiTimingSample> recentSamples;

  const UiTimingReport({
    required this.generatedAt,
    required this.totalSamples,
    required this.eventCount,
    required this.summaries,
    required this.recentSamples,
  });

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt,
        'totalSamples': totalSamples,
        'eventCount': eventCount,
        'summaries': summaries.map((summary) => summary.toJson()).toList(),
        'recentSamples':
            recentSamples.map((sample) => sample.toJson()).toList(),
      };
}

class DiagnosticsState extends ChangeNotifier {
  DiagnosticsState._();

  static final DiagnosticsState instance = DiagnosticsState._();

  static const int _maxRetainedCommandSamples = 600;
  static const int _maxRecentCommandSamples = 20;
  static const int _maxRetainedDiffSessions = 600;
  static const int _maxRecentDiffSessions = 20;
  static const int _maxRetainedUiSamples = 800;
  static const int _maxRecentUiSamples = 40;
  static const int _maxRetainedLifecycleEvents = 240;
  static const int _defaultRetentionDays = 30;
  static const int _defaultRetentionMb = 128;
  static const int _minRetentionDays = 1;
  static const int _maxRetentionDays = 365;
  static const int _minRetentionMb = 16;
  static const int _maxRetentionMb = 4096;
  static const String _commandLatencyStorageKey =
      'gdpu.command-latency.samples.v1';
  static const String _diffRenderStorageKey = 'gdpu.diff-render-metrics.v1';
  static const String _uiTimingStorageKey = 'gdpu.ui-timing.samples.v1';
  static const String _commandLatencyFileName =
      'command_latency.samples.v1.json';
  static const String _diffRenderFileName = 'diff_render_metrics.v1.json';
  static const String _uiTimingFileName = 'ui_timing.samples.v1.json';

  final List<CommandLatencySample> _commandSamples = [];
  final List<DiffRenderMetricSample> _diffRenderSamples = [];
  final List<UiTimingSample> _uiTimingSamples = [];
  final List<CommandLifecycleEvent> _commandLifecycleEvents = [];
  CommandTelemetrySnapshotData _backendCommandTelemetrySnapshot =
      const CommandTelemetrySnapshotData(
    generatedAt: '',
    sampleCount: 0,
    summaries: <CommandTelemetrySummaryData>[],
    recentSamples: <CommandTelemetrySampleData>[],
  );
  CommandLatencyReport? _cachedCommandLatencyReport;
  DiffRenderMetricsReport? _cachedDiffRenderMetricsReport;
  UiTimingReport? _cachedUiTimingReport;

  int _nextLifecycleEventId = 1;
  int _retentionDays = _defaultRetentionDays;
  int _retentionMb = _defaultRetentionMb;
  bool _loaded = false;
  Future<void> _backgroundIo = Future<void>.value();
  Timer? _backendSnapshotRefreshTimer;

  bool get isLoaded => _loaded;
  int get retentionDays => _retentionDays;
  int get retentionMb => _retentionMb;
  List<CommandLifecycleEvent> get commandLifecycleEvents =>
      List.unmodifiable(_commandLifecycleEvents.reversed);

  CommandLatencyReport get commandLatencyReport =>
      _cachedCommandLatencyReport ??= _buildCommandLatencyReport();
  DiffRenderMetricsReport get diffRenderMetricsReport =>
      _cachedDiffRenderMetricsReport ??= _buildDiffRenderMetricsReport();
  UiTimingReport get uiTimingReport =>
      _cachedUiTimingReport ??= _buildUiTimingReport();
  CommandTelemetrySnapshotData get backendCommandTelemetrySnapshot =>
      _backendCommandTelemetrySnapshot;

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final settings = await SettingsStore.load();
    _retentionDays = _normalizeRetentionDays(settings.telemetryRetentionDays);
    _retentionMb = _normalizeRetentionMb(settings.telemetryRetentionMb);
    _commandSamples
      ..clear()
      ..addAll(await _loadCommandSamples(prefs));
    _diffRenderSamples
      ..clear()
      ..addAll(await _loadDiffRenderSamples(prefs));
    _uiTimingSamples
      ..clear()
      ..addAll(await _loadUiTimingSamples(prefs));
    _applyRetentionToAll();
    _invalidateAllCachedReports();
    _loaded = true;
    await _persistRetentionAndSamples();
    await _refreshBackendCommandTelemetrySnapshot();
    notifyListeners();
  }

  Future<void> setRetentionPolicy(int retentionDays, int retentionMb) async {
    final normalizedDays = _normalizeRetentionDays(retentionDays);
    final normalizedMb = _normalizeRetentionMb(retentionMb);
    if (normalizedDays == _retentionDays && normalizedMb == _retentionMb) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    recordCommandLifecycleEvent(
      type: 'start',
      command: 'update_telemetry_retention',
    );
    try {
      _retentionDays = normalizedDays;
      _retentionMb = normalizedMb;
      _applyRetentionToAll();
      _invalidateAllCachedReports();
      await _persistRetentionAndSamples();
      await _refreshBackendCommandTelemetrySnapshot(enforceRetention: true);
      stopwatch.stop();
      recordCommandLifecycleEvent(
        type: 'success',
        command: 'update_telemetry_retention',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
      );
      await recordCommandLatency(
        command: 'update_telemetry_retention',
        ok: true,
        scope: 'command',
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
      );
      notifyListeners();
    } catch (error) {
      stopwatch.stop();
      recordCommandLifecycleEvent(
        type: 'failure',
        command: 'update_telemetry_retention',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
        message: error.toString(),
      );
      await recordCommandLatency(
        command: 'update_telemetry_retention',
        ok: false,
        scope: 'command',
        roundTripMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'preferences.write_failed',
      );
      rethrow;
    }
  }

  void recordCommandLifecycleEvent({
    required String type,
    required String command,
    double? durationMs,
    String? requestId,
    String? errorCode,
    String? message,
    int? attempt,
    bool notify = true,
  }) {
    final normalizedRequestId = _normalizeOptionalLabel(requestId);
    final normalizedErrorCode = _normalizeOptionalLabel(errorCode);
    final normalizedMessage = _normalizeOptionalLabel(message);
    final event = CommandLifecycleEvent(
      id: _nextLifecycleEventId++,
      type: type,
      command: command,
      at: DateTime.now().toIso8601String(),
      durationMs: durationMs == null ? null : _roundToHundredths(durationMs),
      requestId: normalizedRequestId.isEmpty ? null : normalizedRequestId,
      errorCode: normalizedErrorCode.isEmpty ? null : normalizedErrorCode,
      message: normalizedMessage.isEmpty ? null : normalizedMessage,
      attempt: attempt,
    );
    _commandLifecycleEvents.add(event);
    if (_commandLifecycleEvents.length > _maxRetainedLifecycleEvents) {
      _commandLifecycleEvents.removeRange(
        0,
        _commandLifecycleEvents.length - _maxRetainedLifecycleEvents,
      );
    }
    if (notify) {
      notifyListeners();
    }
  }

  void clearCommandLifecycleEvents() {
    if (_commandLifecycleEvents.isEmpty) {
      return;
    }
    _commandLifecycleEvents.clear();
    notifyListeners();
  }

  Future<void> recordCommandLatency({
    required String command,
    required bool ok,
    required double roundTripMs,
    String scope = 'command',
    double? backendDurationMs,
    String? errorCode,
    String? requestId,
  }) async {
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) {
      return;
    }

    final normalizedErrorCode = _normalizeOptionalLabel(errorCode);
    final normalizedRequestId = _normalizeOptionalLabel(requestId);
    _commandSamples.add(
      CommandLatencySample(
        command: normalizedCommand,
        ok: ok,
        errorCode:
            ok || normalizedErrorCode.isEmpty ? null : normalizedErrorCode,
        requestId: normalizedRequestId.isEmpty ? null : normalizedRequestId,
        roundTripMs: _roundToHundredths(_clampNumber(roundTripMs)),
        backendDurationMs: backendDurationMs == null
            ? null
            : _roundToHundredths(_clampNumber(backendDurationMs)),
        recordedAt: DateTime.now().toIso8601String(),
      ),
    );
    _applyCommandLatencyRetention();
    _cachedCommandLatencyReport = null;
    notifyListeners();
    _enqueueBackgroundIo(() async {
      await _persistCommandSamples();
      await CommandTelemetryStore.recordSample(
        scope: scope,
        command: normalizedCommand,
        ok: ok,
        durationMs: backendDurationMs ?? roundTripMs,
        errorCode: ok ? null : normalizedErrorCode,
      );
    });
    _scheduleBackendSnapshotRefresh();
  }

  Future<void> clearCommandLatencyReport() async {
    if (_commandSamples.isEmpty) {
      return;
    }
    _commandSamples.clear();
    _cachedCommandLatencyReport = null;
    await _persistCommandSamples();
    await CommandTelemetryStore.clearSamples();
    await _refreshBackendCommandTelemetrySnapshot();
    notifyListeners();
  }

  Future<void> recordDiffRenderMetrics({
    required String diffId,
    required String path,
    required String rendererMode,
    required int changedLines,
    required int payloadBytes,
    required double firstPaintMs,
    required double sustainedScrollFps,
    required double memoryEstimateMb,
    required double frameTimeP95Ms,
    required double buildTimeP95Ms,
    required double rasterTimeP95Ms,
    required int frameCount,
    required int jankyFrameCount,
    required bool fallbackActivated,
  }) async {
    _diffRenderSamples.add(
      DiffRenderMetricSample(
        diffId: diffId,
        path: path,
        rendererMode: _normalizeRenderMode(rendererMode),
        changedLines: _clampInt(changedLines),
        payloadBytes: _clampInt(payloadBytes),
        firstPaintMs: _roundToHundredths(_clampNumber(firstPaintMs)),
        sustainedScrollFps:
            _roundToHundredths(_clampNumber(sustainedScrollFps)),
        memoryEstimateMb: _roundToHundredths(_clampNumber(memoryEstimateMb)),
        frameTimeP95Ms: _roundToHundredths(_clampNumber(frameTimeP95Ms)),
        buildTimeP95Ms: _roundToHundredths(_clampNumber(buildTimeP95Ms)),
        rasterTimeP95Ms: _roundToHundredths(_clampNumber(rasterTimeP95Ms)),
        frameCount: _clampInt(frameCount),
        jankyFrameCount: _clampInt(jankyFrameCount),
        fallbackActivated: fallbackActivated,
        recordedAt: DateTime.now().toIso8601String(),
      ),
    );
    _applyDiffRenderRetention();
    _cachedDiffRenderMetricsReport = null;
    notifyListeners();
    _enqueueBackgroundIo(_persistDiffRenderSamples);
  }

  Future<void> clearDiffRenderMetricsReport() async {
    if (_diffRenderSamples.isEmpty) {
      return;
    }
    _diffRenderSamples.clear();
    _cachedDiffRenderMetricsReport = null;
    await _persistDiffRenderSamples();
    notifyListeners();
  }

  Future<void> recordUiTiming({
    required String event,
    String phase = 'interaction',
    required double durationMs,
    bool ok = true,
    String? errorCode,
  }) async {
    final normalizedEvent = _normalizeEvent(event);
    if (normalizedEvent.isEmpty) {
      return;
    }

    final normalizedPhase = _normalizePhase(phase);
    final normalizedErrorCode = _normalizeOptionalLabel(errorCode);
    final sample = UiTimingSample(
      event: normalizedEvent,
      phase: normalizedPhase,
      ok: ok,
      errorCode: ok || normalizedErrorCode.isEmpty ? null : normalizedErrorCode,
      durationMs: _roundToHundredths(_clampNumber(durationMs)),
      recordedAt: DateTime.now().toIso8601String(),
    );
    _uiTimingSamples.add(sample);
    _applyUiTimingRetention();
    _cachedUiTimingReport = null;

    recordCommandLifecycleEvent(
      type: ok ? 'success' : 'failure',
      command: 'ui.${sample.phase}.${sample.event}',
      durationMs: sample.durationMs,
      errorCode: sample.errorCode,
      notify: false,
    );
    _enqueueBackgroundIo(_persistUiTimingSamples);
    notifyListeners();
  }

  Future<void> clearUiTimingReport() async {
    if (_uiTimingSamples.isEmpty) {
      return;
    }
    _uiTimingSamples.clear();
    _cachedUiTimingReport = null;
    await _persistUiTimingSamples();
    notifyListeners();
  }

  Future<void> clearAllDiagnostics() async {
    _backendSnapshotRefreshTimer?.cancel();
    _commandSamples.clear();
    _diffRenderSamples.clear();
    _uiTimingSamples.clear();
    _commandLifecycleEvents.clear();
    _invalidateAllCachedReports();
    await _persistRetentionAndSamples();
    await CommandTelemetryStore.clearSamples();
    await _refreshBackendCommandTelemetrySnapshot();
    notifyListeners();
  }

  Future<void> refreshSnapshots() async {
    _backendSnapshotRefreshTimer?.cancel();
    await _refreshBackendCommandTelemetrySnapshot();
    notifyListeners();
  }

  Map<String, dynamic> buildSnapshot({required String focusedStream}) {
    final offenders = <Map<String, dynamic>>[];
    final commandReport = commandLatencyReport;
    final diffReport = diffRenderMetricsReport;
    final uiReport = uiTimingReport;
    final lifecycleEvents = commandLifecycleEvents;
    final commandOffender = _topCommandOffender();
    if (commandOffender != null) {
      offenders.add(commandOffender);
    }
    final diffOffender = _topDiffOffender();
    if (diffOffender != null) {
      offenders.add(diffOffender);
    }
    final uiOffender = _topUiOffender();
    if (uiOffender != null) {
      offenders.add(uiOffender);
    }
    offenders.sort((left, right) =>
        (right['score'] as double).compareTo(left['score'] as double));

    return {
      'schema': 'manifold.telemetry.v3',
      'copiedAt': DateTime.now().toIso8601String(),
      'focusedStream': focusedStream,
      'retention': {
        'days': _retentionDays,
        'mb': _retentionMb,
      },
      'totals': {
        'commandSamples': commandReport.totalSamples,
        'diffSessions': diffReport.totalSessions,
        'uiSamples': uiReport.totalSamples,
        'lifecycleEvents': lifecycleEvents.length,
      },
      'topOffenders': offenders
          .take(3)
          .map((offender) => {
                'stream': offender['stream'],
                'name': offender['name'],
                'metric': offender['metric'],
                'score': _roundToHundredths(offender['score'] as double),
              })
          .toList(),
      'command': _buildDenseCommandSnapshot(commandReport),
      'diffRender': _buildDenseDiffSnapshot(diffReport),
      'uiTiming': _buildDenseUiSnapshot(uiReport),
      'lifecycle': _buildDenseLifecycleSnapshot(lifecycleEvents),
    };
  }

  Map<String, dynamic> _buildDenseCommandSnapshot(
    CommandLatencyReport report,
  ) {
    return {
      'generatedAt': report.generatedAt,
      'totalSamples': report.totalSamples,
      'commandCount': report.commandCount,
      'summaries': _packTable(
        const [
          'command',
          'count',
          'successCount',
          'failureCount',
          'p50Ms',
          'p95Ms',
          'avgMs',
          'minMs',
          'maxMs',
          'lastMs',
        ],
        report.summaries.map(
          (summary) => [
            summary.command,
            summary.count,
            summary.successCount,
            summary.failureCount,
            summary.p50Ms,
            summary.p95Ms,
            summary.avgMs,
            summary.minMs,
            summary.maxMs,
            summary.lastMs,
          ],
        ),
      ),
      'samples': _packTable(
        const [
          'command',
          'ok',
          'roundTripMs',
          'backendDurationMs',
          'recordedAt',
          'errorCode',
        ],
        _smartTrimCommandSamples(_commandSamples).map(
          (sample) => [
            sample.command,
            sample.ok,
            sample.roundTripMs,
            sample.backendDurationMs,
            sample.recordedAt,
            sample.errorCode,
          ],
        ),
      ),
    };
  }

  Map<String, dynamic> _buildDenseDiffSnapshot(
    DiffRenderMetricsReport report,
  ) {
    return {
      'generatedAt': report.generatedAt,
      'totalSessions': report.totalSessions,
      'fallbackCount': report.fallbackCount,
      'fallbackRate': _roundToHundredths(report.fallbackRate),
      'firstPaintP95Ms': report.firstPaintP95Ms,
      'scrollFpsP50': report.scrollFpsP50,
      'memoryP95Mb': report.memoryP95Mb,
      'frameTimeP95Ms': report.frameTimeP95Ms,
      'buildTimeP95Ms': report.buildTimeP95Ms,
      'rasterTimeP95Ms': report.rasterTimeP95Ms,
      'jankyFrameRate': _roundToHundredths(report.jankyFrameRate),
      'modeSummaries': _packTable(
        const [
          'rendererMode',
          'sessionCount',
          'fallbackCount',
          'fallbackRate',
          'firstPaintP50Ms',
          'firstPaintP95Ms',
          'scrollFpsP50',
          'scrollFpsP95',
          'memoryP50Mb',
          'memoryP95Mb',
          'frameTimeP95Ms',
          'buildTimeP95Ms',
          'rasterTimeP95Ms',
          'jankyFrameRate',
        ],
        report.modeSummaries.map(
          (summary) => [
            summary.rendererMode,
            summary.sessionCount,
            summary.fallbackCount,
            _roundToHundredths(summary.fallbackRate),
            summary.firstPaintP50Ms,
            summary.firstPaintP95Ms,
            summary.scrollFpsP50,
            summary.scrollFpsP95,
            summary.memoryP50Mb,
            summary.memoryP95Mb,
            summary.frameTimeP95Ms,
            summary.buildTimeP95Ms,
            summary.rasterTimeP95Ms,
            _roundToHundredths(summary.jankyFrameRate),
          ],
        ),
      ),
      'sessions': _packTable(
        const [
          'rendererMode',
          'path',
          'changedLines',
          'payloadBytes',
          'firstPaintMs',
          'sustainedScrollFps',
          'memoryEstimateMb',
          'frameTimeP95Ms',
          'buildTimeP95Ms',
          'rasterTimeP95Ms',
          'frameCount',
          'jankyFrameCount',
          'fallbackActivated',
          'recordedAt',
          'diffId',
        ],
        _smartTrimDiffSamples(_diffRenderSamples).map(
          (sample) => [
            sample.rendererMode,
            _ellipsize(sample.path, 96),
            sample.changedLines,
            sample.payloadBytes,
            sample.firstPaintMs,
            sample.sustainedScrollFps,
            sample.memoryEstimateMb,
            sample.frameTimeP95Ms,
            sample.buildTimeP95Ms,
            sample.rasterTimeP95Ms,
            sample.frameCount,
            sample.jankyFrameCount,
            sample.fallbackActivated,
            sample.recordedAt,
            sample.diffId,
          ],
        ),
      ),
    };
  }

  Map<String, dynamic> _buildDenseUiSnapshot(UiTimingReport report) {
    return {
      'generatedAt': report.generatedAt,
      'totalSamples': report.totalSamples,
      'eventCount': report.eventCount,
      'summaries': _packTable(
        const [
          'phase',
          'event',
          'count',
          'failureCount',
          'p50Ms',
          'p95Ms',
          'avgMs',
          'minMs',
          'maxMs',
          'lastMs',
        ],
        report.summaries.map(
          (summary) => [
            summary.phase,
            summary.event,
            summary.count,
            summary.failureCount,
            summary.p50Ms,
            summary.p95Ms,
            summary.avgMs,
            summary.minMs,
            summary.maxMs,
            summary.lastMs,
          ],
        ),
      ),
      'samples': _packTable(
        const [
          'phase',
          'event',
          'ok',
          'durationMs',
          'recordedAt',
          'errorCode',
        ],
        _smartTrimUiSamples(_uiTimingSamples).map(
          (sample) => [
            sample.phase,
            sample.event,
            sample.ok,
            sample.durationMs,
            sample.recordedAt,
            sample.errorCode,
          ],
        ),
      ),
    };
  }

  Map<String, dynamic> _buildDenseLifecycleSnapshot(
    List<CommandLifecycleEvent> events,
  ) {
    return {
      'eventCount': events.length,
      'events': _packTable(
        const [
          'type',
          'command',
          'at',
          'durationMs',
          'requestId',
          'errorCode',
          'attempt',
          'message',
          'id',
        ],
        events.map(
          (event) => [
            event.type,
            event.command,
            event.at,
            event.durationMs,
            event.requestId,
            event.errorCode,
            event.attempt,
            event.message == null ? null : _ellipsize(event.message!, 120),
            event.id,
          ],
        ),
      ),
    };
  }

  // ── Smart sample trimming ──────────────────────────────────────────
  // Keep all failures + heaviest outliers + recent context.
  // No arbitrary caps — the diagnostic value comes from the extremes
  // and the tail, not the middle.

  /// Command samples: all failures, top 10 slowest successes, last 15 recent.
  List<CommandLatencySample> _smartTrimCommandSamples(
    List<CommandLatencySample> raw,
  ) {
    final failures = raw.where((s) => !s.ok).toList();
    final successes = raw.where((s) => s.ok).toList()
      ..sort((a, b) => b.roundTripMs.compareTo(a.roundTripMs));
    final heaviest = successes.take(10);
    final recent = raw.reversed.take(15);

    // Merge, dedupe by identity, sort by time.
    final seen = <CommandLatencySample>{};
    seen.addAll(failures);
    seen.addAll(heaviest);
    seen.addAll(recent);
    final result = seen.toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return result;
  }

  /// Diff render: all fallbacks, top 10 jankiest, last 10 recent.
  List<DiffRenderMetricSample> _smartTrimDiffSamples(
    List<DiffRenderMetricSample> raw,
  ) {
    final fallbacks = raw.where((s) => s.fallbackActivated).toList();
    final byJank = List.of(raw)
      ..sort((a, b) => b.frameTimeP95Ms.compareTo(a.frameTimeP95Ms));
    final heaviest = byJank.take(10);
    final recent = raw.reversed.take(10);

    final seen = <DiffRenderMetricSample>{};
    seen.addAll(fallbacks);
    seen.addAll(heaviest);
    seen.addAll(recent);
    final result = seen.toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return result;
  }

  /// UI timing: all failures, top 10 slowest, last 15 recent.
  List<UiTimingSample> _smartTrimUiSamples(List<UiTimingSample> raw) {
    final failures = raw.where((s) => !s.ok).toList();
    final byDuration = List.of(raw)
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    final heaviest = byDuration.take(10);
    final recent = raw.reversed.take(15);

    final seen = <UiTimingSample>{};
    seen.addAll(failures);
    seen.addAll(heaviest);
    seen.addAll(recent);
    final result = seen.toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return result;
  }

  Map<String, dynamic> _packTable(
    List<String> fields,
    Iterable<List<Object?>> rows,
  ) {
    return {
      'fields': fields,
      'rows': rows.map(_trimTrailingNulls).toList(),
    };
  }

  List<Object?> _trimTrailingNulls(List<Object?> row) {
    var end = row.length;
    while (end > 0 && row[end - 1] == null) {
      end -= 1;
    }
    return row.sublist(0, end);
  }

  Map<String, dynamic>? _topCommandOffender() {
    final summaries = commandLatencyReport.summaries;
    if (summaries.isEmpty) {
      return null;
    }
    final ranked = summaries.map((summary) {
      final failureRate =
          summary.count == 0 ? 0.0 : summary.failureCount / summary.count;
      final score = summary.p95Ms * (1 + failureRate * 3);
      return {
        'summary': summary,
        'score': score,
        'failureRate': failureRate,
      };
    }).toList()
      ..sort((left, right) =>
          (right['score'] as double).compareTo(left['score'] as double));
    final offender = ranked.first;
    final summary = offender['summary'] as CommandLatencySummary;
    final failureRate = offender['failureRate'] as double;
    return {
      'stream': 'Command',
      'name': summary.command,
      'metric':
          '${summary.p95Ms.toStringAsFixed(0)}ms p95 | ${(failureRate * 100).toStringAsFixed(0)}% fail',
      'score': offender['score'] as double,
    };
  }

  Map<String, dynamic>? _topDiffOffender() {
    final summaries = diffRenderMetricsReport.modeSummaries;
    if (summaries.isEmpty) {
      return null;
    }
    final ranked = summaries.map((summary) {
      final fpsPenalty = (60 - summary.scrollFpsP50).clamp(0, 60).toDouble();
      final score = summary.firstPaintP95Ms +
          summary.memoryP95Mb * 4 +
          summary.fallbackRate * 600 +
          summary.frameTimeP95Ms * 2.5 +
          summary.jankyFrameRate * 500 +
          fpsPenalty * 6;
      return {'summary': summary, 'score': score};
    }).toList()
      ..sort((left, right) =>
          (right['score'] as double).compareTo(left['score'] as double));
    final offender = ranked.first;
    final summary = offender['summary'] as DiffRenderModeSummary;
    return {
      'stream': 'Diff Render',
      'name': '${summary.rendererMode} renderer',
      'metric':
          '${(summary.jankyFrameRate * 100).toStringAsFixed(0)}% jank | ${summary.frameTimeP95Ms.toStringAsFixed(0)}ms frame p95',
      'score': offender['score'] as double,
    };
  }

  Map<String, dynamic>? _topUiOffender() {
    final summaries = uiTimingReport.summaries;
    if (summaries.isEmpty) {
      return null;
    }
    final ranked = summaries.map((summary) {
      final failureRate =
          summary.count == 0 ? 0.0 : summary.failureCount / summary.count;
      final score = summary.p95Ms * (1 + failureRate * 3);
      return {
        'summary': summary,
        'score': score,
        'failureRate': failureRate,
      };
    }).toList()
      ..sort((left, right) =>
          (right['score'] as double).compareTo(left['score'] as double));
    final offender = ranked.first;
    final summary = offender['summary'] as UiTimingSummary;
    final failureRate = offender['failureRate'] as double;
    return {
      'stream': 'UI Timing',
      'name': '${summary.phase}:${summary.event}',
      'metric':
          '${summary.p95Ms.toStringAsFixed(0)}ms p95 | ${(failureRate * 100).toStringAsFixed(0)}% fail',
      'score': offender['score'] as double,
    };
  }

  CommandLatencyReport _buildCommandLatencyReport() {
    final grouped = <String, List<CommandLatencySample>>{};
    for (final sample in _commandSamples) {
      grouped
          .putIfAbsent(sample.command, () => <CommandLatencySample>[])
          .add(sample);
    }

    final summaries = grouped.entries
        .map((entry) => _summarizeCommand(entry.key, entry.value))
        .toList()
      ..sort((left, right) {
        final byP95 = right.p95Ms.compareTo(left.p95Ms);
        if (byP95 != 0) {
          return byP95;
        }
        return left.command.compareTo(right.command);
      });

    return CommandLatencyReport(
      generatedAt: DateTime.now().toIso8601String(),
      totalSamples: _commandSamples.length,
      commandCount: summaries.length,
      summaries: summaries,
      recentSamples:
          _commandSamples.reversed.take(_maxRecentCommandSamples).toList(),
    );
  }

  DiffRenderMetricsReport _buildDiffRenderMetricsReport() {
    final fallbackCount =
        _diffRenderSamples.where((sample) => sample.fallbackActivated).length;
    final firstPaintValues = _diffRenderSamples
        .map((sample) => sample.firstPaintMs)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final scrollValues = _diffRenderSamples
        .map((sample) => sample.sustainedScrollFps)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final memoryValues = _diffRenderSamples
        .map((sample) => sample.memoryEstimateMb)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final frameValues = _diffRenderSamples
        .map((sample) => sample.frameTimeP95Ms)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final buildValues = _diffRenderSamples
        .map((sample) => sample.buildTimeP95Ms)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final rasterValues = _diffRenderSamples
        .map((sample) => sample.rasterTimeP95Ms)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final totalFrames = _diffRenderSamples.fold<int>(
      0,
      (sum, sample) => sum + sample.frameCount,
    );
    final totalJankyFrames = _diffRenderSamples.fold<int>(
      0,
      (sum, sample) => sum + sample.jankyFrameCount,
    );

    final grouped = <String, List<DiffRenderMetricSample>>{};
    for (final sample in _diffRenderSamples) {
      grouped
          .putIfAbsent(sample.rendererMode, () => <DiffRenderMetricSample>[])
          .add(sample);
    }

    final modeSummaries = grouped.entries
        .map((entry) => _summarizeRendererMode(entry.key, entry.value))
        .toList()
      ..sort((left, right) {
        final byCount = right.sessionCount.compareTo(left.sessionCount);
        if (byCount != 0) {
          return byCount;
        }
        return left.rendererMode.compareTo(right.rendererMode);
      });

    return DiffRenderMetricsReport(
      generatedAt: DateTime.now().toIso8601String(),
      totalSessions: _diffRenderSamples.length,
      fallbackCount: fallbackCount,
      fallbackRate: _diffRenderSamples.isEmpty
          ? 0
          : fallbackCount / _diffRenderSamples.length,
      firstPaintP95Ms: _roundToHundredths(_percentile(firstPaintValues, 95)),
      scrollFpsP50: _roundToHundredths(_percentile(scrollValues, 50)),
      memoryP95Mb: _roundToHundredths(_percentile(memoryValues, 95)),
      frameTimeP95Ms: _roundToHundredths(_percentile(frameValues, 95)),
      buildTimeP95Ms: _roundToHundredths(_percentile(buildValues, 95)),
      rasterTimeP95Ms: _roundToHundredths(_percentile(rasterValues, 95)),
      jankyFrameRate: totalFrames == 0 ? 0 : totalJankyFrames / totalFrames,
      modeSummaries: modeSummaries,
      recentSamples:
          _diffRenderSamples.reversed.take(_maxRecentDiffSessions).toList(),
    );
  }

  UiTimingReport _buildUiTimingReport() {
    final grouped = <String, List<UiTimingSample>>{};
    for (final sample in _uiTimingSamples) {
      final key = '${sample.phase}:${sample.event}';
      grouped.putIfAbsent(key, () => <UiTimingSample>[]).add(sample);
    }

    final summaries = grouped.entries
        .map((entry) => _summarizeUiGroup(entry.key, entry.value))
        .toList()
      ..sort((left, right) {
        final byP95 = right.p95Ms.compareTo(left.p95Ms);
        if (byP95 != 0) {
          return byP95;
        }
        return left.event.compareTo(right.event);
      });

    return UiTimingReport(
      generatedAt: DateTime.now().toIso8601String(),
      totalSamples: _uiTimingSamples.length,
      eventCount: summaries.length,
      summaries: summaries,
      recentSamples:
          _uiTimingSamples.reversed.take(_maxRecentUiSamples).toList(),
    );
  }

  CommandLatencySummary _summarizeCommand(
    String command,
    List<CommandLatencySample> samples,
  ) {
    final durations = samples
        .map((sample) => sample.backendDurationMs ?? sample.roundTripMs)
        .toList()
      ..sort();
    final count = durations.length;
    final successCount = samples.where((sample) => sample.ok).length;
    final failureCount = count - successCount;
    final total = durations.fold<double>(0, (sum, value) => sum + value);
    final lastDuration = samples.isEmpty
        ? 0.0
        : (samples.last.backendDurationMs ?? samples.last.roundTripMs);

    return CommandLatencySummary(
      command: command,
      count: count,
      successCount: successCount,
      failureCount: failureCount,
      p50Ms: _roundToHundredths(_percentile(durations, 50)),
      p95Ms: _roundToHundredths(_percentile(durations, 95)),
      avgMs: _roundToHundredths(count == 0 ? 0.0 : total / count),
      minMs: _roundToHundredths(durations.isEmpty ? 0.0 : durations.first),
      maxMs: _roundToHundredths(durations.isEmpty ? 0.0 : durations.last),
      lastMs: _roundToHundredths(lastDuration),
    );
  }

  DiffRenderModeSummary _summarizeRendererMode(
    String rendererMode,
    List<DiffRenderMetricSample> samples,
  ) {
    final fallbackCount =
        samples.where((sample) => sample.fallbackActivated).length;
    final firstPaintValues = samples
        .map((sample) => sample.firstPaintMs)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final scrollValues = samples
        .map((sample) => sample.sustainedScrollFps)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final memoryValues = samples
        .map((sample) => sample.memoryEstimateMb)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final frameValues = samples
        .map((sample) => sample.frameTimeP95Ms)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final buildValues = samples
        .map((sample) => sample.buildTimeP95Ms)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final rasterValues = samples
        .map((sample) => sample.rasterTimeP95Ms)
        .where((value) => value > 0)
        .toList()
      ..sort();
    final totalFrames =
        samples.fold<int>(0, (sum, sample) => sum + sample.frameCount);
    final totalJankyFrames = samples.fold<int>(
      0,
      (sum, sample) => sum + sample.jankyFrameCount,
    );

    return DiffRenderModeSummary(
      rendererMode: rendererMode,
      sessionCount: samples.length,
      fallbackCount: fallbackCount,
      fallbackRate: samples.isEmpty ? 0 : fallbackCount / samples.length,
      firstPaintP50Ms: _roundToHundredths(_percentile(firstPaintValues, 50)),
      firstPaintP95Ms: _roundToHundredths(_percentile(firstPaintValues, 95)),
      scrollFpsP50: _roundToHundredths(_percentile(scrollValues, 50)),
      scrollFpsP95: _roundToHundredths(_percentile(scrollValues, 95)),
      memoryP50Mb: _roundToHundredths(_percentile(memoryValues, 50)),
      memoryP95Mb: _roundToHundredths(_percentile(memoryValues, 95)),
      frameTimeP95Ms: _roundToHundredths(_percentile(frameValues, 95)),
      buildTimeP95Ms: _roundToHundredths(_percentile(buildValues, 95)),
      rasterTimeP95Ms: _roundToHundredths(_percentile(rasterValues, 95)),
      jankyFrameRate: totalFrames == 0 ? 0 : totalJankyFrames / totalFrames,
    );
  }

  UiTimingSummary _summarizeUiGroup(String key, List<UiTimingSample> samples) {
    final parts = key.split(':');
    final phase = parts.isEmpty ? 'interaction' : parts.first;
    final event = parts.length > 1 ? parts.sublist(1).join(':') : 'unknown';
    final durations = samples.map((sample) => sample.durationMs).toList()
      ..sort();
    final failureCount = samples.where((sample) => !sample.ok).length;
    final total = durations.fold<double>(0, (sum, value) => sum + value);

    return UiTimingSummary(
      event: event,
      phase: phase,
      count: samples.length,
      failureCount: failureCount,
      p50Ms: _roundToHundredths(_percentile(durations, 50)),
      p95Ms: _roundToHundredths(_percentile(durations, 95)),
      avgMs: _roundToHundredths(samples.isEmpty ? 0.0 : total / samples.length),
      minMs: _roundToHundredths(durations.isEmpty ? 0.0 : durations.first),
      maxMs: _roundToHundredths(durations.isEmpty ? 0.0 : durations.last),
      lastMs: _roundToHundredths(
        samples.isEmpty ? 0 : samples.last.durationMs,
      ),
    );
  }

  void _applyRetentionToAll() {
    _applyCommandLatencyRetention();
    _applyDiffRenderRetention();
    _applyUiTimingRetention();
  }

  void _applyCommandLatencyRetention() {
    _trimByTime(_commandSamples, (sample) => sample.recordedAt);
    _trimByCount(_commandSamples, _maxRetainedCommandSamples);
    _trimBySize(
      _commandSamples,
      _retentionMb,
      (samples) => samples.map((sample) => sample.toJson()).toList(),
    );
  }

  void _applyDiffRenderRetention() {
    _trimByTime(_diffRenderSamples, (sample) => sample.recordedAt);
    _trimByCount(_diffRenderSamples, _maxRetainedDiffSessions);
    _trimBySize(
      _diffRenderSamples,
      _retentionMb,
      (samples) => samples.map((sample) => sample.toJson()).toList(),
    );
  }

  void _applyUiTimingRetention() {
    _trimByTime(_uiTimingSamples, (sample) => sample.recordedAt);
    _trimByCount(_uiTimingSamples, _maxRetainedUiSamples);
    _trimBySize(
      _uiTimingSamples,
      _retentionMb,
      (samples) => samples.map((sample) => sample.toJson()).toList(),
    );
  }

  void _trimByTime<T>(List<T> samples, String Function(T sample) timestampOf) {
    final cutoff = DateTime.now().millisecondsSinceEpoch -
        _retentionDays * 24 * 60 * 60 * 1000;
    var firstKeptIndex = 0;
    while (firstKeptIndex < samples.length) {
      final parsed = DateTime.tryParse(timestampOf(samples[firstKeptIndex]));
      if (parsed != null && parsed.millisecondsSinceEpoch >= cutoff) {
        break;
      }
      firstKeptIndex += 1;
    }
    if (firstKeptIndex > 0) {
      samples.removeRange(0, firstKeptIndex);
    }
  }

  void _trimByCount<T>(List<T> samples, int maxItems) {
    if (samples.length > maxItems) {
      samples.removeRange(0, samples.length - maxItems);
    }
  }

  void _trimBySize<T>(
    List<T> samples,
    int retentionMb,
    Object Function(List<T> samples) serializer,
  ) {
    final maxBytes = retentionMb * 1024 * 1024;
    while (samples.isNotEmpty &&
        utf8.encode(jsonEncode(serializer(samples))).length > maxBytes) {
      samples.removeAt(0);
    }
  }

  Future<void> _persistRetentionAndSamples() async {
    await Future.wait([
      _persistRetention(),
      _persistCommandSamples(),
      _persistDiffRenderSamples(),
      _persistUiTimingSamples(),
    ]);
  }

  Future<void> _persistRetention() async {
    final settings = await SettingsStore.load();
    await SettingsStore.persist(
      AppSettingsSnapshot(
        guardrailValue: settings.guardrailValue,
        aiReadOnlyDefault: settings.aiReadOnlyDefault,
        logoAnimatesWhenUnfocused: settings.logoAnimatesWhenUnfocused,
        telemetryRetentionDays: _retentionDays,
        telemetryRetentionMb: _retentionMb,
        updateChannel: settings.updateChannel,
        crashReportingEnabled: settings.crashReportingEnabled,
        themeId: settings.themeId,
        keybindingProfile: settings.keybindingProfile,
        sidebarWidthPx: settings.sidebarWidthPx,
        sidebarPosition: settings.sidebarPosition,
        utilityDrawerDefaultExpanded: settings.utilityDrawerDefaultExpanded,
        utilityDrawerHeightPx: settings.utilityDrawerHeightPx,
        autoExpandOperationLogs: settings.autoExpandOperationLogs,
      ),
    );
  }

  Future<void> _persistCommandSamples() async {
    final payload = _commandSamples.map((sample) => sample.toJson()).toList();
    await LocalTelemetryStore.writeList(_commandLatencyFileName, payload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_commandLatencyStorageKey);
  }

  Future<void> _persistDiffRenderSamples() async {
    final payload =
        _diffRenderSamples.map((sample) => sample.toJson()).toList();
    await LocalTelemetryStore.writeList(_diffRenderFileName, payload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_diffRenderStorageKey);
  }

  Future<void> _persistUiTimingSamples() async {
    final payload = _uiTimingSamples.map((sample) => sample.toJson()).toList();
    await LocalTelemetryStore.writeList(_uiTimingFileName, payload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_uiTimingStorageKey);
  }

  Future<List<CommandLatencySample>> _loadCommandSamples(
    SharedPreferences prefs,
  ) async {
    final raw = await LocalTelemetryStore.readList(_commandLatencyFileName);
    if (raw.isNotEmpty) {
      return raw
          .map(_normalizeCommandSample)
          .whereType<CommandLatencySample>()
          .toList();
    }
    return _decodeCommandSamples(prefs.getString(_commandLatencyStorageKey));
  }

  Future<List<DiffRenderMetricSample>> _loadDiffRenderSamples(
    SharedPreferences prefs,
  ) async {
    final raw = await LocalTelemetryStore.readList(_diffRenderFileName);
    if (raw.isNotEmpty) {
      return raw
          .map(_normalizeDiffRenderSample)
          .whereType<DiffRenderMetricSample>()
          .toList();
    }
    return _decodeDiffRenderSamples(prefs.getString(_diffRenderStorageKey));
  }

  Future<List<UiTimingSample>> _loadUiTimingSamples(
    SharedPreferences prefs,
  ) async {
    final raw = await LocalTelemetryStore.readList(_uiTimingFileName);
    if (raw.isNotEmpty) {
      return raw
          .map(_normalizeUiTimingSample)
          .whereType<UiTimingSample>()
          .toList();
    }
    return _decodeUiTimingSamples(prefs.getString(_uiTimingStorageKey));
  }

  Future<void> _refreshBackendCommandTelemetrySnapshot({
    bool enforceRetention = false,
  }) async {
    if (enforceRetention) {
      await CommandTelemetryStore.enforceRetentionPolicy();
    }
    _backendCommandTelemetrySnapshot =
        await CommandTelemetryStore.getSnapshot();
  }

  void _enqueueBackgroundIo(Future<void> Function() action) {
    _backgroundIo = _backgroundIo.then((_) => action()).catchError((error) {
      debugPrint('Diagnostics background IO failed: $error');
    });
  }

  void _invalidateAllCachedReports() {
    _cachedCommandLatencyReport = null;
    _cachedDiffRenderMetricsReport = null;
    _cachedUiTimingReport = null;
  }

  void _scheduleBackendSnapshotRefresh({
    Duration delay = const Duration(milliseconds: 750),
  }) {
    _backendSnapshotRefreshTimer?.cancel();
    _backendSnapshotRefreshTimer = Timer(delay, () {
      _backendSnapshotRefreshTimer = null;
      _enqueueBackgroundIo(() async {
        await _refreshBackendCommandTelemetrySnapshot();
        notifyListeners();
      });
    });
  }

  List<CommandLatencySample> _decodeCommandSamples(String? raw) {
    final decoded = _decodeJsonList(raw);
    return decoded
        .map(_normalizeCommandSample)
        .whereType<CommandLatencySample>()
        .toList();
  }

  List<DiffRenderMetricSample> _decodeDiffRenderSamples(String? raw) {
    final decoded = _decodeJsonList(raw);
    return decoded
        .map(_normalizeDiffRenderSample)
        .whereType<DiffRenderMetricSample>()
        .toList();
  }

  List<UiTimingSample> _decodeUiTimingSamples(String? raw) {
    final decoded = _decodeJsonList(raw);
    return decoded
        .map(_normalizeUiTimingSample)
        .whereType<UiTimingSample>()
        .toList();
  }

  List<dynamic> _decodeJsonList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  CommandLatencySample? _normalizeCommandSample(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final command = raw['command'];
    final ok = raw['ok'];
    final roundTripMs = raw['roundTripMs'];
    final recordedAt = raw['recordedAt'];
    if (command is! String ||
        ok is! bool ||
        roundTripMs is! num ||
        recordedAt is! String) {
      return null;
    }

    return CommandLatencySample(
      command: command,
      ok: ok,
      errorCode: raw['errorCode'] is String ? raw['errorCode'] as String : null,
      requestId: raw['requestId'] is String ? raw['requestId'] as String : null,
      roundTripMs: _roundToHundredths(_clampNumber(roundTripMs.toDouble())),
      backendDurationMs: raw['backendDurationMs'] is num
          ? _roundToHundredths(
              _clampNumber((raw['backendDurationMs'] as num).toDouble()),
            )
          : null,
      recordedAt: recordedAt,
    );
  }

  DiffRenderMetricSample? _normalizeDiffRenderSample(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final diffId = raw['diffId'];
    final path = raw['path'];
    final rendererMode = raw['rendererMode'];
    final recordedAt = raw['recordedAt'];
    if (diffId is! String ||
        path is! String ||
        rendererMode is! String ||
        recordedAt is! String) {
      return null;
    }

    return DiffRenderMetricSample(
      diffId: diffId,
      path: path,
      rendererMode: _normalizeRenderMode(rendererMode),
      changedLines: _clampInt(_numToInt(raw['changedLines'])),
      payloadBytes: _clampInt(_numToInt(raw['payloadBytes'])),
      firstPaintMs:
          _roundToHundredths(_clampNumber(_numToDouble(raw['firstPaintMs']))),
      sustainedScrollFps: _roundToHundredths(
        _clampNumber(_numToDouble(raw['sustainedScrollFps'])),
      ),
      memoryEstimateMb: _roundToHundredths(
        _clampNumber(_numToDouble(raw['memoryEstimateMb'])),
      ),
      frameTimeP95Ms:
          _roundToHundredths(_clampNumber(_numToDouble(raw['frameTimeP95Ms']))),
      buildTimeP95Ms:
          _roundToHundredths(_clampNumber(_numToDouble(raw['buildTimeP95Ms']))),
      rasterTimeP95Ms: _roundToHundredths(
        _clampNumber(_numToDouble(raw['rasterTimeP95Ms'])),
      ),
      frameCount: _clampInt(_numToInt(raw['frameCount'])),
      jankyFrameCount: _clampInt(_numToInt(raw['jankyFrameCount'])),
      fallbackActivated: raw['fallbackActivated'] == true,
      recordedAt: recordedAt,
    );
  }

  UiTimingSample? _normalizeUiTimingSample(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final event = raw['event'];
    final phase = raw['phase'];
    final ok = raw['ok'];
    final durationMs = raw['durationMs'];
    final recordedAt = raw['recordedAt'];
    if (event is! String ||
        phase is! String ||
        ok is! bool ||
        durationMs is! num ||
        recordedAt is! String) {
      return null;
    }

    return UiTimingSample(
      event: _normalizeEvent(event),
      phase: _normalizePhase(phase),
      ok: ok,
      errorCode: raw['errorCode'] is String ? raw['errorCode'] as String : null,
      durationMs: _roundToHundredths(_clampNumber(durationMs.toDouble())),
      recordedAt: recordedAt,
    );
  }

  int _normalizeRetentionDays(int? value) {
    return (value ?? _defaultRetentionDays)
        .clamp(_minRetentionDays, _maxRetentionDays);
  }

  int _normalizeRetentionMb(int? value) {
    return (value ?? _defaultRetentionMb)
        .clamp(_minRetentionMb, _maxRetentionMb);
  }

  String _normalizeOptionalLabel(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? '' : normalized;
  }

  String _normalizeRenderMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'canvas' ||
        normalized == 'dom' ||
        normalized == 'fallback') {
      return normalized;
    }
    return 'dom';
  }

  String _normalizeEvent(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _normalizePhase(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? 'interaction' : normalized;
  }

  double _percentile(List<double> sortedValues, int percentileValue) {
    if (sortedValues.isEmpty) {
      return 0;
    }
    final index = (percentileValue / 100) * (sortedValues.length - 1);
    final lowerIndex = index.floor();
    final upperIndex = index.ceil();
    final lowerValue = sortedValues[lowerIndex];
    final upperValue = sortedValues[upperIndex];
    if (lowerIndex == upperIndex) {
      return lowerValue;
    }
    final weight = index - lowerIndex;
    return lowerValue + (upperValue - lowerValue) * weight;
  }

  double _roundToHundredths(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  String _ellipsize(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    if (maxLength <= 3) {
      return normalized.substring(0, maxLength);
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  double _clampNumber(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return value < 0 ? 0 : value;
  }

  int _clampInt(int value) => value < 0 ? 0 : value;

  int _numToInt(dynamic value) {
    if (value is num) {
      return value.round();
    }
    return 0;
  }

  double _numToDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }
}
