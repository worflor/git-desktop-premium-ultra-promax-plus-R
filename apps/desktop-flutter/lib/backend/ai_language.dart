// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

/// The human language conversational AI features should reply in.
///
/// Set by the UI layer whenever the locale resolves or changes (see
/// `main.dart`). Lives in the pure-Dart backend — no Flutter/i18n import — so
/// `ai.dart` can read it without depending on the widget layer.
///
/// Scope is deliberate: only CONVERSATIONAL, screen-bound AI output honors
/// this — code review, muse, debug analysis, i.e. the app speaking *to* the
/// user. Commit-message generation does NOT: commit text is an artifact
/// written into git history, so it follows the repository's own convention
/// (which the model infers from the recent-commit log already in that prompt),
/// not the reader's UI language. A French UI must still produce English
/// commits on an English project.
class AiLanguage {
  AiLanguage._();

  /// English name of the user's selected UI language (e.g. `'French'`,
  /// `'Simplified Chinese'`), or `null` when the UI is English (the model's
  /// default — no instruction needed) or the locale is unknown.
  static String? preferredName;

  /// Maps a resolved locale's parts to the English language name used in
  /// prompts. English → `null` (so switching back to English clears any prior
  /// instruction). Unknown tags → `null`.
  static String? nameForLocale(
    String languageCode, [
    String? scriptCode,
    String? countryCode,
  ]) {
    switch (languageCode) {
      case 'de':
        return 'German';
      case 'es':
        return 'Spanish';
      case 'fr':
        return 'French';
      case 'id':
        return 'Indonesian';
      case 'it':
        return 'Italian';
      case 'ja':
        return 'Japanese';
      case 'ko':
        return 'Korean';
      case 'nl':
        return 'Dutch';
      case 'pl':
        return 'Polish';
      case 'pt':
        return countryCode == 'BR' ? 'Brazilian Portuguese' : 'Portuguese';
      case 'ru':
        return 'Russian';
      case 'tr':
        return 'Turkish';
      case 'zh':
        return scriptCode == 'Hant'
            ? 'Traditional Chinese'
            : 'Simplified Chinese';
      case 'en':
      default:
        return null;
    }
  }
}
