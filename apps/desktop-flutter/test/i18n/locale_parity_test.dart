// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural + placeholder parity law across every bundled locale.
///
/// `slang analyze` guarantees key PRESENCE (no missing/unused keys) and codegen
/// guarantees plural-vs-string shape, but neither validates the placeholder
/// CONTENT inside a value. A locale that typo'd `{name}` into `{nom}` still has
/// the key, still compiles — and silently renders the literal `{nom}` to the
/// user, because slang substitutes by the base locale's parameter name. Across
/// 14 locales this is exactly the "output correctness" gap a broad translation
/// sweep can't cover by eye. This is a LAW: for every leaf the English base
/// defines, every locale must carry the same set of `{placeholders}` and the
/// same value SHAPE (string / plural-map / list-of-known-length). No golden
/// wording is asserted, so translation edits never trip it — only structural
/// or placeholder drift does.
void main() {
  final i18nDir = Directory('lib/i18n');
  // `{param}` interpolation, excluding the escaped `\{path}` literal (a slang
  // argument-syntax hint, not a placeholder).
  final placeholderRe = RegExp(r'(?<!\\)\{(\w+)\}');
  const pluralCategories = {'zero', 'one', 'two', 'few', 'many', 'other'};

  Map<String, dynamic> loadLocale(String loc) {
    final result = <String, dynamic>{};
    for (final f in Directory('lib/i18n/$loc').listSync().whereType<File>()) {
      if (!f.path.endsWith('.i18n.json')) continue;
      final ns = f.uri.pathSegments.last.replaceAll('.i18n.json', '');
      result[ns] = jsonDecode(f.readAsStringSync());
    }
    return result;
  }

  Set<String> placeholders(String s) =>
      placeholderRe.allMatches(s).map((m) => m.group(1)!).toSet();

  bool isPluralMap(Object? node) =>
      node is Map &&
      node.isNotEmpty &&
      node.keys.every((k) => pluralCategories.contains(k)) &&
      node.containsKey('other');

  final en = loadLocale('en');

  void walk(Object? base, Object? loc, String path, List<String> problems) {
    // @@locale is intentionally per-locale.
    if (path.endsWith('.@@locale')) return;

    if (isPluralMap(base)) {
      if (base is! Map || loc is! Map || !isPluralMap(loc)) {
        problems.add(
          '$path: base is a plural map, locale is ${loc.runtimeType}',
        );
        return;
      }
      // A plural category may use any SUBSET of the base's parameters — the
      // "one" form legitimately hardcodes the singular and omits {n} (English's
      // own base does: "1 core" / "{n} core"). What's never valid is INVENTING
      // a placeholder the base doesn't provide (the `{nom}`-for-`{name}` typo),
      // which would render literally. So flag only invented placeholders.
      final avail = <String>{};
      for (final v in base.values) {
        avail.addAll(placeholders(v.toString()));
      }
      for (final entry in loc.entries) {
        final invented = placeholders(entry.value.toString()).difference(avail);
        if (invented.isNotEmpty) {
          problems.add(
            '$path.${entry.key}: invented placeholder(s) '
            '$invented not in base $avail',
          );
        }
      }
      return;
    }

    if (base is Map) {
      if (loc is! Map) {
        problems.add('$path: base is an object, locale is ${loc.runtimeType}');
        return;
      }
      for (final key in base.keys) {
        if (key == '@@locale') continue;
        if (!loc.containsKey(key)) {
          problems.add('$path.$key: missing in locale');
          continue;
        }
        walk(base[key], loc[key], '$path.$key', problems);
      }
      return;
    }

    if (base is List) {
      if (loc is! List) {
        problems.add('$path: base is a list, locale is ${loc.runtimeType}');
        return;
      }
      if (loc.length != base.length) {
        problems.add('$path: list length ${loc.length} != base ${base.length}');
        return;
      }
      for (var i = 0; i < base.length; i++) {
        walk(base[i], loc[i], '$path[$i]', problems);
      }
      return;
    }

    // Leaf string: placeholder sets must match exactly.
    final want = placeholders(base.toString());
    final got = placeholders(loc.toString());
    if (got.difference(want).isNotEmpty || want.difference(got).isNotEmpty) {
      problems.add('$path: placeholders $got != base $want');
    }
  }

  final localeNames =
      i18nDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .where((n) => n != 'en' && n != 'gen')
          .toList()
        ..sort();

  test('every locale carries the same namespaces as en', () {
    for (final loc in localeNames) {
      final have = loadLocale(loc).keys.toSet();
      final missing = en.keys.toSet().difference(have);
      expect(
        missing,
        isEmpty,
        reason: '$loc is missing namespace files: $missing',
      );
    }
  });

  for (final loc in localeNames) {
    test('$loc — structure + placeholders match en', () {
      final locale = loadLocale(loc);
      final problems = <String>[];
      for (final ns in en.keys) {
        if (!locale.containsKey(ns)) continue; // reported by the namespace test
        walk(en[ns], locale[ns], ns, problems);
      }
      expect(
        problems,
        isEmpty,
        reason:
            '$loc has ${problems.length} parity problem(s):\n'
            '${problems.take(40).join('\n')}',
      );
    });
  }
}
