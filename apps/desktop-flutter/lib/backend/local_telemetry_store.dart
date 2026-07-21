// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'atomic_write.dart';
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
    // Atomic temp-then-rename so a crash mid-write can't leave a torn file
    // that readList would silently fall back to empty over (see
    // atomic_write.dart).
    await writeFileAtomicString(file, jsonEncode(items));
  }

  static Future<void> clear(String fileName) async {
    await writeList(fileName, const <dynamic>[]);
  }

  static Future<File> _file(String fileName) async {
    final dir = await StoragePaths.gdpuDataDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }
}
