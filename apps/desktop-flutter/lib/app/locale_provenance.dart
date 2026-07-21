// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Provenance facts for one bundled locale, read from
/// `assets/i18n/provenance.json`. The manifest is the in-repo source of
/// truth for the translation-transparency promise: the language picker
/// renders these facts verbatim ("machine translated by X — N% human
/// reviewed"), so the data is loaded, never hand-written into UI code.
class LocaleProvenance {
  /// 'source' (authored language), 'ai' (machine translated), or
  /// 'human' (community translation).
  final String source;

  /// Exact model id that produced the translation, when [source] is 'ai'.
  final String? model;

  /// ISO date the machine translation was generated, when known.
  final String? generated;

  /// Display names of humans who reviewed this locale.
  final List<String> reviewers;

  /// Share of keys a named reviewer has vetted, 0–100.
  final int humanReviewedPercent;

  const LocaleProvenance({
    required this.source,
    this.model,
    this.generated,
    this.reviewers = const [],
    this.humanReviewedPercent = 0,
  });

  static LocaleProvenance? _fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final source = json['source'];
    if (source is! String) return null;
    return LocaleProvenance(
      source: source,
      model: json['model'] is String ? json['model'] as String : null,
      generated:
          json['generated'] is String ? json['generated'] as String : null,
      reviewers: [
        if (json['reviewers'] is List)
          for (final r in json['reviewers'] as List)
            if (r is Map<String, dynamic> && r['name'] is String)
              r['name'] as String
            else if (r is String)
              r,
      ],
      humanReviewedPercent: json['humanReviewedPercent'] is num
          ? (json['humanReviewedPercent'] as num).round().clamp(0, 100)
          : 0,
    );
  }
}

/// Loads and memoizes the provenance manifest. Missing or malformed
/// manifest degrades to an empty map — the picker simply shows no
/// disclosure line rather than failing.
class LocaleProvenanceStore {
  LocaleProvenanceStore._();

  static Future<Map<String, LocaleProvenance>>? _loading;

  static Future<Map<String, LocaleProvenance>> load() {
    return _loading ??= _loadOnce();
  }

  static Future<Map<String, LocaleProvenance>> _loadOnce() async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/provenance.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final locales = decoded['locales'];
      if (locales is! Map<String, dynamic>) return const {};
      return {
        for (final entry in locales.entries)
          if (LocaleProvenance._fromJson(entry.value) != null)
            entry.key: LocaleProvenance._fromJson(entry.value)!,
      };
    } catch (_) {
      return const {};
    }
  }
}
