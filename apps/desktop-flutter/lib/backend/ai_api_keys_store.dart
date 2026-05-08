import 'dart:convert';
import 'dart:io';

import 'storage_paths.dart';

class AiApiKeyEntry {
  final String apiKey;
  final String? baseUrl;
  const AiApiKeyEntry({required this.apiKey, this.baseUrl});

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        if (baseUrl != null && baseUrl!.trim().isNotEmpty) 'baseUrl': baseUrl,
      };

  factory AiApiKeyEntry.fromJson(Map<String, dynamic> json) => AiApiKeyEntry(
        apiKey: (json['apiKey'] as String?) ?? '',
        baseUrl: json['baseUrl'] as String?,
      );
}

class AiApiKeysSnapshot {
  final Map<String, AiApiKeyEntry> entries;
  const AiApiKeysSnapshot({required this.entries});

  factory AiApiKeysSnapshot.empty() =>
      const AiApiKeysSnapshot(entries: {});

  Map<String, dynamic> toJson() =>
      entries.map((k, v) => MapEntry(k, v.toJson()));

  factory AiApiKeysSnapshot.fromJson(Map<String, dynamic> json) {
    final entries = <String, AiApiKeyEntry>{};
    for (final e in json.entries) {
      if (e.value is Map<String, dynamic>) {
        final entry = AiApiKeyEntry.fromJson(e.value as Map<String, dynamic>);
        if (entry.apiKey.trim().isNotEmpty) {
          entries[e.key] = entry;
        }
      }
    }
    return AiApiKeysSnapshot(entries: entries);
  }

  AiApiKeyEntry? operator [](String providerId) => entries[providerId];

  AiApiKeysSnapshot withEntry(String providerId, AiApiKeyEntry entry) {
    if (entry.apiKey.trim().isEmpty) {
      return withoutEntry(providerId);
    }
    return AiApiKeysSnapshot(entries: {...entries, providerId: entry});
  }

  AiApiKeysSnapshot withoutEntry(String providerId) {
    final next = Map<String, AiApiKeyEntry>.from(entries)..remove(providerId);
    return AiApiKeysSnapshot(entries: next);
  }
}

class AiApiKeysStore {
  static const String _fileName = 'api_keys.json';

  static Future<AiApiKeysSnapshot> load() async {
    final file = await _keysFile();
    if (!await file.exists()) {
      return AiApiKeysSnapshot.empty();
    }
    try {
      final raw = await file.readAsString();
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return AiApiKeysSnapshot.fromJson(parsed);
      }
    } catch (_) {}
    return AiApiKeysSnapshot.empty();
  }

  static Future<void> persist(AiApiKeysSnapshot snapshot) async {
    final file = await _keysFile();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      flush: true,
    );
    await _restrictPermissions(tmp);
    await tmp.rename(file.path);
  }

  static Future<void> _restrictPermissions(File file) async {
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        final user = Platform.environment['USERNAME'];
        if (user == null || user.trim().isEmpty) {
          stderr.writeln(
              'api_keys: USERNAME not set, skipping permission restriction');
          return;
        }
        result = await Process.run('icacls', [
          file.path,
          '/reset',
          '/inheritance:r',
          '/grant:r',
          '$user:(R,W)',
        ]);
      } else {
        result = await Process.run('chmod', ['600', file.path]);
      }
      if (result.exitCode != 0) {
        stderr.writeln(
            'api_keys: permission restriction failed (exit ${result.exitCode})');
      }
    } catch (e) {
      stderr.writeln('api_keys: permission restriction error: $e');
    }
  }

  static Future<File> _keysFile() async {
    final dataDir = await StoragePaths.gdpuDataDir();
    return File(
      '${dataDir.path}${Platform.pathSeparator}ai${Platform.pathSeparator}$_fileName',
    );
  }
}
