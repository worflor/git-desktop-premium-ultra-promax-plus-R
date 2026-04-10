import 'dart:convert';
import 'dart:io';

import 'storage_paths.dart';

class LocalTelemetryStore {
  static Future<List<dynamic>> readList(String fileName) async {
    final file = await _file(fileName);
    if (!await file.exists()) {
      return const <dynamic>[];
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  static Future<void> writeList(String fileName, List<dynamic> items) async {
    final file = await _file(fileName);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(items), flush: true);
  }

  static Future<void> clear(String fileName) async {
    await writeList(fileName, const <dynamic>[]);
  }

  static Future<File> _file(String fileName) async {
    final dir = await StoragePaths.gdpuDataDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }
}
