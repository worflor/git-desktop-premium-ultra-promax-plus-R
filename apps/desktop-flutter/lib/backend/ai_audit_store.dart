import 'dart:convert';
import 'dart:io';

import 'storage_paths.dart';

class AiAuditEntryData {
  final String id;
  final String event;
  final String providerId;
  final String repositoryHint;
  final String? diffScopePath;
  final String promptPreview;
  final String outputPreview;
  final bool ok;
  final String? errorCode;
  final String createdAt;

  const AiAuditEntryData({
    required this.id,
    required this.event,
    required this.providerId,
    required this.repositoryHint,
    required this.diffScopePath,
    required this.promptPreview,
    required this.outputPreview,
    required this.ok,
    required this.errorCode,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'event': event,
        'providerId': providerId,
        'repositoryHint': repositoryHint,
        if (diffScopePath != null) 'diffScopePath': diffScopePath,
        'promptPreview': promptPreview,
        'outputPreview': outputPreview,
        'ok': ok,
        if (errorCode != null) 'errorCode': errorCode,
        'createdAt': createdAt,
      };

  factory AiAuditEntryData.fromJson(Map<String, dynamic> json) {
    return AiAuditEntryData(
      id: json['id'] as String,
      event: json['event'] as String,
      providerId: json['providerId'] as String,
      repositoryHint: json['repositoryHint'] as String,
      diffScopePath: json['diffScopePath'] is String
          ? json['diffScopePath'] as String
          : null,
      promptPreview: json['promptPreview'] as String,
      outputPreview: json['outputPreview'] as String,
      ok: json['ok'] == true,
      errorCode:
          json['errorCode'] is String ? json['errorCode'] as String : null,
      createdAt: json['createdAt'] as String,
    );
  }
}

class AiAuditListData {
  final String generatedAt;
  final int sampleCount;
  final List<AiAuditEntryData> entries;

  const AiAuditListData({
    required this.generatedAt,
    required this.sampleCount,
    required this.entries,
  });
}

class AiAuditStore {
  static const String _fileName = 'ai_review_audit.jsonl';
  static const int _maxAuditEntries = 5000;
  static const int _maxAuditBytes = 16 * 1024 * 1024;
  static const int _retentionDays = 90;

  static Future<AiAuditListData> getEntries({int limit = 200}) async {
    final entries = await _loadEntries();
    final retained = _applyRetention(entries);
    await _persistEntries(retained);
    final normalizedLimit = limit.clamp(1, 1000);
    final start = retained.length > normalizedLimit
        ? retained.length - normalizedLimit
        : 0;
    return AiAuditListData(
      generatedAt: DateTime.now().toIso8601String(),
      sampleCount: retained.length,
      entries: retained.sublist(start),
    );
  }

  static Future<int> clearEntries() async {
    final entries = await _loadEntries();
    await _persistEntries(const []);
    return entries.length;
  }

  static Future<void> recordEntry(AiAuditEntryData entry) async {
    final entries = await _loadEntries();
    entries.add(entry);
    final retained = _applyRetention(entries);
    await _persistEntries(retained);
  }

  static Future<List<AiAuditEntryData>> _loadEntries() async {
    final file = await _file();
    if (!await file.exists()) {
      return <AiAuditEntryData>[];
    }
    final lines = await file.readAsLines();
    final entries = <AiAuditEntryData>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is Map) {
          entries.add(
              AiAuditEntryData.fromJson(Map<String, dynamic>.from(parsed)));
        }
      } catch (_) {}
    }
    return entries;
  }

  static List<AiAuditEntryData> _applyRetention(
      List<AiAuditEntryData> entries) {
    final cutoff =
        DateTime.now().subtract(const Duration(days: _retentionDays));
    final retained = entries.where((entry) {
      final parsed = DateTime.tryParse(entry.createdAt);
      return parsed != null && !parsed.isBefore(cutoff);
    }).toList();

    if (retained.length > _maxAuditEntries) {
      retained.removeRange(0, retained.length - _maxAuditEntries);
    }

    while (retained.isNotEmpty &&
        utf8
                .encode(retained
                    .map((entry) => jsonEncode(entry.toJson()))
                    .join('\n'))
                .length >
            _maxAuditBytes) {
      retained.removeAt(0);
    }

    return retained;
  }

  static Future<void> _persistEntries(List<AiAuditEntryData> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    for (final entry in entries) {
      sink.writeln(jsonEncode(entry.toJson()));
    }
    await sink.flush();
    await sink.close();
  }

  static Future<File> _file() async {
    final dir = await StoragePaths.gdpuDataDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }
}
