import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'settings_store.dart';
import 'storage_paths.dart';

class CommandTelemetrySampleData {
  final String id;
  final String scope;
  final String command;
  final bool ok;
  final String? errorCode;
  final int durationMs;
  final String createdAt;

  const CommandTelemetrySampleData({
    required this.id,
    required this.scope,
    required this.command,
    required this.ok,
    required this.durationMs,
    required this.createdAt,
    this.errorCode,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'scope': scope,
        'command': command,
        'ok': ok,
        if (errorCode != null) 'errorCode': errorCode,
        'durationMs': durationMs,
        'createdAt': createdAt,
      };
}

class CommandTelemetrySummaryData {
  final String scope;
  final String command;
  final int sampleCount;
  final int failureCount;
  final int p50Ms;
  final int p95Ms;
  final int lastDurationMs;
  final String lastSeenAt;

  const CommandTelemetrySummaryData({
    required this.scope,
    required this.command,
    required this.sampleCount,
    required this.failureCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.lastDurationMs,
    required this.lastSeenAt,
  });

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'command': command,
        'sampleCount': sampleCount,
        'failureCount': failureCount,
        'p50Ms': p50Ms,
        'p95Ms': p95Ms,
        'lastDurationMs': lastDurationMs,
        'lastSeenAt': lastSeenAt,
      };
}

class CommandTelemetrySnapshotData {
  final String generatedAt;
  final int sampleCount;
  final List<CommandTelemetrySummaryData> summaries;
  final List<CommandTelemetrySampleData> recentSamples;

  const CommandTelemetrySnapshotData({
    required this.generatedAt,
    required this.sampleCount,
    required this.summaries,
    required this.recentSamples,
  });

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt,
        'sampleCount': sampleCount,
        'summaries': summaries.map((summary) => summary.toJson()).toList(),
        'recentSamples':
            recentSamples.map((sample) => sample.toJson()).toList(),
      };
}

class CommandTelemetryMaintenanceData {
  final String operation;
  final int affectedSamples;
  final int sampleCount;

  const CommandTelemetryMaintenanceData({
    required this.operation,
    required this.affectedSamples,
    required this.sampleCount,
  });

  Map<String, dynamic> toJson() => {
        'operation': operation,
        'affectedSamples': affectedSamples,
        'sampleCount': sampleCount,
      };
}

class CommandTelemetryStore {
  static const String _fileName = 'command_telemetry.jsonl';
  static const int _defaultRetentionDays = 30;
  static const int _defaultRetentionMb = 128;
  static const int _defaultRecentLimit = 200;
  static const int _maxRecentLimit = 1000;
  static Future<void> _io = Future<void>.value();

  static Future<void> recordSample({
    required String scope,
    required String command,
    required bool ok,
    required double durationMs,
    String? errorCode,
  }) {
    return _serialize<Null>(() async {
      final normalizedScope = _normalizeScope(scope);
      final normalizedCommand = _normalizeCommand(command);
      if (normalizedCommand.isEmpty) {
        return null;
      }

      final samples = await _loadSamples();
      samples.add(
        _StoredCommandTelemetrySample(
          id: _sampleId(),
          scope: normalizedScope,
          command: normalizedCommand,
          ok: ok,
          errorCode: _normalizeOptionalLabel(errorCode),
          durationMs: _sanitizeDuration(durationMs),
          createdAt: DateTime.now().toUtc().toIso8601String(),
          serializedLen: 0,
        ),
      );
      final latest = samples.removeLast()._withSerializedLen();
      samples.add(latest);
      _applyRetentionPolicy(samples, await _loadRetentionPolicy());
      await _persistSamples(samples);
      return null;
    });
  }

  static Future<CommandTelemetrySnapshotData> getSnapshot({
    int recentLimit = _defaultRecentLimit,
  }) {
    return _serialize(() async {
      final samples = await _loadSamples();
      _applyRetentionPolicy(samples, await _loadRetentionPolicy());
      await _persistSamples(samples);

      final limit = recentLimit.clamp(1, _maxRecentLimit).toInt();
      final start = samples.length > limit ? samples.length - limit : 0;
      return CommandTelemetrySnapshotData(
        generatedAt: DateTime.now().toUtc().toIso8601String(),
        sampleCount: samples.length,
        summaries: _summaries(samples),
        recentSamples: samples
            .sublist(start)
            .map(
              (sample) => CommandTelemetrySampleData(
                id: sample.id,
                scope: sample.scope,
                command: sample.command,
                ok: sample.ok,
                errorCode: sample.errorCode,
                durationMs: sample.durationMs,
                createdAt: sample.createdAt,
              ),
            )
            .toList(),
      );
    });
  }

  static Future<CommandTelemetryMaintenanceData> clearSamples() {
    return _serialize(() async {
      final samples = await _loadSamples();
      final affectedSamples = samples.length;
      await _persistSamples(const <_StoredCommandTelemetrySample>[]);
      return CommandTelemetryMaintenanceData(
        operation: 'clear',
        affectedSamples: affectedSamples,
        sampleCount: 0,
      );
    });
  }

  static Future<CommandTelemetryMaintenanceData> enforceRetentionPolicy() {
    return _serialize(() async {
      final samples = await _loadSamples();
      _applyRetentionPolicy(samples, await _loadRetentionPolicy());
      await _persistSamples(samples);
      return CommandTelemetryMaintenanceData(
        operation: 'retention',
        affectedSamples: 0,
        sampleCount: samples.length,
      );
    });
  }

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _io = _io.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<_RetentionPolicy> _loadRetentionPolicy() async {
    try {
      final settings = await SettingsStore.load();
      return _RetentionPolicy(
        maxAgeDays: settings.telemetryRetentionDays.clamp(1, 365).toInt(),
        maxBytes:
            settings.telemetryRetentionMb.clamp(16, 4096).toInt() * 1024 * 1024,
      );
    } catch (_) {
      return const _RetentionPolicy(
        maxAgeDays: _defaultRetentionDays,
        maxBytes: _defaultRetentionMb * 1024 * 1024,
      );
    }
  }

  static List<CommandTelemetrySummaryData> _summaries(
    List<_StoredCommandTelemetrySample> samples,
  ) {
    final grouped = <String, _TelemetryAggregate>{};
    for (final sample in samples) {
      final key = '${sample.scope}:${sample.command}';
      final aggregate = grouped.putIfAbsent(
          key, () => _TelemetryAggregate(sample.scope, sample.command));
      aggregate.durations.add(sample.durationMs);
      if (!sample.ok) {
        aggregate.failureCount += 1;
      }
      aggregate.lastDurationMs = sample.durationMs;
      aggregate.lastSeenAt = sample.createdAt;
    }

    final summaries = grouped.values.map((aggregate) {
      aggregate.durations.sort();
      return CommandTelemetrySummaryData(
        scope: aggregate.scope,
        command: aggregate.command,
        sampleCount: aggregate.durations.length,
        failureCount: aggregate.failureCount,
        p50Ms: _percentile(aggregate.durations, 50),
        p95Ms: _percentile(aggregate.durations, 95),
        lastDurationMs: aggregate.lastDurationMs,
        lastSeenAt: aggregate.lastSeenAt,
      );
    }).toList();

    summaries.sort((left, right) {
      final scopeCompare = left.scope.compareTo(right.scope);
      if (scopeCompare != 0) {
        return scopeCompare;
      }
      return left.command.compareTo(right.command);
    });
    return summaries;
  }

  static void _applyRetentionPolicy(
    List<_StoredCommandTelemetrySample> samples,
    _RetentionPolicy policy,
  ) {
    final cutoff =
        DateTime.now().toUtc().subtract(Duration(days: policy.maxAgeDays));
    samples.removeWhere((sample) {
      final createdAt = DateTime.tryParse(sample.createdAt)?.toUtc();
      return createdAt == null || createdAt.isBefore(cutoff);
    });

    if (samples.isEmpty) {
      return;
    }

    final maxBytes = policy.maxBytes < 1024 ? 1024 : policy.maxBytes;
    var keptBytes = 0;
    var keepStart = samples.length;

    for (var index = samples.length - 1; index >= 0; index -= 1) {
      final sampleBytes = samples[index].serializedLen + 1;
      if (sampleBytes > maxBytes) {
        keepStart = index + 1;
        break;
      }
      if (keptBytes + sampleBytes > maxBytes) {
        break;
      }
      keptBytes += sampleBytes;
      keepStart = index;
    }

    if (keepStart > 0) {
      samples.removeRange(0, keepStart);
    }
  }

  static int _percentile(List<int> sortedDurations, int percentile) {
    if (sortedDurations.isEmpty) {
      return 0;
    }
    final scaled = sortedDurations.length * percentile;
    final rank = (scaled / 100).ceil();
    final index =
        rank <= 0 ? 0 : (rank - 1).clamp(0, sortedDurations.length - 1);
    return sortedDurations[index];
  }

  static Future<List<_StoredCommandTelemetrySample>> _loadSamples() async {
    final file = await _file();
    if (!await file.exists()) {
      return <_StoredCommandTelemetrySample>[];
    }

    final lines = await file.readAsLines();
    final samples = <_StoredCommandTelemetrySample>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is Map<String, dynamic>) {
          final sample = _StoredCommandTelemetrySample.tryFromJson(parsed);
          if (sample != null) {
            samples.add(sample);
          }
        } else if (parsed is Map) {
          final sample = _StoredCommandTelemetrySample.tryFromJson(
            Map<String, dynamic>.from(parsed),
          );
          if (sample != null) {
            samples.add(sample);
          }
        }
      } catch (_) {}
    }
    return samples;
  }

  static Future<void> _persistSamples(
    List<_StoredCommandTelemetrySample> samples,
  ) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    if (samples.isEmpty) {
      await file.writeAsString('', flush: true);
      return;
    }

    final sink = file.openWrite();
    try {
      for (final sample in samples) {
        sink.writeln(jsonEncode(sample.toJson()));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static Future<File> _file() async {
    final dir = await StoragePaths.gdpuDataDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static String _normalizeScope(String value) {
    final normalized = _normalizeAsciiLabel(value);
    return normalized.isEmpty ? 'backend' : normalized;
  }

  static String _normalizeCommand(String value) {
    return _normalizeAsciiLabel(value);
  }

  static String _normalizeAsciiLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final lowerCased = trimmed.toLowerCase();
    return trimmed == lowerCased ? trimmed : lowerCased;
  }

  static String? _normalizeOptionalLabel(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static int _sanitizeDuration(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return math.max(0, value.round());
  }

  static String _sampleId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final tail = micros.toRadixString(16).padLeft(16, '0');
    return '${tail.substring(0, 8)}-${tail.substring(8)}';
  }
}

class _StoredCommandTelemetrySample {
  final String id;
  final String scope;
  final String command;
  final bool ok;
  final String? errorCode;
  final int durationMs;
  final String createdAt;
  final int serializedLen;

  const _StoredCommandTelemetrySample({
    required this.id,
    required this.scope,
    required this.command,
    required this.ok,
    required this.durationMs,
    required this.createdAt,
    required this.serializedLen,
    this.errorCode,
  });

  static _StoredCommandTelemetrySample? tryFromJson(
    Map<String, dynamic> json,
  ) {
    final id = json['id'];
    final scope = json['scope'];
    final command = json['command'];
    final ok = json['ok'];
    final durationMs = json['durationMs'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        scope is! String ||
        command is! String ||
        ok is! bool ||
        durationMs is! num ||
        createdAt is! String) {
      return null;
    }

    return _StoredCommandTelemetrySample(
      id: id,
      scope: scope,
      command: command,
      ok: ok,
      errorCode:
          json['errorCode'] is String ? json['errorCode'] as String : null,
      durationMs: durationMs.toInt(),
      createdAt: createdAt,
      serializedLen: 0,
    )._withSerializedLen();
  }

  _StoredCommandTelemetrySample _withSerializedLen() {
    return _StoredCommandTelemetrySample(
      id: id,
      scope: scope,
      command: command,
      ok: ok,
      errorCode: errorCode,
      durationMs: durationMs,
      createdAt: createdAt,
      serializedLen: utf8.encode(jsonEncode(toJson())).length,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scope': scope,
        'command': command,
        'ok': ok,
        if (errorCode != null) 'errorCode': errorCode,
        'durationMs': durationMs,
        'createdAt': createdAt,
      };
}

class _TelemetryAggregate {
  final String scope;
  final String command;
  final List<int> durations = <int>[];
  int failureCount = 0;
  int lastDurationMs = 0;
  String lastSeenAt = '';

  _TelemetryAggregate(this.scope, this.command);
}

class _RetentionPolicy {
  final int maxAgeDays;
  final int maxBytes;

  const _RetentionPolicy({
    required this.maxAgeDays,
    required this.maxBytes,
  });
}
