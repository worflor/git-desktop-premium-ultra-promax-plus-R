import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// Shared motion vocabulary. Every animation in the app should source its
/// duration + curve from here instead of hardcoding a Duration inline. One
/// place to tune the feel across 9 themes and 100+ call-sites.
///
/// Three tiers, roughly matching the `SurfaceMotion` shader enum that the
/// theme engine already emits:
///   * snap  — instant feedback (hover flips, toggle state, press-in)
///   * fade  — UI transitions (row backgrounds, stripe appearances,
///             container decorations settling)
///   * fluid — choreographed moments (page loads, panel opens, the
///             logo animation's visible phases)
///
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
///
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

/// Border radii. Four tiers covering the app's needs — anything outside
/// these is probably wrong. Use `.circular` BorderRadius via these if you
/// want a rounded-rect shape; use the raw double if a half-radius matters
/// (e.g. for accent stripes).
class AppRadii {
  AppRadii._();

  /// 4px — tight. Inline chips, small badges, hash pills.
  static const double xs = 4;

  /// 6px — small. Dense chrome buttons, compact controls.
  static const double sm = 6;

  /// 8px — default. Rows, cards, most surfaces.
  static const double base = 8;

  /// 12px — panel. Big surfaces, major containers.
  static const double lg = 12;

  /// Pre-computed BorderRadius for convenience.
  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius baseAll = BorderRadius.all(Radius.circular(base));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}
