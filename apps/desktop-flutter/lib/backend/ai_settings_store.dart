import 'dart:convert';
import 'dart:io';

import 'storage_paths.dart';

class AiSettingsSnapshot {
  final Map<String, String> modelSelections;
  final Map<String, String> modelCategoryLabels;
  final String commitMessageModelCategoryId;
  final String reviewCommitModelCategoryId;
  final bool reviewCommitDoubleCheckEnabled;
  final String museBrainstormModelCategoryId;
  final String museSynthesisModelCategoryId;

  const AiSettingsSnapshot({
    required this.modelSelections,
    required this.modelCategoryLabels,
    required this.commitMessageModelCategoryId,
    required this.reviewCommitModelCategoryId,
    required this.reviewCommitDoubleCheckEnabled,
    required this.museBrainstormModelCategoryId,
    required this.museSynthesisModelCategoryId,
  });

  factory AiSettingsSnapshot.defaults() => const AiSettingsSnapshot(
        modelSelections: {},
        modelCategoryLabels: {
          'quality': 'Quality model',
          'fast': 'Fast model',
        },
        commitMessageModelCategoryId: 'quality',
        reviewCommitModelCategoryId: 'quality',
        reviewCommitDoubleCheckEnabled: false,
        museBrainstormModelCategoryId: 'fast',
        museSynthesisModelCategoryId: 'quality',
      );

  Map<String, dynamic> toJson() => {
        'modelSelections': modelSelections,
        'modelCategoryLabels': modelCategoryLabels,
        'commitMessageModelCategoryId': commitMessageModelCategoryId,
        'reviewCommitModelCategoryId': reviewCommitModelCategoryId,
        'reviewCommitDoubleCheckEnabled': reviewCommitDoubleCheckEnabled,
        'museBrainstormModelCategoryId': museBrainstormModelCategoryId,
        'museSynthesisModelCategoryId': museSynthesisModelCategoryId,
      };

  factory AiSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final defaults = AiSettingsSnapshot.defaults();
    return AiSettingsSnapshot(
      modelSelections: _readStringMap(json['modelSelections']),
      modelCategoryLabels: {
        ...defaults.modelCategoryLabels,
        ..._readStringMap(json['modelCategoryLabels']),
      },
      commitMessageModelCategoryId: _stringOr(
        json['commitMessageModelCategoryId'],
        defaults.commitMessageModelCategoryId,
      ),
      reviewCommitModelCategoryId: _stringOr(
        json['reviewCommitModelCategoryId'],
        defaults.reviewCommitModelCategoryId,
      ),
      reviewCommitDoubleCheckEnabled: _boolOr(
        json['reviewCommitDoubleCheckEnabled'],
        defaults.reviewCommitDoubleCheckEnabled,
      ),
      museBrainstormModelCategoryId: _stringOr(
        json['museBrainstormModelCategoryId'],
        defaults.museBrainstormModelCategoryId,
      ),
      museSynthesisModelCategoryId: _stringOr(
        json['museSynthesisModelCategoryId'],
        defaults.museSynthesisModelCategoryId,
      ),
    );
  }

  static Map<String, String> _readStringMap(dynamic raw) {
    if (raw is! Map) {
      return {};
    }

    final values = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! String) {
        continue;
      }
      final normalizedKey = key.trim();
      final normalizedValue = value.trim();
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) {
        continue;
      }
      values[normalizedKey] = normalizedValue;
    }
    return values;
  }

  static String _stringOr(dynamic value, String fallback) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  static bool _boolOr(dynamic value, bool fallback) {
    return value is bool ? value : fallback;
  }
}

class AiSettingsStore {
  static const String _settingsFileName = 'ai_settings.json';
  static const String _promptDirectoryName = 'prompts';
  static const String _commitPromptFileName = 'commit-message.md';
  static const String _reviewPromptFileName = 'review-commit.md';
  static const String _musePromptFileName = 'muse.md';

  static Future<AiSettingsSnapshot> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      final defaults = AiSettingsSnapshot.defaults();
      await persist(defaults);
      return defaults;
    }

    try {
      final raw = await file.readAsString();
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        final snapshot = AiSettingsSnapshot.fromJson(parsed);
        await persist(snapshot);
        return snapshot;
      }
    } catch (_) {}

    final defaults = AiSettingsSnapshot.defaults();
    await persist(defaults);
    return defaults;
  }

  static Future<void> persist(AiSettingsSnapshot snapshot) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
      flush: true,
    );
  }

  static Future<String> loadCommitMessagePrompt() async {
    final file = await commitMessagePromptFile();
    if (!await file.exists()) {
      return '';
    }

    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> persistCommitMessagePrompt(String value) async {
    final file = await commitMessagePromptFile();
    final normalized = value.trimRight();
    if (normalized.trim().isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString('$normalized\n', flush: true);
  }

  static Future<String> commitMessagePromptPath() async {
    final file = await commitMessagePromptFile();
    return file.path;
  }

  static Future<File> commitMessagePromptFile() async {
    final root = await _aiRootDir();
    return File(
      '${root.path}${Platform.pathSeparator}$_promptDirectoryName${Platform.pathSeparator}$_commitPromptFileName',
    );
  }

  static Future<String> loadReviewCommitPrompt() async {
    final file = await reviewCommitPromptFile();
    if (!await file.exists()) {
      return '';
    }

    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> persistReviewCommitPrompt(String value) async {
    final file = await reviewCommitPromptFile();
    final normalized = value.trimRight();
    if (normalized.trim().isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString('$normalized\n', flush: true);
  }

  static Future<String> reviewCommitPromptPath() async {
    final file = await reviewCommitPromptFile();
    return file.path;
  }

  static Future<File> reviewCommitPromptFile() async {
    final root = await _aiRootDir();
    return File(
      '${root.path}${Platform.pathSeparator}$_promptDirectoryName${Platform.pathSeparator}$_reviewPromptFileName',
    );
  }

  static Future<String> loadMusePrompt() async {
    final file = await musePromptFile();
    if (!await file.exists()) return '';
    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> persistMusePrompt(String value) async {
    final file = await musePromptFile();
    final normalized = value.trimRight();
    if (normalized.trim().isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('$normalized\n', flush: true);
  }

  static Future<String> musePromptPath() async {
    final file = await musePromptFile();
    return file.path;
  }

  static Future<File> musePromptFile() async {
    final root = await _aiRootDir();
    return File(
      '${root.path}${Platform.pathSeparator}$_promptDirectoryName${Platform.pathSeparator}$_musePromptFileName',
    );
  }

  static Future<File> _settingsFile() async {
    final root = await _aiRootDir();
    return File('${root.path}${Platform.pathSeparator}$_settingsFileName');
  }

  static Future<Directory> _aiRootDir() async {
    final dataDir = await StoragePaths.gdpuDataDir();
    return Directory('${dataDir.path}${Platform.pathSeparator}ai');
  }
}
