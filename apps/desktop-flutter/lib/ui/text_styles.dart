import 'package:flutter/painting.dart';

import 'design_primitives.dart';
import 'tokens.dart';

/// Shared text styles. Centralized so the dozens of inline `TextStyle(...)`
/// definitions for caps labels, mono badges, and section titles stop
/// drifting apart. Each helper takes the active [AppTokens] so colors
/// stay theme-aware without coupling the call site to context.
///
/// Usage:
///   `Text('SPARK', style: AppTextStyles.capsLabel(t))`
///   `Text('a3f9c2', style: AppTextStyles.monoBadge(t))`
///
/// Override per-call via `.copyWith` only when the style genuinely needs
/// a tweak — that's the signal to consider whether a new tier belongs
/// here.
class AppTextStyles {
  AppTextStyles._();

  /// Caps section labels — "SPARK", "FINDINGS", "OPTIONS". Uppercase
  /// glyphs intended; widget passes already-uppercased text. Replaces
  /// the ~40 inline `(fontSize 9-11, letterSpacing 1.2-1.6, w600)`
  /// triples scattered across the feature panels.
  static TextStyle capsLabel(AppTokens t, {Color? color}) => TextStyle(
        color: color ?? t.textMuted,
        fontSize: 10,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
      );

  /// Looser caps label variant — wider letterspacing, slightly smaller.
  /// Use for the rarer "BRAINSTORM SPEW" / decorative labels where the
  /// header should breathe more than the standard caps tier.
  static TextStyle capsLabelLoose(AppTokens t, {Color? color}) => TextStyle(
        color: color ?? t.textFaint,
        fontSize: 9,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w500,
      );

  /// Monospace badge — commit hashes, file counts, line numbers, any
  /// fixed-width inline label. Pairs `AppFonts.mono` with the fallback
  /// chain so the metrics survive a missing font.
  static TextStyle monoBadge(AppTokens t, {Color? color}) => TextStyle(
        color: color ?? t.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
      );

  /// Monospace inline — for citations, paths, code-like labels in body
  /// text. Slightly larger and lighter than the badge tier.
  static TextStyle monoInline(AppTokens t, {Color? color}) => TextStyle(
        color: color ?? t.textFaint,
        fontSize: 10.5,
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
      );

  /// Section title — medium-weight panel titles. Replaces the scattered
  /// `(fontSize 12, w600)` triples used as panel headers.
  static TextStyle sectionTitle(AppTokens t, {Color? color}) => TextStyle(
        color: color ?? t.textStrong,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
}
