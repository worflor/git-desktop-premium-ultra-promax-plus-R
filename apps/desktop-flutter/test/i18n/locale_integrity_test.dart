// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/i18n/gen/strings.g.dart';

/// Locale-integrity laws for the bundled translations.
///
/// Every AppLocale must (1) build its translation tree, (2) resolve
/// cardinal plurals without throwing — slang raises at runtime when a
/// locale lacks a plural resolver, which is exactly the failure mode
/// that must never reach a user — and (3) keep placeholder substitution
/// working. These are laws, not goldens: no assertion pins translated
/// wording, only structure and non-explosion, so translation PRs never
/// break this suite.
void main() {
  group('every bundled locale', () {
    for (final locale in AppLocale.values) {
      test('$locale builds and resolves plurals + placeholders', () {
        final t = locale.buildSync();

        // Cardinal plurals across the interesting counts: 1 (one), the
        // 2-4 band and teens (Slavic few/many splits), and a large n.
        for (final n in [0, 1, 2, 5, 11, 21, 100]) {
          final rendered = t.common.fileCount(n: n);
          expect(rendered, isNotEmpty);
          expect(rendered, contains('$n'),
              reason: '$locale fileCount($n) must interpolate the count');
        }

        // Placeholder substitution in a parameterized sentence.
        final disclosure =
            t.settings.language.disclosureAi(model: 'TestModel');
        expect(disclosure, contains('TestModel'),
            reason: '$locale must substitute {model}');

        // List keys survive translation with their length intact.
        expect(t.common.time.monthAbbrevs, hasLength(12),
            reason: '$locale monthAbbrevs must keep 12 entries');
      });
    }
  });

  test('locale tags round-trip through AppLocaleUtils.parse', () {
    for (final locale in AppLocale.values) {
      expect(AppLocaleUtils.parse(locale.languageTag), locale,
          reason: '${locale.languageTag} must parse back to itself');
    }
  });
}
