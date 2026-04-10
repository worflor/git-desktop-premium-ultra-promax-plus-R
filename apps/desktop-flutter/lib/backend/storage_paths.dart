import 'dart:io';

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
