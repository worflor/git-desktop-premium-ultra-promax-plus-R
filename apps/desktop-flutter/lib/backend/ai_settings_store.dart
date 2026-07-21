// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'atomic_write.dart';
import 'dtos.dart'
    show
        MuseQuiverEntry,
        MuseStrandKind,
        defaultMuseQuiver,
        kMuseStrandDisplayOrder,
        museStrandLabel,
        normalizeMuseStrandOrder,
        parseMuseStrand;
import 'storage_paths.dart';

/// The closed set of CLIs that can carry API-provider prompts (see
/// `apiPiggybackCli`). Store load, the settings setter, and the settings
/// dropdown all key off this one set, so a value that can't be rendered or
/// dispatched can never enter the system.
const Set<String> kSupportedPiggybackClis = {'codex'};

class AiSettingsSnapshot {
  final Map<String, String> modelSelections;
  final Map<String, String> modelCategoryLabels;
  final Map<String, String> reasoningEfforts;
  final String commitMessageModelCategoryId;
  final String reviewCommitModelCategoryId;
  final bool reviewCommitDoubleCheckEnabled;
  /// Universal transport policy for API-provider models across all AI
  /// features (reviews, commit messages, muse, ask, debug, patch).
  /// `''` = direct HTTP; `'codex'` = ride through the codex CLI. More
  /// providers may join this dropdown later; today codex is the only option.
  final String apiPiggybackCli;
  /// Per-attempt wall-clock cap (in seconds) for the long-running AI CLIs
  /// (codex/claude/cursor/opencode/API-provider). Pushed into the backend via
  /// `configureCliTimeout`. The tight antigravity/copilot caps are independent.
  final int cliTimeoutSeconds;
  final String museBrainstormModelCategoryId;
  final String museSynthesisModelCategoryId;
  final String presentModelCategoryId;
  /// The user's active loadout — which strands the muse throws on its
  /// next call, and how many walkers of each. Empty list falls back to
  /// [defaultMuseQuiver] (the original 4-strand spark/current/horizon/
  /// fever set, count 1 each).
  final List<MuseQuiverEntry> museQuiver;
  /// The order strands are rendered in — both the settings strand strip
  /// and the muse output panel iterate this. User-reorderable; orthogonal
  /// to [museQuiver] (which strands are active). Always a complete,
  /// de-duplicated ordering of every [MuseStrandKind]; normalised on
  /// read so a partial or stale persisted value can't drop a strand.
  final List<MuseStrandKind> museStrandOrder;

  const AiSettingsSnapshot({
    required this.modelSelections,
    required this.modelCategoryLabels,
    this.reasoningEfforts = const {},
    required this.commitMessageModelCategoryId,
    required this.reviewCommitModelCategoryId,
    required this.reviewCommitDoubleCheckEnabled,
    this.apiPiggybackCli = 'codex',
    this.cliTimeoutSeconds = 1200,
    required this.museBrainstormModelCategoryId,
    required this.museSynthesisModelCategoryId,
    required this.presentModelCategoryId,
    this.museQuiver = const [],
    this.museStrandOrder = kMuseStrandDisplayOrder,
  });

  factory AiSettingsSnapshot.defaults() => AiSettingsSnapshot(
        modelSelections: const {},
        modelCategoryLabels: const {
          'quality': 'Quality',
          'fast': 'Fast',
        },
        commitMessageModelCategoryId: 'quality',
        reviewCommitModelCategoryId: 'quality',
        reviewCommitDoubleCheckEnabled: false,
        apiPiggybackCli: 'codex',
        cliTimeoutSeconds: 1200,
        museBrainstormModelCategoryId: 'fast',
        museSynthesisModelCategoryId: 'quality',
        presentModelCategoryId: 'quality',
        museQuiver: defaultMuseQuiver(),
        museStrandOrder: kMuseStrandDisplayOrder,
      );

  Map<String, dynamic> toJson() => {
        'modelSelections': modelSelections,
        'modelCategoryLabels': modelCategoryLabels,
        'reasoningEfforts': reasoningEfforts,
        'commitMessageModelCategoryId': commitMessageModelCategoryId,
        'reviewCommitModelCategoryId': reviewCommitModelCategoryId,
        'reviewCommitDoubleCheckEnabled': reviewCommitDoubleCheckEnabled,
        'apiPiggybackCli': apiPiggybackCli,
        'cliTimeoutSeconds': cliTimeoutSeconds,
        'museBrainstormModelCategoryId': museBrainstormModelCategoryId,
        'museSynthesisModelCategoryId': museSynthesisModelCategoryId,
        'presentModelCategoryId': presentModelCategoryId,
        'museQuiver': [for (final e in museQuiver) e.toJson()],
        'museStrandOrder': [for (final k in museStrandOrder) museStrandLabel(k)],
      };

  factory AiSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    final defaults = AiSettingsSnapshot.defaults();
    return AiSettingsSnapshot(
      modelSelections: _readStringMap(json['modelSelections']),
      modelCategoryLabels: {
        ...defaults.modelCategoryLabels,
        ..._readStringMap(json['modelCategoryLabels']),
      },
      reasoningEfforts: _readStringMap(json['reasoningEfforts']),
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
      apiPiggybackCli: _piggybackCliOr(
        json['apiPiggybackCli'],
        defaults.apiPiggybackCli,
      ),
      cliTimeoutSeconds: _intOr(
        json['cliTimeoutSeconds'],
        defaults.cliTimeoutSeconds,
      ).clamp(30, 7200),
      museBrainstormModelCategoryId: _stringOr(
        json['museBrainstormModelCategoryId'],
        defaults.museBrainstormModelCategoryId,
      ),
      museSynthesisModelCategoryId: _stringOr(
        json['museSynthesisModelCategoryId'],
        defaults.museSynthesisModelCategoryId,
      ),
      presentModelCategoryId: _stringOr(
        json['presentModelCategoryId'],
        defaults.presentModelCategoryId,
      ),
      museQuiver: _readQuiver(json['museQuiver'], defaults.museQuiver),
      museStrandOrder: _readStrandOrder(json['museStrandOrder']),
    );
  }

  static List<MuseQuiverEntry> _readQuiver(
    dynamic raw,
    List<MuseQuiverEntry> fallback,
  ) {
    if (raw is! List) return fallback;
    final entries = <MuseQuiverEntry>[
      for (final item in raw)
        if (MuseQuiverEntry.fromJson(item) case final e?) e,
    ];
    return entries.isEmpty ? fallback : entries;
  }

  /// Parse a persisted strand-order list (an array of strand labels)
  /// and normalise it to a complete ordering. Unknown labels are
  /// dropped; missing strands are appended in canonical order. A
  /// missing or malformed value yields the canonical default order.
  static List<MuseStrandKind> _readStrandOrder(dynamic raw) {
    if (raw is! List) return kMuseStrandDisplayOrder;
    final parsed = <MuseStrandKind>[
      for (final item in raw)
        if (item is String)
          if (parseMuseStrand(item) case final k?) k,
    ];
    return normalizeMuseStrandOrder(parsed);
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

  /// Like [_stringOr], but a persisted empty string is a real value
  /// (not "missing") — only an absent/non-string key falls back.
  /// Reader for `apiPiggybackCli`. Unlike the category-id fields, '' is a
  /// meaningful, distinct value (piggyback off) rather than "unset" — and
  /// the value set must stay closed over [kSupportedPiggybackClis]: an
  /// arbitrary persisted string (hand-edited JSON, a newer build's provider
  /// name after a downgrade) would otherwise reach the settings dropdown as
  /// a value matching no item, which asserts and takes the page down. An
  /// unknown carrier degrades to the fallback, preserving "piggyback on".
  static String _piggybackCliOr(dynamic value, String fallback) {
    if (value is! String) return fallback;
    final trimmed = value.trim();
    if (trimmed.isEmpty || kSupportedPiggybackClis.contains(trimmed)) {
      return trimmed;
    }
    return fallback;
  }

  static bool _boolOr(dynamic value, bool fallback) {
    return value is bool ? value : fallback;
  }

  static int _intOr(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  AiSettingsSnapshot copyWith({
    Map<String, String>? modelSelections,
    Map<String, String>? modelCategoryLabels,
    Map<String, String>? reasoningEfforts,
    String? commitMessageModelCategoryId,
    String? reviewCommitModelCategoryId,
    bool? reviewCommitDoubleCheckEnabled,
    String? apiPiggybackCli,
    int? cliTimeoutSeconds,
    String? museBrainstormModelCategoryId,
    String? museSynthesisModelCategoryId,
    String? presentModelCategoryId,
    List<MuseQuiverEntry>? museQuiver,
    List<MuseStrandKind>? museStrandOrder,
  }) {
    return AiSettingsSnapshot(
      modelSelections: modelSelections ?? this.modelSelections,
      modelCategoryLabels: modelCategoryLabels ?? this.modelCategoryLabels,
      reasoningEfforts: reasoningEfforts ?? this.reasoningEfforts,
      commitMessageModelCategoryId:
          commitMessageModelCategoryId ?? this.commitMessageModelCategoryId,
      reviewCommitModelCategoryId:
          reviewCommitModelCategoryId ?? this.reviewCommitModelCategoryId,
      reviewCommitDoubleCheckEnabled:
          reviewCommitDoubleCheckEnabled ?? this.reviewCommitDoubleCheckEnabled,
      apiPiggybackCli: apiPiggybackCli ?? this.apiPiggybackCli,
      cliTimeoutSeconds: cliTimeoutSeconds ?? this.cliTimeoutSeconds,
      museBrainstormModelCategoryId:
          museBrainstormModelCategoryId ?? this.museBrainstormModelCategoryId,
      museSynthesisModelCategoryId:
          museSynthesisModelCategoryId ?? this.museSynthesisModelCategoryId,
      presentModelCategoryId:
          presentModelCategoryId ?? this.presentModelCategoryId,
      museQuiver: museQuiver ?? this.museQuiver,
      museStrandOrder: museStrandOrder ?? this.museStrandOrder,
    );
  }
}

class AiSettingsStore {
  static const String _settingsFileName = 'ai_settings.json';
  static const String _promptDirectoryName = 'prompts';
  static const String _commitPromptFileName = 'commit-message.md';
  static const String _reviewPromptFileName = 'review-commit.md';
  static const String _musePromptFileName = 'muse.md';
  static const String _presentPromptFileName = 'present.md';

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
        return snapshot;
      }
    } catch (_) {
      // Parse failure on an EXISTING file: return defaults in memory but
      // leave the on-disk bytes untouched (mirrors SettingsStore._loadImpl).
      // Re-persisting defaults here would destroy a torn file's forensic
      // evidence and silently overwrite partially-valid real user settings;
      // rewrite only on an explicit user reset via persist().
      return AiSettingsSnapshot.defaults();
    }

    // The file exists but decoded to a non-map (e.g. a bare `[]` or `"x"`).
    // Same policy as the catch above: default in memory, don't clobber.
    return AiSettingsSnapshot.defaults();
  }

  static Future<void> persist(AiSettingsSnapshot snapshot) async {
    final file = await _settingsFile();
    // Atomic temp-then-rename so a crash mid-write can't leave a torn
    // ai_settings.json (see atomic_write.dart).
    await writeFileAtomicString(
      file,
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
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

    await writeFileAtomicString(file, '$normalized\n');
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

    await writeFileAtomicString(file, '$normalized\n');
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
    await writeFileAtomicString(file, '$normalized\n');
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

  static Future<String> loadPresentPrompt() async {
    final file = await presentPromptFile();
    if (!await file.exists()) return '';
    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> persistPresentPrompt(String value) async {
    final file = await presentPromptFile();
    final normalized = value.trimRight();
    if (normalized.trim().isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await writeFileAtomicString(file, '$normalized\n');
  }

  static Future<String> presentPromptPath() async {
    final file = await presentPromptFile();
    return file.path;
  }

  static Future<File> presentPromptFile() async {
    final root = await _aiRootDir();
    return File(
      '${root.path}${Platform.pathSeparator}$_promptDirectoryName${Platform.pathSeparator}$_presentPromptFileName',
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
