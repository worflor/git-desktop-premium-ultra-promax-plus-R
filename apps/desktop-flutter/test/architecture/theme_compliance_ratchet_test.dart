// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Architectural tripwire, not a behavior test — same unusual shape as
/// `test/backend/manifold_refs_transport_guard_test.dart`, and for the same
/// reason: there is no compiler or lint rule that can tell "this widget
/// hand-rolled `BorderRadius.circular(8)` instead of reaching for
/// `AppRadii.base`" from "this widget correctly reached for the token" —
/// the two produce identical `BorderRadius` values and identical runtime
/// behavior. Only a source scan can see the difference, and the difference
/// matters: `lib/ui/design_primitives.dart` (`AppRadii`/`AppElev`),
/// `lib/ui/tokens.dart` (`SurfaceMaterialGeometry`), `lib/ui/theme.dart`
/// (`chromeBorder*` tiers) and `lib/ui/motion.dart`
/// (`context.motion(...)`) exist specifically so that re-theming the app —
/// sharp corners for one theme, rounded for another, a faster or slower
/// global motion curve — is a change in ONE file instead of a grep-and-pray
/// across a couple hundred widgets. Every raw `BorderRadius.circular(...)`,
/// `BoxShadow(...)`, `Color(0x...)`, `Border.all(...)`, or bare
/// `Duration(milliseconds: ...)` passed to an animation is a widget that
/// silently opts itself out of that lever.
///
/// This is a RATCHET, not a gate (see `lib/backend/review_ratchet.dart` for
/// the same philosophy applied to review-finding suppression): it measures
/// the number of violating FILES today, pins that as a ceiling, and only
/// fails if the debt grows. It does not block anyone from shipping a
/// feature that happens to touch a non-compliant file, and it does not
/// demand the ~100-site backlog get fixed before a baseline can be pinned
/// (see `project_theme_compliance` — a 2026-07 audit already covers
/// materials/corners/motion/color/shadow with a documented DEFERRED
/// border-tier backlog; this test is the mechanism that stops that backlog
/// from quietly growing while nobody is looking). If you touch a file on
/// an offenders list below and it's easy to migrate it to the token API,
/// do it and lower the baseline — that's the ratchet tightening. If a
/// baseline needs to go UP because a legitimate new raw usage was added
/// (extremely rare — it should almost always be a token call instead),
/// treat that with the same suspicion the manifold_refs guard asks for a
/// new direct `Process.run`: justify it in a comment at the call site
/// first.
void main() {
  final libDir =
      Directory(p.join(Directory.current.path, 'lib'));

  // Files that legitimately contain raw BorderRadius/BoxShadow/Color/Border
  // values because they DEFINE the design system — everyone else is
  // expected to consume their constants/widgets instead of re-deriving raw
  // values. Scanning these files for "violations" would just be counting
  // the token definitions themselves.
  const allowlist = {
    'lib/ui/design_primitives.dart',
    'lib/ui/tokens.dart',
    'lib/ui/theme.dart',
    'lib/ui/motion.dart',
    'lib/ui/material_surface.dart',
    'lib/ui/liquid_glass.dart',
    'lib/ui/theme_shaders.dart',
  };

  List<File> dartFiles() => libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  /// Posix-style path relative to the flutter package root, for stable
  /// comparison against [allowlist] and for readable failure messages
  /// regardless of host OS path separators.
  String relPath(File f) =>
      p.posix.joinAll(p.split(p.relative(f.path, from: Directory.current.path)));

  bool isAllowlisted(File f) => allowlist.contains(relPath(f));

  /// Animation-context keywords. `Duration(milliseconds: ...)` is
  /// legitimate almost everywhere (network timeouts, debounce windows,
  /// cache TTLs, retry backoff) — it only violates the "motion durations
  /// go through `context.motion(...)`" house rule when it's actually
  /// feeding an animation. We can't prove that with a regex, so we use a
  /// precise-as-practical heuristic: the file must ALSO reference one of
  /// the concrete Flutter animation APIs (`AnimationController`,
  /// `AnimatedContainer`, `TweenAnimationBuilder`, `.animate(`, `curve:`).
  /// This intentionally undercounts (a file could pass a raw Duration into
  /// a bespoke animation helper that doesn't use any of those five
  /// spellings) but it does not overcount a `git.dart`-style file whose
  /// only `Duration(milliseconds: ...)` is a subprocess timeout.
  final animationRefPattern = RegExp(
    r'AnimationController|AnimatedContainer|TweenAnimationBuilder|\.animate\(|curve:',
  );

  /// True when [source] contains a RAW use of [pattern] — one whose
  /// argument does not reach for the token API.
  ///
  /// Line-level, because that is the granularity the distinction lives
  /// at: `BorderRadius.circular(4)` is the smell this rule is named for,
  /// while `BorderRadius.circular(geo.badgeRadius)` IS the token API and
  /// the only way to spell it (a BorderRadius has to be built from the
  /// double the theme hands you). Counting both identically would push
  /// correct, per-theme-geometry code to hard-code a constant to get
  /// quiet — the opposite of what this file is for.
  bool hasRawUse(
    String source,
    RegExp pattern, {
    RegExp? sanctioned,
  }) {
    for (final line in source.split('\n')) {
      if (!pattern.hasMatch(line)) continue;
      if (sanctioned != null && sanctioned.hasMatch(line)) continue;
      return true;
    }
    return false;
  }

  int countViolatingFiles(
    RegExp pattern, {
    bool requireAnimationRef = false,
    RegExp? sanctioned,
  }) {
    var count = 0;
    for (final f in dartFiles()) {
      if (isAllowlisted(f)) continue;
      final source = f.readAsStringSync();
      if (!hasRawUse(source, pattern, sanctioned: sanctioned)) continue;
      if (requireAnimationRef && !animationRefPattern.hasMatch(source)) {
        continue;
      }
      count++;
    }
    return count;
  }

  List<String> offendersFor(
    RegExp pattern, {
    bool requireAnimationRef = false,
    RegExp? sanctioned,
  }) {
    final offenders = <String>[];
    for (final f in dartFiles()) {
      if (isAllowlisted(f)) continue;
      final source = f.readAsStringSync();
      if (!hasRawUse(source, pattern, sanctioned: sanctioned)) continue;
      if (requireAnimationRef && !animationRefPattern.hasMatch(source)) {
        continue;
      }
      offenders.add(relPath(f));
    }
    offenders.sort();
    return offenders;
  }

  void ratchetTest({
    required String label,
    required RegExp pattern,
    required int baseline,
    bool requireAnimationRef = false,
    RegExp? sanctioned,
  }) {
    test('$label: violating-file count must not exceed the pinned baseline',
        () {
      final count = countViolatingFiles(pattern,
          requireAnimationRef: requireAnimationRef, sanctioned: sanctioned);
      if (count < baseline) {
        // The ratchet just tightened — someone migrated a file to the
        // token API without lowering the pin. Nudge them (not fail them)
        // so the constant below tracks reality instead of quietly
        // drifting stale.
        // ignore: avoid_print
        print('$label: violating-file count dropped to $count (baseline '
            '$baseline) — lower the baseline constant in '
            'theme_compliance_ratchet_test.dart to lock in the improvement.');
      }
      final offenders = offendersFor(pattern,
          requireAnimationRef: requireAnimationRef, sanctioned: sanctioned);
      expect(count, lessThanOrEqualTo(baseline),
          reason: '$label: found $count violating files, ceiling is '
              '$baseline. New violations in: ${offenders.take(5).toList()}');
    });
  }

  // Baselines measured 2026-07-09 by running this test's counting logic
  // against the tree at that commit. Every number below is a real
  // measurement, not a guess — see the task report for the full
  // per-rule offender lists.

  ratchetTest(
    label: 'rawCorners (BorderRadius.circular(...) / BorderRadius.all(...) '
        'instead of AppRadii / geometry.*Radius)',
    pattern: RegExp(r'BorderRadius\.circular\(|BorderRadius\.all\('),
    // Reaching for the theme's geometry or the radius scale IS the token
    // API; only a bare literal opts a widget out of the re-theming lever.
    sanctioned: RegExp(r'AppRadii\.|geo(metry)?\.\w*[Rr]adius|resolvedRadius'),
    // 36, re-measured 2026-07-25 when the rule started reading the
    // ARGUMENT: two of the files it had been counting were reaching for
    // the theme geometry all along. Tightened, not relaxed — the pin is
    // below the old 38, so the debt it guards can only shrink from here.
    baseline: 36,
  );

  ratchetTest(
    label: 'rawShadows (BoxShadow(...) instead of AppElev)',
    pattern: RegExp(r'BoxShadow\('),
    baseline: 13, // measured 2026-07-09
  );

  ratchetTest(
    label: 'rawMotion (Duration(milliseconds: ...) feeding an animation '
        'instead of context.motion(...))',
    pattern: RegExp(r'Duration\(milliseconds:'),
    requireAnimationRef: true,
    baseline: 23, // measured 2026-07-09
  );

  ratchetTest(
    label: 'rawHexColors (Color(0x...) instead of AppTokens)',
    pattern: RegExp(r'Color\(0x'),
    baseline: 10, // measured 2026-07-09
  );

  ratchetTest(
    label: 'rawBorderAll (Border.all(...) instead of chromeBorder* tiers)',
    pattern: RegExp(r'Border\.all\('),
    // A Border.all carrying a chromeBorder tier is the tier API being
    // used; the rule is about borders that invent their own colour.
    sanctioned: RegExp(r'chromeBorder'),
    // 36, re-measured 2026-07-25 with the same argument-aware rule.
    baseline: 36,
  );
}
