import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Font-family vocabulary. Centralizing the mono family + fallback chain
/// stops every TextStyle from string-literal'ing `'JetBrainsMono'` and
/// guarantees a coherent fallback if the font fails to load — instead of
/// silently falling through to whatever the platform's default sans-serif
/// happens to be (a real risk on Windows where `'monospace'` resolves to
/// Courier New, with completely different metrics from JetBrainsMono).
class AppFonts {
  AppFonts._();

  /// Primary monospace family. Use for code, hashes, line numbers,
  /// file paths, anywhere fixed-width metrics matter.
  ///
  /// Always pair with [monoFallback] via `fontFamilyFallback` so
  /// glyphs missing from JetBrainsMono (emoji, CJK, symbols) fall
  /// through to platform fonts. Callers that use [mono] without
  /// the fallback will render tofu for those glyphs.
  static const String mono = 'JetBrainsMono';

  /// Fallback chain for monospace. Cross-platform — Consolas (Windows),
  /// Menlo (macOS), Courier New (universal), emoji fonts, then generic.
  static const List<String> monoFallback = [
    'Consolas',
    'Menlo',
    'Courier New',
    'Segoe UI Emoji',
    'Apple Color Emoji',
    'Noto Color Emoji',
    'monospace',
  ];
}

/// Shared spacing scale. Use these constants for SizedBox / EdgeInsets
/// gaps so the rhythm stays coherent. Anything off-scale (5, 7, 9, 11,
/// 13) is probably a per-eye tuning that should be a token instead. The
/// scale is 4-based; intermediate sizes (6, 10, 14) are deliberate
/// in-betweens for rows that need a touch more or less air.
class AppSpacing {
  AppSpacing._();

  /// 4px — tight. Tag glyph gap, inline accent stripe.
  static const double xs = 4;
  /// 6px — between xs and sm. Compact chip gap.
  static const double sm6 = 6;
  /// 8px — small. Standard inline gap, dense row spacing.
  static const double sm = 8;
  /// 10px — between sm and md. Mid-density row gap.
  static const double sm10 = 10;
  /// 12px — medium. Default block gap, card padding inset.
  static const double md = 12;
  /// 14px — between md and lg. Generous row air.
  static const double md14 = 14;
  /// 16px — large. Section gap, panel inset.
  static const double lg = 16;
  /// 20px — between lg and xl. Header pad.
  static const double lg20 = 20;
  /// 24px — extra large. Big section break.
  static const double xl = 24;
}

/// Shared motion vocabulary. Every animation in the app should source its
/// duration + curve from here instead of hardcoding a Duration inline. One
/// place to tune the feel across 9 themes and 100+ call-sites.
/// Three tiers, roughly matching the `SurfaceMotion` shader enum that the
/// theme engine already emits:
///   * snap  — instant feedback (hover flips, toggle state, press-in)
///   * fade  — UI transitions (row backgrounds, stripe appearances,
///             container decorations settling)
///   * fluid — choreographed moments (page loads, panel opens, the
///             logo animation's visible phases)
/// Durations are intentionally short. Flutter framework animations default
/// to 300ms; this app's house voice is crisper.
class AppMotion {
  AppMotion._();

  /// 80ms — snap. Press-in, hover, toggle. "Did something happen? Yes."
  static const Duration snap = Duration(milliseconds: 80);

  /// 180ms — fade. Row stripe color resolves, card background resolves,
  /// stripe slot width animates. Readable but not languid.
  static const Duration fade = Duration(milliseconds: 180);

  /// 300ms — fluid. Panel shows, treemap reflows, page-scoped staggers.
  /// Approaching the edge of "slow"; use sparingly.
  static const Duration fluid = Duration(milliseconds: 300);

  /// Curves paired with each tier. `Curves.easeOutCubic` is the house
  /// default — quick start, soft landing. Swap per-tier if a specific
  /// moment calls for something different (e.g. `easeOutBack` for a
  /// pop), but prefer the default.
  static const Curve snapCurve = Curves.easeOutCubic;
  static const Curve fadeCurve = Curves.easeOutCubic;
  static const Curve fluidCurve = Curves.easeInOutCubic;
}

/// Elevation recipes — pre-composed `BoxShadow` lists. Use these in
/// `BoxDecoration.boxShadow` instead of rolling one-off shadows per widget.
/// Keeps the app's depth language consistent and lets us tune elevation
/// app-wide by editing this file.
/// Colors are token-agnostic black with alpha; for themed shadows, layer
/// an additional tinted glow on top.
class AppElev {
  AppElev._();

  /// Resting row / chip. Barely-there 1px lift.
  static const List<BoxShadow> row = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F000000), // ~6% black
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Panel card / surface1 equivalent. Visible but subtle.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000), // ~8% black
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Floating dialog / menu / popup.
  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F000000), // ~12% black
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  /// Modal / command-surface depth.
  static const List<BoxShadow> modal = <BoxShadow>[
    BoxShadow(
      color: Color(0x2B000000), // ~17% black
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

/// Border radii. Six tiers covering the app's needs — anything outside
/// these is probably wrong. Use `.circular` BorderRadius via these if you
/// want a rounded-rect shape; use the raw double if a half-radius matters
/// (e.g. for accent stripes).
///
/// Note: these are STATIC tiers. If you need radii that respect the
/// per-theme `geometry.radius` (so Crafty/Kirby/Phosphor can go sharp),
/// use `context.surfaceShader.geometry.cardRadius/pillRadius/badgeRadius`
/// from material_surface.dart instead.
class AppRadii {
  AppRadii._();

  /// 2px — micro. Sparkline clips, micro indicators, inner ticks.
  static const double xxs = 2;

  /// 4px — tight. Inline chips, small badges, hash pills.
  static const double xs = 4;

  /// 6px — small. Dense chrome buttons, compact controls.
  static const double sm = 6;

  /// 8px — default. Rows, cards, most surfaces.
  static const double base = 8;

  /// 12px — panel. Big surfaces, major containers.
  static const double lg = 12;

  /// 999 — full pill / stadium shape. Tag chips, dismiss circles,
  /// affordances meant to read as fully-rounded.
  static const double pill = 999;

  /// Pre-computed BorderRadius for convenience.
  static const BorderRadius xxsAll = BorderRadius.all(Radius.circular(xxs));
  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius baseAll = BorderRadius.all(Radius.circular(base));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Border widths. Three tiers covering chrome strokes. Use these for
/// `BorderSide.width` so the app's stroke language stays coherent. The
/// raw value `1` is so common it's self-documenting; reach for these
/// when intent matters (hairline divider vs structural border).
class AppBorderWidth {
  AppBorderWidth._();

  /// 0.5px — hairline. Subtle dividers, sparkline rules, inner edges.
  static const double hairline = 0.5;
  /// 1px — thin. Default chrome border.
  static const double thin = 1;
  /// 1.5px — medium. Emphasis border on selected rows / hover.
  static const double medium = 1.5;
  /// 2px — thick. Structural borders, accent rails.
  static const double thick = 2;
}

/// Icon sizes. Five tiers spanning inline glyphs to panel-header icons.
/// Use these for `Icon(..., size: ...)` so icon weight stays in band
/// with surrounding text and adjacent icons.
class AppIconSize {
  AppIconSize._();

  /// 12px — micro. Inline indicator next to small text.
  static const double xs = 12;
  /// 14px — small. Inline icons in row text.
  static const double sm = 14;
  /// 16px — default. Action buttons, chip leading icons.
  static const double md = 16;
  /// 18px — large. Toolbar icons, panel-header glyphs.
  static const double lg = 18;
  /// 20px — extra large. Big affordances, overflow menus.
  static const double xl = 20;
}
