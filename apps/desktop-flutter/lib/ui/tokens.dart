import 'package:flutter/material.dart';

// ── Semantic severity palette ──────────────────────────────────────────
// Theme-independent signal colors used for review verdicts, guardrail
// stages, and any UI that communicates a confidence/risk level.
// Order: safe → informational → cautious → risky → critical.
class AppSeverityPalette {
  AppSeverityPalette._();

  static const safe     = Color(0xFF4AD399); // green  — ready / safe
  static const info     = Color(0xFF7AB8FF); // blue   — balanced / informational
  static const caution  = Color(0xFFD39A2C); // amber  — needs attention
  static const risk     = Color(0xFFEF7C75); // coral  — high risk / danger
  static const critical = Color(0xFFB280FF); // purple — block / extreme
  static const neutral  = Color(0xFF8CA0B3); // slate  — unknown / fallback

  /// The 4-stage guardrail scale (maps to guardrail slider positions).
  static const guardrailStages = [safe, info, risk, critical];

  /// Map a review verdict string to its severity color.
  static Color fromVerdict(String verdict) {
    return switch (verdict) {
      'Ready'           => safe,
      'Mostly ready'    => info,
      'Needs attention' => caution,
      'High risk'       => risk,
      'Block'           => critical,
      _                 => neutral,
    };
  }
}

enum AppThemeId {
  halo,
  nightwalker,
  petrichor,
  helix,
  nacre,
  loverboy,
  aether,
  quanta,
  phosphor,
  redshift,
  kirby,
  blackboard,
  crafty,
}

enum SurfaceMaterialMode { solid, glass }

enum ThemeTexture { none, grain, scanlines, pixels, halftone, iridescent, darkIridescent }

enum ThemeMotion { snappy, fluid, elastic }

enum ThemeParticles {
  none,
  stardust,
  embers,
  voxels,
  chalkdust,
  ethereal,
  voidRain,
  quantum,
  whisps,
  inkblots,
}

enum ThemeInteraction { none, vibration, caustic, etch, warp, chalk, inkSplat }

/// Per-theme flavor layer on top of the base [ThemeMorphText] per-char
/// morph. Each value adds a small decorative pass during the transition
/// window — the base LCS-aligned slide + fade is always the substrate,
/// and the effect decorates which chars are arriving/leaving.
enum ThemeTextEffect {
  none, // pure fade+slide (petrichor — restraint)
  glint, // warm accent sweep L→R across the morph region (halo)
  stamp, // offset drop-shadow settling in on inserted chars (nightwalker)
  burn, // amber glow on leaving chars; cool glow on arriving (redshift)
  chalk, // small dust speckles at changing char positions (blackboard)
  pop, // single-frame scale snap on inserted chars (crafty)
  twinkle, // pale star-dots flash near inserted chars (aether)
  sparkle, // twinkle + a diagonal streak at collision (quanta)
  warmth, // amber tint on leaving chars as they fade (helix)
  outline, // chunky black ink stroke around glyphs (kirby)
  phosphor, // blurred green halo + horizontal CRT bleed (phosphor)
  iridescent, // mother-of-pearl hue cycle through glyphs — every char picks
              // up a shifting cyan→pink→lavender→gold tint sweeping by
              // glyph position + time, so the whole word shimmers (nacre)
}

const defaultThemeId = AppThemeId.aether;

class ThemeOption {
  final AppThemeId id;
  final String label;
  final String description;

  const ThemeOption(this.id, this.label, this.description);
}

class SurfaceMaterialGeometry {
  final double radius;
  final bool pixelated;
  final String? typography;
  final double fontScale;
  final double letterSpacingEm;

  const SurfaceMaterialGeometry({
    this.radius = 8,
    this.pixelated = false,
    this.typography,
    this.fontScale = 1,
    this.letterSpacingEm = 0,
  });
}

/// Tiered radii derived from the theme's `radius` so sub-elements
/// scale coherently with surfaces. A `BorderRadius.circular(4)`
/// hardcoded in widget code looks fine on Aether (radius 8) but
/// destroys themes like Crafty/Kirby (radius 0, sharp/pixelated)
/// where every chip should be square. These getters preserve that
/// scaling AND keep visual hierarchy: badges stay smaller than
/// pills which stay smaller than cards.
extension SurfaceMaterialGeometryRadii on SurfaceMaterialGeometry {
  /// Card-level radius — full theme radius. Use for content panels,
  /// rows that read as cards, popovers.
  double get cardRadius => radius;

  /// Pill / chip / button radius — half of card. Use for prominent
  /// sub-elements like file pills, link chips, action buttons,
  /// section containers.
  double get pillRadius => radius * 0.5;

  /// Badge / state-indicator radius — ~30% of card. Use for tight
  /// status badges (OPEN/MERGED/CLOSED), commit-count badges,
  /// hover backgrounds.
  double get badgeRadius => radius * 0.3;

  /// Tiny clip radius — ~20% of card. Use for sparkline clips,
  /// checkbox squares, narrow strips. Always 0 on pixelated themes.
  double get tinyRadius => radius * 0.2;
}

class SurfaceMaterialShader {
  final SurfaceMaterialMode mode;
  final double blurPx;
  final double saturatePct;
  final double opacityScale;
  final double edgeIntensity;
  final ThemeTexture texture;
  final double textureOpacity;
  final ThemeMotion motion;
  final double luminescence;
  final ThemeParticles particles;
  final double parallaxStrength;
  final ThemeInteraction interaction;
  final ThemeTextEffect textEffect;
  /// Chunky-border width for themes that lean into ink-line outlines
  /// (kirby). Most themes leave this at 0 and use [borderAlpha]
  /// from MaterialSurface for the standard 1px chrome stroke.
  final double outlineWidth;
  final SurfaceMaterialGeometry geometry;

  const SurfaceMaterialShader({
    required this.mode,
    required this.blurPx,
    required this.saturatePct,
    required this.opacityScale,
    required this.edgeIntensity,
    this.texture = ThemeTexture.none,
    this.textureOpacity = 0,
    this.motion = ThemeMotion.snappy,
    this.luminescence = 1,
    this.particles = ThemeParticles.none,
    this.parallaxStrength = 0.5,
    this.interaction = ThemeInteraction.none,
    this.textEffect = ThemeTextEffect.none,
    this.outlineWidth = 0,
    this.geometry = const SurfaceMaterialGeometry(),
  });

  Duration get duration {
    switch (motion) {
      case ThemeMotion.snappy:
        return const Duration(milliseconds: 80);
      case ThemeMotion.fluid:
        return const Duration(milliseconds: 180);
      case ThemeMotion.elastic:
        return const Duration(milliseconds: 250);
    }
  }

  Curve get curve {
    switch (motion) {
      case ThemeMotion.snappy:
        return Curves.easeOutCubic;
      case ThemeMotion.fluid:
        return Curves.easeInOutCubic;
      case ThemeMotion.elastic:
        return Curves.easeOutBack;
    }
  }

  /// Bounded counterpart to [curve] — never overshoots [0, 1]. Use this
  /// when you're animating a value with asserted bounds (BoxShadow
  /// blurRadius, Opacity, Color alpha) — extrapolation past 1.0 from
  /// [Curves.easeOutBack] makes `BoxShadow.lerp` compute a negative
  /// blurRadius, which trips a `Shadow` assertion in dart:ui/painting.dart
  /// and breaks the paint tree. For pure translation or scale effects
  /// where overshoot reads as character, keep using [curve].
  Curve get safeCurve {
    switch (motion) {
      case ThemeMotion.snappy:
        return Curves.easeOutCubic;
      case ThemeMotion.fluid:
        return Curves.easeInOutCubic;
      case ThemeMotion.elastic:
        return Curves.easeOutCubic;
    }
  }
}

class AppThemeDefinition {
  final ThemeOption option;
  final SurfaceMaterialShader shader;

  const AppThemeDefinition(this.option, this.shader);
}

class AppTokens {
  final AppThemeId id;
  final bool isDark;
  final Color bg0;
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surfaceAccent;
  final Color textStrong;
  final Color textNormal;
  final Color textMuted;
  final Color textFaint;
  final Color stateAdded;
  final Color stateModified;
  final Color stateDeleted;
  final Color stateConflicted;
  final Color stateStaged;
  final Color stateUnstaged;
  final Color focusRing;
  final Color accentBright;
  final Color eventStartTone;
  final Color chromeBorder;
  final Color chromeAccent;
  final Color danger;
  final Color dangerOverlay;
  final Color panelOverlay;
  final Color panelOverlayStrong;
  final Color inputOverlay;
  final Color diffOverlay;
  final Color btnBg;
  final Color btnHoverBg;
  final Color btnBorder;
  final Color btnText;
  final Color inputBg;
  final Color inputBorder;
  final Color inputFocusBorder;
  final Color sliderTrack;
  final Color sliderThumb;
  final Color sliderThumbBorder;
  final Color secondaryBtnBg;
  final Color itemHoverBg;
  final Color itemActiveBg;
  final Color itemActiveBorder;
  final Color secondaryBtnBorder;
  final Color secondaryBtnHoverBg;
  final Color rowBg;
  final Color scrollbarThumb;
  final Color scrollbarHover;
  final Color selectionBg;
  final Color shadowElev;
  final Color hyperChromatic1;
  final Color hyperChromatic2;
  final Color hyperCore;
  final Color hypercubePositive;
  final Color hypercubeNegative;
  final Color? themeAmbient;
  final double themeSparkOpacity;
  final Duration themeSparkSpeed;
  final double backdropBlur;
  final double backdropSaturate;
  final List<Color> appGradientColors;
  final List<AlignmentGeometry> appGradientAlignments;

  AppTokens._({
    required this.id,
    required this.isDark,
    required List<int> colors,
    required this.themeAmbient,
    required this.themeSparkOpacity,
    required this.themeSparkSpeed,
    required this.backdropBlur,
    required this.backdropSaturate,
    required this.appGradientColors,
    required this.appGradientAlignments,
  })  : bg0 = Color(colors[0]),
        bg1 = Color(colors[1]),
        bg2 = Color(colors[2]),
        bg3 = Color(colors[3]),
        surface0 = Color(colors[4]),
        surface1 = Color(colors[5]),
        surface2 = Color(colors[6]),
        surfaceAccent = Color(colors[7]),
        textStrong = Color(colors[8]),
        textNormal = Color(colors[9]),
        textMuted = Color(colors[10]),
        stateAdded = Color(colors[11]),
        stateModified = Color(colors[12]),
        stateDeleted = Color(colors[13]),
        stateConflicted = Color(colors[14]),
        stateStaged = Color(colors[15]),
        stateUnstaged = Color(colors[16]),
        focusRing = Color(colors[17]),
        accentBright = Color(colors[18]),
        chromeBorder = Color(colors[19]),
        chromeAccent = Color(colors[20]),
        danger = Color(colors[21]),
        panelOverlay = Color(colors[22]),
        panelOverlayStrong = Color(colors[23]),
        inputOverlay = Color(colors[24]),
        diffOverlay = Color(colors[25]),
        btnBg = Color(colors[26]),
        btnHoverBg = Color(colors[27]),
        btnBorder = Color(colors[28]),
        btnText = Color(colors[29]),
        inputBg = Color(colors[30]),
        inputBorder = Color(colors[31]),
        inputFocusBorder = Color(colors[32]),
        itemHoverBg = Color(colors[33]),
        itemActiveBg = Color(colors[34]),
        itemActiveBorder = Color(colors[35]),
        secondaryBtnBorder = Color(colors[36]),
        secondaryBtnHoverBg = Color(colors[37]),
        rowBg = Color(colors[38]),
        scrollbarThumb = Color(colors[39]),
        selectionBg = Color(colors[40]),
        shadowElev = Color(colors[41]),
        hyperChromatic1 = Color(colors[42]),
        hyperChromatic2 = Color(colors[43]),
        hyperCore = Color(colors[44]),
        hypercubePositive = Color(colors[45]),
        hypercubeNegative = Color(colors[46]),
        textFaint = Color(colors[47]),
        scrollbarHover = Color(colors[48]),
        secondaryBtnBg = Color(colors[49]),
        sliderTrack = Color(colors[50]),
        sliderThumb = Color(colors[51]),
        sliderThumbBorder = Color(colors[52]),
        dangerOverlay = Color(colors[53]),
        eventStartTone = Color(colors[54]);

  static AppTokens fromId(AppThemeId id) =>
      _tokens[id] ?? _tokens[defaultThemeId]!;
}

final _tokens = <AppThemeId, AppTokens>{
  AppThemeId.halo: AppTokens._(
    id: AppThemeId.halo,
    isDark: false,
    colors: const [
      0xFFFBF9F4,
      0xFFF7F3E8,
      0xFFEFEBD6,
      0xFFE6E0CC,
      0x85FFFFFF,
      0xC7FFFFFF,
      0xEBFFFFFF,
      0x47EBD7B4,
      0xFF322B24,
      0xFF4D453B,
      0xFF8E8579,
      0xFF36A47A,
      0xFFB5955A,
      0xFFCA5A56,
      0xFFD87C50,
      0xFF41B98D,
      0xFF7E95A1,
      0xFFD4AF37, // 17 focusRing — was pale cream (invisible on cream bg);
                  //                  gold matches the theme accent and is
                  //                  legible as a focus indicator.
      0xFFD4AF37,
      0xFFEBDEC9,
      0xFFEBD7B4,
      0xFFCA5A56,
      0xD1FFFEFC,
      0xE6FFFDF8,
      0x26FFFFFF,
      0xE6FEFCF8,
      0xFFFDFAF0,
      0xFFFFFFFF,
      0xFFEBDFCC,
      0xFF4D453B,
      0x4CFFFFFF,
      0x1AD4AF37,
      0xFFEBDFCC,
      0x1AF3E5AB,
      0x2EF3E5AB,
      0x40D4AF37,
      0x1FD4AF37,
      0xCCFFFFFF,
      0x40FFFFFF,
      0x1AD4AF37,
      0x4CEBD7B4,
      0x14184B0B,
      0xFFD4AF37,
      0xFFEDC9AF, // 43 hyperChromatic2 — rose-gold (was textNormal brown,
                  //                       which made the cybercube animation
                  //                       just two gold/brown colors with no
                  //                       chromatic split — divine palette
                  //                       wants warm-pink + gold + halo white)
      0xFFE89B4F, // 44 hyperCore — sunset amber-gold. Halo wants RADIANT,
                  //                  not aged — pearl-white blended into the
                  //                  cream bg, deep brass read as ancient,
                  //                  this is the saturated warm "burning
                  //                  core" of a divine aureole. Sits in hue
                  //                  between bright gold (chromatic1) and
                  //                  rose-gold (chromatic2) so the chromatic
                  //                  split visually wraps it with cooler
                  //                  edges — a saintly halo at peak glow.
      0xFF4D453B,
      0xFFD4AF37,
      0xFFB6AD9F,
      0x33D4AF37,
      0x80FFFFFF,
      0x33EBD7B4,
      0xFFEBDFCC,
      0xFFFFFFFF,
      0xD9FFF0EB,
      0xFFA89885,
    ],
    themeAmbient: const Color(0xFFF3EBD3),
    themeSparkOpacity: 0.35,
    themeSparkSpeed: const Duration(seconds: 22),
    backdropBlur: 24,
    backdropSaturate: 1.25,
    appGradientColors: const [
      Color(0xFFFDFBF7),
      Color(0xFFF9F6E9),
      Color(0xFFF2EFE4)
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight
    ],
  ),
  AppThemeId.nightwalker: AppTokens._(
    id: AppThemeId.nightwalker,
    isDark: true,
    colors: const [
      0xFF080808,
      0xFF0C0C0E,
      0xFF141416,
      0xFF1A1A1C,
      0xD90A0A0C,
      0xEB0F0F12,
      0xFA141418,
      0x2600F0FF,
      0xFFFFFFFF,
      0xFFCCCCCC,
      0xFF777777,
      0xFF00FFAA,
      0xFF00F0FF,
      0xFFFF3333,
      0xFFFF7700,
      0xFF00FF88,
      0xFF666666,
      0xFF00F0FF,
      0xFF00F0FF,
      0xFF28282D,
      0xFF00F0FF,
      0xFFFF3333,
      0x99000000,
      0xCC000000,
      0x0D00F0FF,
      0x66000000,
      0xFF1A1A1C,
      0xFF212124,
      0xFF333336,
      0xFF00F0FF,
      0xFF050505,
      0xFF28282C,
      0xFF00F0FF,
      0x0800F0FF,
      0x1400F0FF,
      0xFF00F0FF,
      0xFF28282C,
      0xCC1E1E23,
      0x660A0A0C,
      0xFF28282C,
      0x3300F0FF,
      0xCC000000,
      0xFF00F0FF,
      0xFFFF00CC, // 43 hyperChromatic2 — magenta (was green-cyan, which made
                  //                       hyper1+hyper2 both blue-greens with
                  //                       no split — true cyan/magenta CRT
                  //                       aberration is what nightwalker's
                  //                       chromatic core wants)
      0xFFFFFFFF,
      0xFF00FFAA,
      0xFF00F0FF,
      0xFF444444,
      0xFF333336,
      0x00000000,
      0xFF1A1A1C,
      0xFF00F0FF,
      0xFF050505,
      0x4C320000,
      0xFF888888,
    ],
    themeAmbient: const Color(0xFF00F0FF),
    themeSparkOpacity: 0.60,
    themeSparkSpeed: const Duration(seconds: 8),
    backdropBlur: 8,
    backdropSaturate: 2,
    appGradientColors: const [Color(0xFF050505), Color(0xFF0D0D0F)],
    appGradientAlignments: const [Alignment.topCenter, Alignment.bottomCenter],
  ),
  AppThemeId.petrichor: AppTokens._(
    id: AppThemeId.petrichor,
    isDark: false,
    colors: const [
      0xFFEDF2F4,
      0xFFE4EBEF,
      0xFFD6E0E5,
      0xFFC4D0D9,
      0xE6F8FBFC,
      0xEDF2F7F9,
      0xF2E8F0F4,
      0x336C9DB1,
      0xFF23323D,
      0xFF40515F,
      0xFF70818F,
      0xFF289374,
      0xFFA67F1B,
      0xFFC25752,
      0xFFD47A31,
      0xFF37A987,
      0xFF6F8294,
      0xFF6CA3BB,
      0xFF4B95AF,
      0xFF8199AA,
      0xFF5D98B2,
      0xFFC25752,
      0xC7F4F9FB,
      0xD6ECF4F8,
      0xD6EFF6F9,
      0xE0E7F0F5,
      0x145D98B2,
      0x2E5D98B2,
      0x408199AA,
      0xFF40515F,
      0x0F8199AA,
      0x408199AA,
      0x805D98B2,
      0x1A8199AA,
      0x1F5D98B2,
      0x4C5D98B2,
      0x408199AA,
      0x1F8199AA,
      0x0F8199AA,
      0x408199AA,
      0x4C5D98B2,
      0x3337495A,
      0xFF4B95AF,
      0xFF40515F,
      0xFF23323D,
      0xFF40515F,
      0xFF4B95AF,
      0xFF9AA7B2,
      0x738199AA,
      0x00000000,
      0x338199AA,
      0xFF4B95AF,
      0x00000000,
      0xDBFBE7E6,
      0xFF7E98A7,
    ],
    themeAmbient: const Color(0xFF5D98B2),
    themeSparkOpacity: 0.05,
    themeSparkSpeed: const Duration(seconds: 36),
    backdropBlur: 10,
    backdropSaturate: 1.1,
    appGradientColors: const [
      Color(0xFFD4E2E8),
      Color(0xFFE4EDF0),
      Color(0xFFD4DDE2)
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight
    ],
  ),
  AppThemeId.helix: AppTokens._(
    id: AppThemeId.helix,
    isDark: false,
    colors: const [
      0xFFF1E6D2,
      0xFFEFE2CB,
      0xFFE2D1B6,
      0xFFCFB996,
      0xE6FAF6ED,
      0xF0F5EEE2,
      0xF2E9DCC4,
      0x33C48F40,
      0xFF2F2519,
      0xFF49372A,
      0xFF755F4C,
      0xFF258A5A,
      0xFF9D7100,
      0xFFBE463F,
      0xFFD24F22,
      0xFF2F9F71,
      0xFF6D7F95,
      0xFF4E7F5E,
      0xFF0F8F74,
      0xFFA58A6E,
      0xFFCD7F2D,
      0xFFBE463F,
      0xC7FCF7EF,
      0xD6FBF4EA,
      0xD6F8EFE3,
      0xE0F6ECDE,
      0x1FCD7F2D,
      0x38CD7F2D,
      0x66A58A6E,
      0xFF49372A,
      0x14A58A6E,
      0x40A58A6E,
      0x80CD7F2D,
      0x1AA58A6E,
      0x1FCD7F2D,
      0x4CCD7F2D,
      0x40A58A6E,
      0x1FA58A6E,
      0x0FA58A6E,
      0x40A58A6E,
      0x4CCD7F2D,
      0x3D5C4524,
      0xFFCD7F2D,
      0xFF4E7F5E,
      0xFFFFCC66, // 44 hyperCore — warm honey (was dark brown text, which
                  //                  made the hypercube core invisible at
                  //                  small sizes and identical to chrome)
      0xFF0F8F5E, // 45 hypercubePositive — rich deep emerald
      0xFF4E7F5E, // 46 hypercubeNegative — muted sage (previous positive)
      0xFF9B835D,
      0x73A58A6E,
      0x00000000,
      0x33A58A6E,
      0xFF0F8F74,
      0x00000000,
      0xD6FFE6E0,
      0xFF9B835D,
    ],
    themeAmbient: const Color(0xFF8D7F4A),
    themeSparkOpacity: 0.09,
    themeSparkSpeed: const Duration(seconds: 34),
    backdropBlur: 0,
    backdropSaturate: 1,
    appGradientColors: const [
      Color(0xFFF4D8B5),
      Color(0xFFEFE7D6),
      Color(0xFFDED5BD)
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight
    ],
  ),
  // Nacre — pearl/cream base; the iridescent fragment shader paints a
  // position-derived hue spectrum on top of every surface, so the
  // static palette is intentionally restrained (dark legible text,
  // pale violet chrome, jewel-tone state colors). The shimmer is the
  // identity, the palette is the substrate.
  AppThemeId.nacre: AppTokens._(
    id: AppThemeId.nacre,
    isDark: false,
    colors: const [
      0xFFFBF6F0, // 0  bg0           — warm pearl
      0xFFF6EFE6, // 1  bg1
      0xFFEEE6DC, // 2  bg2
      0xFFE3DAD0, // 3  bg3
      0x99FFFAF2, // 4  surface0      — high translucency: iridescent bleeds through
      0xC4FBF5EC, // 5  surface1
      0xE0F8F0E2, // 6  surface2
      0x33B8A6E8, // 7  surfaceAccent — lavender wash
      0xFF1F1A2A, // 8  textStrong    — deep ink with a violet hint
      0xFF3A3447, // 9  textNormal
      0xFF6F6878, // 10 textMuted
      0xFF3FA98E, // 11 stateAdded    — sea green
      0xFFC58A4E, // 12 stateModified — amber
      0xFFC44A6F, // 13 stateDeleted  — rose
      0xFFD8643F, // 14 stateConflicted — coral
      0xFF4FB39A, // 15 stateStaged
      0xFF8E8898, // 16 stateUnstaged
      0xFFB89BE6, // 17 focusRing     — opal lavender
      0xFFB89BE6, // 18 accentBright
      0xFFD8CCDC, // 19 chromeBorder  — pale violet hairline
      0xFFB89BE6, // 20 chromeAccent
      0xFFC44A6F, // 21 danger
      0xB8FAF4EC, // 22 panelOverlay
      0xD4F7EFE3, // 23 panelOverlayStrong
      0x80FFFAF2, // 24 inputOverlay
      0xCCFAF4EC, // 25 diffOverlay
      0xFFF7EEDF, // 26 btnBg
      0xFFEFE3D0, // 27 btnHoverBg
      0x4DD8CCDC, // 28 btnBorder — translucent (was 0xFFD8CCDC fully opaque,
                  //                  which stamped a hard violet box around
                  //                  every button and fought Nacre's soft
                  //                  pearl character; ~30% lets buttons
                  //                  whisper instead of shout)
      0xFF3A3447, // 29 btnText
      0xFFFCF6EC, // 30 inputBg
      0x66D8CCDC, // 31 inputBorder — translucent for the same reason; inputs
                  //                    should melt into the surface, not box
                  //                    out of it. ~40% reads as defined-but-soft.
      0xFFB89BE6, // 32 inputFocusBorder
      0x22B89BE6, // 33 itemHoverBg
      0x40B89BE6, // 34 itemActiveBg
      0xFFB89BE6, // 35 itemActiveBorder
      0x4DD8CCDC, // 36 secondaryBtnBorder — same translucent treatment as
                  //                          btnBorder; ghost buttons in the
                  //                          X-Ray header used the full-alpha
                  //                          version and looked stamped-on
      0x14B89BE6, // 37 secondaryBtnHoverBg
      0xFFFAF4EC, // 38 rowBg
      0xFFC8BCD2, // 39 scrollbarThumb
      0x44B89BE6, // 40 selectionBg
      0x33B89BE6, // 41 shadowElev    — soft opal glow
      0xFF8FD3FF, // 42 hyperChromatic1 — cyan shimmer
      0xFFFF9CD9, // 43 hyperChromatic2 — pink shimmer
      0xFFB89BE6, // 44 hyperCore       — lavender (logo glow)
      0xFF3FA98E, // 45 hypercubePositive
      0xFFC44A6F, // 46 hypercubeNegative
      0xFFA59EB0, // 47 textFaint
      0xFFAA9DBC, // 48 scrollbarHover
      0xFFFCF6EC, // 49 secondaryBtnBg
      0xFFEFE3D0, // 50 sliderTrack
      0xFFFFFFFF, // 51 sliderThumb
      0xFFB89BE6, // 52 sliderThumbBorder
      0xCCFCEFE9, // 53 dangerOverlay
      0xFFB89BE6, // 54 eventStartTone
    ],
    themeAmbient: const Color(0xFFE8D9F2),
    themeSparkOpacity: 0.25,
    themeSparkSpeed: const Duration(seconds: 26),
    backdropBlur: 18,
    backdropSaturate: 1.4,
    appGradientColors: const [
      Color(0xFFFCF7F0),
      Color(0xFFF4ECE0),
      Color(0xFFEDE3D6),
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight,
    ],
  ),
  // Loverboy. Hot pink and lavender over warm-dark. The blacks have a
  // slight red-brown cast rather than cold obsidian.
  AppThemeId.loverboy: AppTokens._(
    id: AppThemeId.loverboy,
    isDark: true,
    colors: const [
      0xFF0C0609, // 0  bg0           — near-black, faint warmth underneath
      0xFF120A0E, // 1  bg1
      0xFF180E14, // 2  bg2
      0xFF201218, // 3  bg3
      0xFF120A0E, // 4  surface0      — solid; iridescent texture paints on top
      0xFF180E14, // 5  surface1      — solid
      0xFF1E1218, // 6  surface2      — solid
      0x33FF6EB4, // 7  surfaceAccent — rose blush wash (~20%)
      0xFFF0E8FF, // 8  textStrong    — near-white, lavender-tinted
      0xFFD4C8F0, // 9  textNormal    — lavender-white
      0xFF9080B8, // 10 textMuted     — medium lavender
      0xFF5ECC9B, // 11 stateAdded    — mint
      0xFFE8A84E, // 12 stateModified — amber
      0xFFFF6B8A, // 13 stateDeleted  — rose-red
      0xFFFF7A5C, // 14 stateConflicted — coral
      0xFF7ADEB8, // 15 stateStaged
      0xFF7A6A9B, // 16 stateUnstaged — dim lavender
      0xFFFF6EB4, // 17 focusRing     — hot pink
      0xFFFF6EB4, // 18 accentBright  — hot pink (identity colour)
      0xFFB09AE0, // 19 chromeBorder  — lavender hairline
      0xFFFF6EB4, // 20 chromeAccent  — hot pink
      0xFFFF6B8A, // 21 danger        — rose-red
      0xFF120A0E, // 22 panelOverlay        — solid
      0xFF180E14, // 23 panelOverlayStrong  — solid
      0xFF100E1A, // 24 inputOverlay        — solid
      0xFF180E14, // 25 diffOverlay         — solid
      0xFF1A1014, // 26 btnBg
      0xFF221418, // 27 btnHoverBg
      0x44FF6EB4, // 28 btnBorder     — translucent pink; whisper treatment
      0xFFD4C8F0, // 29 btnText
      0xFF160E12, // 30 inputBg
      0x55B09AE0, // 31 inputBorder   — translucent lavender; melts into surface
      0xFFFF6EB4, // 32 inputFocusBorder — hot pink
      0x22FF6EB4, // 33 itemHoverBg   — 13% pink
      0x40FF6EB4, // 34 itemActiveBg  — 25% pink
      0xFFFF6EB4, // 35 itemActiveBorder
      0x44B09AE0, // 36 secondaryBtnBorder — translucent lavender
      0x1AFF6EB4, // 37 secondaryBtnHoverBg
      0xFF120B0F, // 38 rowBg
      0xFF6A5490, // 39 scrollbarThumb — dim lavender
      0x44FF6EB4, // 40 selectionBg
      0x55FF6EB4, // 41 shadowElev    — pink glow shadow
      0xFFC4A8F5, // 42 hyperChromatic1 — soft lavender shimmer
      0xFFFF6EB4, // 43 hyperChromatic2 — hot pink shimmer
      0xFFFF6EB4, // 44 hyperCore       — pink logo glow
      0xFF4DE0F0, // 45 hypercubePositive — cyan (full CMYK with the pink)
      0xFFF5E050, // 46 hypercubeNegative — yellow
      0xFF5A4E7A, // 47 textFaint      — deep lavender (ghosted)
      0xFF8A70BA, // 48 scrollbarHover
      0xFF150C10, // 49 secondaryBtnBg
      0xFF221418, // 50 sliderTrack
      0xFFFFFFFF, // 51 sliderThumb
      0xFFFF6EB4, // 52 sliderThumbBorder — pink
      0xCC1A0812, // 53 dangerOverlay  — dark rose tint
      0xFFFF6EB4, // 54 eventStartTone
    ],
    themeAmbient: const Color(0xFFFF6EB4),
    themeSparkOpacity: 0.30,
    themeSparkSpeed: const Duration(seconds: 22),
    backdropBlur: 22,
    backdropSaturate: 1.6,
    appGradientColors: const [
      Color(0xFF0C0609),
      Color(0xFF160C10),
      Color(0xFF0E080A),
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight,
    ],
  ),
  AppThemeId.aether: AppTokens._(
    id: AppThemeId.aether,
    isDark: true,
    colors: const [
      0xFF0A0D12,
      0xFF0F141D,
      0xFF151B27,
      0xFF1F2634,
      0xBD0B0F16,
      0xC710161F,
      0xD1151D29,
      0x1F7693FF,
      0xFFF1F4FA,
      0xFFCFD7E7,
      0xFF8C98AD,
      0xFF49BE8F,
      0xFFDDBA61,
      0xFFE97571,
      0xFFF29A62,
      0xFF65CFA7,
      0xFF91A0BD,
      0xFF90A7FF,
      0xFF9DB2FF,
      0xFF51617E,
      0xFF7899FF,
      0xFFE97571,
      0xB80C1118,
      0xCC0E131C,
      0xDB0A0E15,
      0xE0090D14,
      0x147899FF,
      0x2E7899FF,
      0x4051617E,
      0xFFCFD7E7,
      0x0F51617E,
      0x4051617E,
      0x807899FF,
      0x1A51617E,
      0x1F7899FF,
      0x4C7899FF,
      0x4051617E,
      0x1F51617E,
      0x0F51617E,
      0x4051617E,
      0x4C7899FF,
      0x99080A1C,
      0xFFFF00FF,
      0xFF00FFFF,
      0xFFFFFFFF,
      0xFF00FFFF,
      0xFFFF00FF,
      0xFF5F6B7E,
      0x7351617E,
      0x00000000,
      0x3351617E,
      0xFF9DB2FF,
      0x00000000,
      0xDB3B181D,
      0xFF96A6CB,
    ],
    themeAmbient: const Color(0xFF7899FF),
    themeSparkOpacity: 0.12,
    themeSparkSpeed: const Duration(seconds: 28),
    backdropBlur: 16,
    backdropSaturate: 1.14,
    appGradientColors: const [
      Color(0xFF1A2333),
      Color(0xFF0D1118),
      Color(0xFF0A0D12)
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight
    ],
  ),
  AppThemeId.quanta: AppTokens._(
    id: AppThemeId.quanta,
    isDark: true,
    colors: const [
      0xFF020403,
      0xFF050A07,
      0xFF0A120D,
      0xFF121D15,
      0xA6030805,
      0xB0060E09,
      0xBA0A140E,
      0x1F00FF88,
      0xFFF0FFF4,
      0xFFC7D6CC,
      0xFF7A8C81,
      0xFF00FF88,
      0xFF00E0FF,
      0xFFFF4A4A,
      0xFFFF9900,
      0xFF00FFAA,
      0xFF667766,
      0xFF00FF88,
      0xFF00FFAA,
      0xFF192D23,
      0xFF00FF88,
      0xFFFF4A4A,
      0x8C020504,
      0xA6030706,
      0x0500FF88,
      0x4D000000,
      0xFF0A1A10,
      0xFF153822,
      0xFF1A3A25,
      0xFF00FF88,
      0x0F192D23,
      0x40192D23,
      0x8000FF88,
      0x0A00FF88,
      0x1400FF88,
      0xFF00FF88,
      0xFF1A3A25,
      0x990A190F,
      0x4D050C08,
      0xFF1A3A25,
      0x3300FF88,
      0xB300120C,
      0xFF00FF88,
      0xFF00E0FF,
      0xFFFF00CC, // 43 hyperChromatic2 — magenta (was pure white, which
                  //                       isn't chromatic at all — quanta's
                  //                       cybercube needs cyan + magenta to
                  //                       split into actual aberration)
      0xFFFFFFFF, // 44 hyperCore — pure white (was duplicate of chromatic1)
      0xFF00FF88,
      0xFF445249,
      0xFF224A30,
      0x66050F0A,
      0x33192D23,
      0xFF00FFAA,
      0x00000000,
      0x1A280505,
      0xFF7EA68A,
    ],
    themeAmbient: const Color(0xFF00FF88),
    themeSparkOpacity: 0.45,
    themeSparkSpeed: const Duration(seconds: 10),
    backdropBlur: 14,
    backdropSaturate: 1.32,
    appGradientColors: const [
      Color(0xFF061009),
      Color(0xFF030604),
      Color(0xFF020403)
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight
    ],
  ),
  AppThemeId.redshift: AppTokens._(
    id: AppThemeId.redshift,
    isDark: true,
    colors: const [
      0xFF050204,
      0xFF0F050A,
      0xFF18080F,
      0xFF220B15,
      0x4C0A0306,
      0xA612050A,
      0xD91E0A12,
      0x40FF0044,
      0xFFFFF5F7,
      0xFFD9B8C0,
      0xFF8C6A72,
      0xFF00FF88,
      0xFFFFCC44, // 12 stateModified — warm amber (was theme red 0xFFFF0044
                  //                     which conflicted with deleted's
                  //                     destructive semantics; modified is
                  //                     in-between, deserves a distinct hue)
      0xFFFF0044, // 13 stateDeleted — theme red (was 0xFF3D2A2E dark mauve,
                  //                    completely invisible on dark bg —
                  //                    "deleted" should be the strong negative
                  //                    color, which IS the redshift signature)
      0xFFFF7700,
      0xFF00FFAA,
      0xFF665555,
      0xFFFF0044,
      0xFFFF3366,
      0xFF782832,
      0xFFFF0044,
      0xFFFF0044,
      0x4C030001,
      0xD9050203,
      0x0DFF0044,
      0x99000000,
      0xFF0A0406,
      0xFF1A080D,
      0xFF220B12,
      0xFFFF0044,
      0x99050203,
      0xFF220B12,
      0x80FF0044,
      0x0DFF0044,
      0x1AFF0044,
      0x4CFF0044,
      0xFF220B12,
      0xB214080C,
      0x0F782832,
      0xFF1C0A0F,
      0x40FF0044,
      0xCC160408,
      0xFFFF0044,
      0xFFFF7700,
      0xFFFFFFFF,
      0xFFFF7700,
      0xFFFF0044,
      0xFF433236,
      0xFF2A0F18,
      0x800A0406,
      0x33782832,
      0xFFFF3366,
      0x00000000,
      0x4C280508,
      0xFFA67E8A,
    ],
    themeAmbient: const Color(0xFFFF0040),
    themeSparkOpacity: 0.60,
    themeSparkSpeed: const Duration(seconds: 15),
    backdropBlur: 24,
    backdropSaturate: 1.5,
    appGradientColors: const [
      Color(0xFF15050A),
      Color(0xFF0A0306),
      Color(0xFF050204)
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight
    ],
  ),
  AppThemeId.kirby: AppTokens._(
    id: AppThemeId.kirby,
    isDark: false,
    colors: const [
      // Aged newsprint palette + CMYK process accents. Real comic
      // books were printed on cheap pulp paper with 4-color separation
      // (Cyan / Magenta / Yellow / Black) — the colors here lock to
      // that printing reality, not generic "comic-y" pastels.
      0xFFEDE2BC, // 0  bg0          — aged newsprint, warm
      0xFFE5D8AC, // 1  bg1          — slightly deeper page
      0xFFDCCD9C, // 2  bg2          — page shadow
      0xFFD2C18A, // 3  bg3          — deepest crease
      0xCCF2EAC6, // 4  surface0     — lifted page
      0xE6F8F1D6, // 5  surface1     — clean page area
      0xFFFCF6E0, // 6  surface2     — cleanest paper highlight
      0x40FFD300, // 7  surfaceAccent — process-yellow wash
      0xFF14141A, // 8  textStrong   — process black ink
      0xFF24242C, // 9  textNormal
      0xFF5A5040, // 10 textMuted    — old-newsprint muted
      0xFF6B9F3D, // 11 stateAdded   — pulled CMYK green
      0xFFB8860B, // 12 stateModified — darkgoldenrod (process yellow on
                  //                    cream paper would be invisible; this
                  //                    is the "yellow ink baked into newsprint
                  //                    for 50 years" version: same hue family,
                  //                    finally readable on bg0)
      0xFFE63946, // 13 stateDeleted — comic spot red
      0xFFFF8C42, // 14 stateConflicted — printed orange
      0xFF00ACC8, // 15 stateStaged  — process cyan
      0xFF8A7E68, // 16 stateUnstaged — paper-aged gray
      0xFFE91E5F, // 17 focusRing    — process magenta (POW!)
      0xFF00ACC8, // 18 accentBright — process cyan (the cool accent)
      0xFF14141A, // 19 chromeBorder — INK LINE — every panel border
      0xFFE91E5F, // 20 chromeAccent — magenta highlight
      0xFFE63946, // 21 danger
      0xCCF2EAC6, // 22 panelOverlay
      0xE6E5D8AC, // 23 panelOverlayStrong
      0x99FCF6E0, // 24 inputOverlay
      0xCCF2EAC6, // 25 diffOverlay
      0xFFF8F1D6, // 26 btnBg        — clean page
      0xFFFFD300, // 27 btnHoverBg   — process yellow on hover (POW)
      0xFF14141A, // 28 btnBorder    — INK
      0xFF14141A, // 29 btnText      — INK
      0xFFFCF6E0, // 30 inputBg
      0xFF14141A, // 31 inputBorder
      0xFFE91E5F, // 32 inputFocusBorder — magenta
      0x40FFD300, // 33 itemHoverBg  — yellow wash
      0x66FFD300, // 34 itemActiveBg
      0xFF14141A, // 35 itemActiveBorder — INK
      0xFF14141A, // 36 secondaryBtnBorder
      0x33FFD300, // 37 secondaryBtnHoverBg
      0xFFF8F1D6, // 38 rowBg
      0xFF5A5040, // 39 scrollbarThumb
      0x66FFD300, // 40 selectionBg
      0x99000000, // 41 shadowElev   — hard ink-shadow drop
      0xFFE91E5F, // 42 hyperChromatic1 — magenta plate
      0xFF00ACC8, // 43 hyperChromatic2 — cyan plate
      0xFF14141A, // 44 hyperCore — process black (K of CMYK). Yellow plate
                  //                  was invisible on cream paper bg; black
                  //                  ink IS the defining color of the comic
                  //                  aesthetic and matches every chromeBorder
                  //                  in the theme. Cyan/magenta chromatic
                  //                  edges now wrap a true inked silhouette.
      0xFFC9272E, // 45 hypercubePositive — Marvel newsprint hero red.
                  //                       Eyedropped from the Spider-Man
                  //                       chest on Amazing Fantasy #15
                  //                       and Cap's stripes on Tales of
                  //                       Suspense. Muted by absorbent
                  //                       newsprint, NOT modern-screen
                  //                       saturated — sits on the cream
                  //                       paper bg without screaming.
      0xFF2A4A98, // 46 hypercubeNegative — Marvel newsprint hero blue.
                  //                       Spider-Man's web-suit blue,
                  //                       Cap's field, Reed Richards'
                  //                       uniform — same plate, same era.
                  //                       Slightly purple-tinted from
                  //                       the magenta bleed printers
                  //                       got on absorbent stock.
      0xFF8A7E68, // 47 textFaint
      0xFF8A7E68, // 48 scrollbarHover
      0xFFF8F1D6, // 49 secondaryBtnBg
      0xFFD2C18A, // 50 sliderTrack
      0xFF14141A, // 51 sliderThumb
      0xFF14141A, // 52 sliderThumbBorder
      0xCCFCE5E0, // 53 dangerOverlay
      0xFF00ACC8, // 54 eventStartTone — cyan
    ],
    themeAmbient: const Color(0xFFF0C040), // yellow ambient
    themeSparkOpacity: 0,
    themeSparkSpeed: const Duration(seconds: 30),
    backdropBlur: 0,
    backdropSaturate: 1,
    // Page light: warm key from the upper-left (like a comic-panel
    // light source), cooling toward the lower-right shadow side. Reads
    // as "this page is lit," not "flat cream."
    appGradientColors: const [
      Color(0xFFFFEAB8), // warm highlight UL
      Color(0xFFE5D8AC), // page mid
      Color(0xFFC8B888), // cool shadow LR
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight,
    ],
  ),
  AppThemeId.blackboard: AppTokens._(
    id: AppThemeId.blackboard,
    isDark: true,
    colors: const [
      0xFF141416,
      0xFF141416,
      0xFF141416,
      0xFF141416,
      0xFF141416,
      0xFF141416,
      0xFF141416,
      0x1F7693FF,
      0xFFFFFFFF,
      0xFFE6E6EB,
      0xFF9BA0A5,
      0xFF49BE8F,
      0xFFDDBA61,
      0xFFE97571,
      0xFFF29A62,
      0xFF65CFA7,
      0xFF91A0BD,
      0xFF90A7FF,
      0xFFFFFFFF,
      0xFFDCDCE1,
      0xFF96D2FF,
      0xFFFF828C,
      0x66FFFFFF, // 22 panelOverlay — chalk wash. Was 5% (invisible), then
                  //                    20% (still too sheer). 40% lifts the
                  //                    panel without making content fight
                  //                    the workspace bleed-through.
      0xB3FFFFFF, // 23 panelOverlayStrong — heavy chalk wash for the X-Ray
                  //                          and other content panels. 70%
                  //                          reads as a distinct surface
                  //                          with a hint of slate behind.
      0x00000000,
      0x00000000,
      0x00000000,
      0x14FFFFFF,
      0x66FFFFFF,
      0xFFE6E6EB,
      0x00000000,
      0x4CFFFFFF,
      0xFFFFFFFF,
      0x0DFFFFFF,
      0x1A96D2FF,
      0x6696D2FF,
      0x33FFFFFF,
      0x0DFFFFFF,
      0x00000000,
      0x33FFFFFF,
      0x40FFFFFF,
      0x00000000,
      0xFF96D2FF,
      0xFFFFFFFF, // 42 hyperChromatic1 — white chalk
      0xFF96D2FF, // 43 hyperChromatic2 — blue chalk (was white — three white
                  //                       slots gave the cybercube no
                  //                       chromatic separation; chalkboards
                  //                       are about COLORED chalks)
      0xFFFFFFCC, // 44 hyperCore — yellow chalk (warm cream, distinct from
                  //                  pure white so the core glows)
      0xFF96D2FF,
      0xFF5F6368,
      0x66FFFFFF,
      0x00000000,
      0x26FFFFFF,
      0xFFFFFFFF,
      0xFFFFFFFF,
      0x1AFF7896,
      0xFF96A6CB,
    ],
    themeAmbient: const Color(0xFFF0F5FA),
    themeSparkOpacity: 0.30,
    themeSparkSpeed: const Duration(seconds: 12),
    backdropBlur: 0,
    backdropSaturate: 1,
    appGradientColors: const [Color(0xFF141416), Color(0xFF141416)],
    appGradientAlignments: const [Alignment.topCenter, Alignment.bottomCenter],
  ),
  AppThemeId.crafty: AppTokens._(
    id: AppThemeId.crafty,
    isDark: true,
    colors: const [
      0xFF1C1511,
      0xFF241C17,
      0xFF29211C,
      0xFF3F342D,
      0xFF29211C,
      0xFF3F342D,
      0xFF4C4038,
      0x1F7693FF,
      0xFFFEFEFE,
      0xFFDCD4C8,
      0xFFA4968C,
      0xFF49BE8F,
      0xFFDDBA61,
      0xFFE97571,
      0xFFF29A62,
      0xFF65CFA7,
      0xFF91A0BD,
      0xFF90A7FF,
      0xFF70D655,
      0xFF100906,
      0xFF55AF41,
      0xFFE83C3C,
      0xCC17110E,
      0xE6100906,
      0xE61C1511,
      0xE617110E,
      0xFF8B5A2B,
      0xFFA06D3D,
      0xFF3D2918,
      0xFFFFFFFF,
      0xFF1C1511,
      0xFF584C44,
      0xFF70D655,
      0xFF3F342D,
      0xFF4C4038,
      0xFF70D655,
      0xFF100906,
      0xFF4C4038,
      0xFF1C1511,
      0xFF3D2918,
      0x6670D655,
      0xCC000000,
      0xFF8B5A2B,
      0xFF70D655,
      0xFFFFFFFF,
      0xFF70D655,
      0xFF8B5A2B,
      0xFF7A6E66,
      0xFF584C44,
      0xFF29211C,
      0xFF1C1511,
      0xFF55AF41,
      0xFF3D2918,
      0xD95A1414,
      0xFF96A6CB,
    ],
    themeAmbient: const Color(0xFF55AF41),
    themeSparkOpacity: 0,
    themeSparkSpeed: const Duration(seconds: 10),
    backdropBlur: 0,
    backdropSaturate: 1,
    appGradientColors: const [Color(0xFF17110E), Color(0xFF1C1511)],
    appGradientAlignments: const [Alignment.topCenter, Alignment.bottomCenter],
  ),
  // ── Phosphor — CRT terminal, green-on-black, scanlines ───────────
  // Iconic serial-line / VT220 vibe. Pure black background, bright
  // phosphor green text that bleeds horizontally like CRT signal,
  // amber as the secondary "warning" color (matches old terminals).
  // Scanlines come from the existing texture path. Square corners,
  // monospace everywhere.
  AppThemeId.phosphor: AppTokens._(
    id: AppThemeId.phosphor,
    isDark: true,
    colors: const [
      0xFF000000, // 0  bg0          — true black tube
      0xFF030806, // 1  bg1          — barely-lit black, hint of green
      0xFF071410, // 2  bg2          — dim phosphor wash, more lift
      0xFF0E2418, // 3  bg3          — deepest green-tinted dark
      0xCC020806, // 4  surface0     — translucent dark
      0xE6092113, // 5  surface1     — visibly-lifted surface
      0xFF0C2918, // 6  surface2     — most-lifted surface
      0x3300FF66, // 7  surfaceAccent — green wash
      0xFF7CFF99, // 8  textStrong   — bright phosphor — slightly desaturated
                  //                    so it doesn't burn the eye
      0xFF55CC77, // 9  textNormal   — phosphor body — readable, restful
      0xFF3D8855, // 10 textMuted    — dim phosphor
      0xFF77FF44, // 11 stateAdded   — bright lime
      0xFFFFB000, // 12 stateModified — amber (the OTHER CRT color)
      0xFFFF3344, // 13 stateDeleted — alarm red
      0xFFFF6622, // 14 stateConflicted — orange alert
      0xFF00DD55, // 15 stateStaged  — phosphor green
      0xFF005522, // 16 stateUnstaged — dim
      0xFFFFB000, // 17 focusRing    — amber focus ring
      0xFFFFB000, // 18 accentBright — amber (secondary CRT phosphor)
      0xFF005522, // 19 chromeBorder — dim green hairline
      0xFF00FF66, // 20 chromeAccent — bright green
      0xFFFF3344, // 21 danger
      0xCC020806, // 22 panelOverlay
      0xE6051A0E, // 23 panelOverlayStrong
      0x99030D08, // 24 inputOverlay
      0xCC020806, // 25 diffOverlay
      0xFF03100A, // 26 btnBg
      0xFF0A2418, // 27 btnHoverBg   — slight phosphor bloom
      0xFF00853A, // 28 btnBorder    — dim green
      0xFF00FF66, // 29 btnText      — bright phosphor
      0xFF030D08, // 30 inputBg
      0xFF005522, // 31 inputBorder
      0xFFFFB000, // 32 inputFocusBorder — amber
      0x2200FF66, // 33 itemHoverBg  — green wash
      0x4400FF66, // 34 itemActiveBg — stronger
      0xFF00FF66, // 35 itemActiveBorder
      0xFF005522, // 36 secondaryBtnBorder
      0x1100FF66, // 37 secondaryBtnHoverBg
      0xFF030D08, // 38 rowBg
      0xFF00853A, // 39 scrollbarThumb
      0x4400FF66, // 40 selectionBg
      0xCC00FF66, // 41 shadowElev   — phosphor glow shadow
      0xFF00FF66, // 42 hyperChromatic1 — phosphor green
      0xFFFFB000, // 43 hyperChromatic2 — amber
      0xFF7CFF99, // 44 hyperCore       — light phosphor (logo glow)
      0xFF77FF44, // 45 hypercubePositive — P1 lime phosphor
                  //                       (primary CRT emission)
      0xFFFFB000, // 46 hypercubeNegative — P3 amber phosphor
                  //                       (the other commercial CRT
                  //                       coating; same accent the
                  //                       theme already uses across
                  //                       focus rings + accentBright)
      0xFF005522, // 47 textFaint
      0xFF00DD55, // 48 scrollbarHover
      0xFF03100A, // 49 secondaryBtnBg
      0xFF0A1814, // 50 sliderTrack
      0xFF00FF66, // 51 sliderThumb
      0xFF00853A, // 52 sliderThumbBorder
      0xCC1A0606, // 53 dangerOverlay
      0xFFFFB000, // 54 eventStartTone — amber
    ],
    themeAmbient: const Color(0xFF00FF66), // phosphor green
    themeSparkOpacity: 0,
    themeSparkSpeed: const Duration(seconds: 30),
    backdropBlur: 0,
    backdropSaturate: 1,
    appGradientColors: const [Color(0xFF000000), Color(0xFF03070A)],
    appGradientAlignments: const [
      Alignment.topCenter,
      Alignment.bottomCenter,
    ],
  ),
};

AppThemeId normalizeThemeId(String value) {
  final normalized = value.trim().toLowerCase();
  for (final id in AppThemeId.values) {
    if (id.name == normalized) return id;
  }
  return defaultThemeId;
}

const themeDefinitions = <AppThemeDefinition>[
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.halo,
      'Halo',
      'the light that arrives before anything else does.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 32,
      saturatePct: 125,
      opacityScale: 0.75,
      edgeIntensity: 1.2,
      motion: ThemeMotion.fluid,
      luminescence: 1.5,
      particles: ThemeParticles.ethereal,
      textEffect: ThemeTextEffect.glint,
      parallaxStrength: 0.25,
      interaction: ThemeInteraction.caustic,
      geometry: SurfaceMaterialGeometry(
        radius: 12,
        typography: 'Playfair Display',
        fontScale: 1.12,
        letterSpacingEm: 0.035,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.nightwalker,
      'Nightwalker',
      'a fallen angel\'s halo cracks in cold obsidian rain - am i here?',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 8,
      saturatePct: 200,
      opacityScale: 0.85,
      edgeIntensity: 1.5,
      motion: ThemeMotion.snappy,
      luminescence: 0.2,
      particles: ThemeParticles.voidRain,
      textEffect: ThemeTextEffect.stamp,
      parallaxStrength: 0.3,
      interaction: ThemeInteraction.etch,
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: 'JetBrains Mono',
        fontScale: 0.95,
        letterSpacingEm: -0.01,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.petrichor,
      'Petrichor',
      'first light through fog before the sky remembers itself.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1.1,
      edgeIntensity: 0,
      motion: ThemeMotion.elastic,
      luminescence: 0.1,
      parallaxStrength: 0,
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.helix,
      'Helix',
      'honey tastes sweeter drizzled over expensive emeralds.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1.14,
      edgeIntensity: 0,
      texture: ThemeTexture.grain,
      textureOpacity: 0.15,
      motion: ThemeMotion.snappy,
      luminescence: 0.1,
      parallaxStrength: 0,
      textEffect: ThemeTextEffect.warmth,
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.nacre,
      'Nacre',
      'light pooling in mother-of-pearl. every surface its own quiet spectrum.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 18,
      saturatePct: 140,
      opacityScale: 0.78,
      edgeIntensity: 1.0,
      // Iridescent fragment shader paints position-derived hue
      // spectrum across each surface. The pearl bg shows through
      // the translucent surfaces so the whole UI shimmers.
      texture: ThemeTexture.iridescent,
      textureOpacity: 0.42,
      motion: ThemeMotion.fluid,
      luminescence: 1.2,
      particles: ThemeParticles.ethereal,
      textEffect: ThemeTextEffect.iridescent,
      parallaxStrength: 0.3,
      interaction: ThemeInteraction.caustic,
      geometry: SurfaceMaterialGeometry(
        radius: 14,
        typography: 'Playfair Display',
        fontScale: 1.08,
        letterSpacingEm: 0.025,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.loverboy,
      'Loverboy',
      '"i love you," into the void of overflowing thoughts.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 120,
      opacityScale: 1.0,
      edgeIntensity: 1.6,
      // Same hue physics as nacre's iridescent shader, compressed to
      // the pink/lavender/violet band.
      texture: ThemeTexture.darkIridescent,
      textureOpacity: 0.55,
      motion: ThemeMotion.fluid,
      luminescence: 1.4,
      particles: ThemeParticles.ethereal,
      textEffect: ThemeTextEffect.iridescent,
      parallaxStrength: 0.32,
      interaction: ThemeInteraction.caustic,
      // Thin directional hairline (kirby recipe) rather than a 2px stamp.
      outlineWidth: 1.0,
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: 'Playfair Display',
        fontScale: 1.08,
        letterSpacingEm: 0.025,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.aether,
      'Aether',
      'somewhere between the last star and the first thought. cold, clear, awake.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 16,
      saturatePct: 130,
      opacityScale: 0.82,
      edgeIntensity: 0.78,
      texture: ThemeTexture.scanlines,
      textureOpacity: 0.03,
      motion: ThemeMotion.fluid,
      luminescence: 0.4,
      particles: ThemeParticles.stardust,
      textEffect: ThemeTextEffect.twinkle,
      parallaxStrength: 0.26,
      interaction: ThemeInteraction.warp,
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.quanta,
      'Quanta',
      'i don\'t know what the goal is. i was protected till the end.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 22,
      saturatePct: 165,
      opacityScale: 0.62,
      edgeIntensity: 1.15,
      texture: ThemeTexture.scanlines,
      textureOpacity: 0.06,
      motion: ThemeMotion.fluid,
      luminescence: 0.75,
      particles: ThemeParticles.quantum,
      textEffect: ThemeTextEffect.sparkle,
      parallaxStrength: 0.3,
      interaction: ThemeInteraction.vibration,
      geometry: SurfaceMaterialGeometry(
        letterSpacingEm: 0.02,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.phosphor,
      'Phosphor',
      'something typed here before you. the screen is still warm to the touch.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1,
      edgeIntensity: 0.4,
      texture: ThemeTexture.scanlines,
      textureOpacity: 0.22,
      motion: ThemeMotion.snappy,
      luminescence: 0.7,
      particles: ThemeParticles.none,
      parallaxStrength: 0,
      interaction: ThemeInteraction.etch,
      textEffect: ThemeTextEffect.phosphor,
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: 'JetBrainsMono',
        fontScale: 0.98,
        letterSpacingEm: 0.01,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.redshift,
      'Redshift',
      'the light left. you\'re seeing the memory of where it was.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      // Harder geometry: less blur, higher edge intensity, snappy
      // motion. Palette and scanlines unchanged.
      blurPx: 10,
      saturatePct: 150,
      opacityScale: 0.92,
      edgeIntensity: 1.25,
      texture: ThemeTexture.scanlines,
      textureOpacity: 0.11,
      motion: ThemeMotion.snappy,
      luminescence: 0.45,
      particles: ThemeParticles.whisps,
      textEffect: ThemeTextEffect.burn,
      parallaxStrength: 0.35,
      outlineWidth: 0.6, // kirby-style hairline, directional shading
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: 'JetBrains Mono',
        letterSpacingEm: 0.01,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.kirby,
      'Kirby',
      'off-register ink on newsprint. was it always supposed to look like that?',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 110,
      opacityScale: 1,
      edgeIntensity: 0,
      // Halftone fully off — Marvel-Rivals-style cell shading is
      // about FLAT smooth fills with hard ink lines and rim lighting,
      // NOT print-comic dot bombardment.
      texture: ThemeTexture.none,
      textureOpacity: 0,
      motion: ThemeMotion.snappy,
      luminescence: 0.6,
      particles: ThemeParticles.inkblots,
      parallaxStrength: 0.25,
      interaction: ThemeInteraction.inkSplat,
      textEffect: ThemeTextEffect.outline,
      outlineWidth: 2.0,
      // Square panels — comic panels don't have rounded corners,
      // and Flutter's asymmetric Border (used for the rim-light
      // effect) only renders correctly with radius: 0.
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        fontScale: 1.0,
        letterSpacingEm: 0.005,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.blackboard,
      'Blackboard',
      'chalk dust in the air. something was just figured out.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 100,
      opacityScale: 1,
      edgeIntensity: 1,
      texture: ThemeTexture.grain,
      textureOpacity: 0.1,
      motion: ThemeMotion.snappy,
      luminescence: 0.1,
      particles: ThemeParticles.chalkdust,
      textEffect: ThemeTextEffect.chalk,
      parallaxStrength: 0.12,
      interaction: ThemeInteraction.chalk,
      geometry: SurfaceMaterialGeometry(
        radius: 2,
        typography: 'Lora',
        fontScale: 1.05,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.crafty,
      'Crafty',
      '16 colours. infinite time. nothing else mattered.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 150,
      opacityScale: 1,
      edgeIntensity: 0.8,
      texture: ThemeTexture.pixels,
      textureOpacity: 0.15,
      motion: ThemeMotion.snappy,
      luminescence: 0.4,
      particles: ThemeParticles.voxels,
      textEffect: ThemeTextEffect.pop,
      parallaxStrength: 0.3,
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        pixelated: true,
        typography: 'VT323',
        fontScale: 1.2,
        letterSpacingEm: 0.02,
      ),
    ),
  ),
];

final themeOptions = themeDefinitions
    .map((definition) => definition.option)
    .toList(growable: false);

// Built once (O(9)) and reused — avoids the O(9) linear scan that was
// happening on every `context.themeDefinition` access.
final Map<AppThemeId, AppThemeDefinition> _themeDefinitionById = {
  for (final definition in themeDefinitions) definition.option.id: definition,
};

AppThemeDefinition themeDefinitionFor(AppThemeId id) =>
    _themeDefinitionById[id] ?? _themeDefinitionById[defaultThemeId]!;

class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final AppTokens tokens;
  const AppThemeExtension(this.tokens);

  @override
  ThemeExtension<AppThemeExtension> copyWith({AppTokens? tokens}) =>
      AppThemeExtension(tokens ?? this.tokens);

  @override
  ThemeExtension<AppThemeExtension> lerp(
    covariant AppThemeExtension? other,
    double t,
  ) {
    if (other == null || t < 0.5) return this;
    return other;
  }
}

extension BuildContextTokens on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppThemeExtension>()!.tokens;
  AppThemeDefinition get themeDefinition => themeDefinitionFor(tokens.id);
  SurfaceMaterialShader get surfaceShader => themeDefinition.shader;
}

extension ClusterColors on AppTokens {
  /// Stripe / pill color for a coupling-cluster id. Returns null for
  /// "no cluster" (isolated files), so callers can fall back to a
  /// neutral chrome color. Hypercube palette — same identity as the
  /// app's logo so cluster groups read as part of the family rather
  /// than as alarm semantics. Step alpha down for the 5th+ cluster so
  /// far-out groups fade rather than flash.
  ///
  /// Promoted from a private helper in `changes_page.dart` so the
  /// branches lens (PR file pills) and any future surface that wants
  /// to visualize coupling can share the exact same color identity.
  Color? clusterStripeColor(int? clusterId) {
    if (clusterId == null || clusterId < 0) return null;
    final base = switch (clusterId % 4) {
      0 => hyperChromatic1,
      1 => hyperChromatic2,
      2 => eventStartTone,
      _ => stateAdded,
    };
    final step = clusterId ~/ 4;
    final alpha = (0.65 - step * 0.18).clamp(0.25, 0.65).toDouble();
    return base.withValues(alpha: alpha);
  }
}
