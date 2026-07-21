// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'atomic_write.dart';
import 'json_safety.dart';
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
        apiKey: asStringOr(json['apiKey'], ''),
        baseUrl: asStringOrNull(json['baseUrl']),
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
      final map = asMapOrNull(e.value);
      if (map != null) {
        final entry = AiApiKeyEntry.fromJson(map);
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
    // Shared atomic choreography (unique temp name — a fixed `.tmp` races
    // concurrent writers cross-process); permissions are stamped on the temp
    // before it becomes visible under the target name.
    await writeFileAtomicString(
      file,
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      beforeRename: _restrictPermissions,
    );
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
