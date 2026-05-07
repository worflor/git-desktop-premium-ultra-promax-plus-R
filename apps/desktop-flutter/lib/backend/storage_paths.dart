import 'dart:io';

import 'package:meta/meta.dart';

class StoragePaths {
  static const String _appDataDirName = 'gdpu';

  static Future<Directory> gdpuDataDir() async {
    final overridePath = _envNonEmpty('GDPU_DATA_DIR');
    if (overridePath != null) {
      return Directory(overridePath);
    }

    if (Platform.isWindows) {
      final appData = _envNonEmpty('APPDATA');
      if (appData != null) {
        return Directory(appData)
            .uri
            .resolve(_appDataDirName)
            .toFilePath()
            .let(Directory.new);
      }

      final userProfile = _envNonEmpty('USERPROFILE');
      if (userProfile != null) {
        return Directory(
          '${Directory(userProfile).path}${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming${Platform.pathSeparator}$_appDataDirName',
        );
      }
    }

    if (Platform.isMacOS) {
      final home = _envNonEmpty('HOME');
      if (home != null) {
        return Directory(
          '${Directory(home).path}${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}$_appDataDirName',
        );
      }
    }

    final xdgDataHome = _envNonEmpty('XDG_DATA_HOME');
    if (xdgDataHome != null) {
      return Directory(xdgDataHome)
          .uri
          .resolve(_appDataDirName)
          .toFilePath()
          .let(Directory.new);
    }

    final home = _envNonEmpty('HOME');
    if (home != null) {
      return Directory(
        '${Directory(home).path}${Platform.pathSeparator}.local${Platform.pathSeparator}share${Platform.pathSeparator}$_appDataDirName',
      );
    }

    throw StateError('failed to resolve cross-platform app data directory');
  }

  static Directory? gdpuDataDirSync() {
    final overridePath = _envNonEmpty('GDPU_DATA_DIR');
    if (overridePath != null) return Directory(overridePath);
    if (Platform.isWindows) {
      final appData = _envNonEmpty('APPDATA');
      if (appData != null) {
        return Directory(appData)
            .uri
            .resolve(_appDataDirName)
            .toFilePath()
            .let(Directory.new);
      }
      final userProfile = _envNonEmpty('USERPROFILE');
      if (userProfile != null) {
        return Directory(
          '${Directory(userProfile).path}${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming${Platform.pathSeparator}$_appDataDirName',
        );
      }
    }
    if (Platform.isMacOS) {
      final home = _envNonEmpty('HOME');
      if (home != null) {
        return Directory(
          '${Directory(home).path}${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}$_appDataDirName',
        );
      }
    }
    final xdgDataHome = _envNonEmpty('XDG_DATA_HOME');
    if (xdgDataHome != null) {
      return Directory(xdgDataHome)
          .uri
          .resolve(_appDataDirName)
          .toFilePath()
          .let(Directory.new);
    }
    final home = _envNonEmpty('HOME');
    if (home != null) {
      return Directory(
        '${Directory(home).path}${Platform.pathSeparator}.local${Platform.pathSeparator}share${Platform.pathSeparator}$_appDataDirName',
      );
    }
    return null;
  }

  /// Removes the entire app data directory (settings, ai prefs, telemetry,
  /// engram caches — everything under [gdpuDataDir]). The user's repos and
  /// any state outside this dir are untouched.
  ///
  /// Idempotent: a missing dir is a no-op. Callers that intend a "factory
  /// reset" workflow are responsible for terminating the process
  /// immediately afterwards — any state object still in memory will
  /// happily re-persist itself if given a chance, recreating the file
  /// we just deleted.
  static Future<void> purgeDataDir() async => deleteIfExists(await gdpuDataDir());

  /// Recursively removes [dir] when it exists, otherwise no-ops. Exposed
  /// for tests so they can exercise the idempotency contract without
  /// touching the real app data dir on the developer's machine.
  @visibleForTesting
  static Future<void> deleteIfExists(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Synchronous IPC directory path. The CLI entry point (`bin/manifold_cli.dart`)
  /// can't easily await, so this provides the same resolution logic as
  /// [gdpuDataDir] but returns a plain path string and appends `/ipc`.
  /// Returns null when no env vars resolve (same failure mode as gdpuDataDir
  /// throwing StateError, but non-throwing for the CLI's best-effort flow).
  static String? ipcDirPathSync() {
    final overridePath = _envNonEmpty('GDPU_DATA_DIR');
    if (overridePath != null) {
      return '$overridePath${Platform.pathSeparator}ipc';
    }
    if (Platform.isWindows) {
      final appData = _envNonEmpty('APPDATA');
      if (appData != null) {
        return '$appData${Platform.pathSeparator}$_appDataDirName${Platform.pathSeparator}ipc';
      }
      final userProfile = _envNonEmpty('USERPROFILE');
      if (userProfile != null) {
        return '$userProfile${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming${Platform.pathSeparator}$_appDataDirName${Platform.pathSeparator}ipc';
      }
    }
    if (Platform.isMacOS) {
      final home = _envNonEmpty('HOME');
      if (home != null) {
        return '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}$_appDataDirName${Platform.pathSeparator}ipc';
      }
    }
    final xdgDataHome = _envNonEmpty('XDG_DATA_HOME');
    if (xdgDataHome != null) {
      return '$xdgDataHome${Platform.pathSeparator}$_appDataDirName${Platform.pathSeparator}ipc';
    }
    final home = _envNonEmpty('HOME');
    if (home != null) {
      return '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share${Platform.pathSeparator}$_appDataDirName${Platform.pathSeparator}ipc';
    }
    return null;
  }

  static String? _envNonEmpty(String name) {
    final value = Platform.environment[name]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

extension<T> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}
