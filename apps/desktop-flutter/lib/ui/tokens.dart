import 'package:flutter/material.dart';

import 'design_primitives.dart';

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
  barbie,
}

enum SurfaceMaterialMode { solid, glass, phosphor }

enum ThemeTexture { none, grain, scanlines, pixels, halftone, iridescent, darkIridescent, gloss }

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
  /// Bibble. 4-point star sprites, alternating gold/magenta, upward
  /// drift with per-sprite rotation and twinkle. Glitter is *shaped*
  /// sparkle — distinct from `ethereal`'s diffuse dots or `stardust`'s
  /// cosmic points.
  glitter,
}

enum ThemeInteraction {
  none,
  vibration,
  caustic,
  etch,
  warp,
  chalk,
  inkSplat,
  /// Voxel burst on tap — small block shards spawn at the click and
  /// fall under gravity, rotate, and fade. Crafty.
  blockBreak,
  /// Bibble. Horizontal specular streak across the pressed element —
  /// magenta leading edge, gold trailing tail. Plastic catches light
  /// along a line; it doesn't ripple from a tap like `caustic`.
  gloss,
}

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
  pop, // single-frame scale snap on inserted chars
  blockify, // crafty: leaving chars fall with gravity + rotate +
            // fade (breaking); arriving chars drop from above with
            // a tiny easeOutBack bounce (placing)
  emeraldStamp, // helix: leaving chars amber-warm out; arriving chars
                // plummet onto the page with a hard impact compression
                // and fade from deep emerald to normal ink. Reads as
                // stamping a gem into wax — no blur, no glow, just
                // weight and saturation.
  twinkle, // pale star-dots flash near inserted chars (aether)
  sparkle, // twinkle + a diagonal streak at collision (quanta)
  warmth, // amber tint on leaving chars as they fade (helix)
  outline, // chunky black ink stroke around glyphs (kirby)
  phosphor, // blurred green halo + horizontal CRT bleed (phosphor)
  iridescent, // mother-of-pearl hue cycle through glyphs — every char picks
              // up a shifting cyan→pink→lavender→gold tint sweeping by
              // glyph position + time, so the whole word shimmers (nacre)
  shimmer,    // bibble: two-color gold→magenta band sweeps L→R across
              // changed chars, once per morph. not hue-cycling — that's
              // iridescent's job.
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

/// Physical material profile for the PBR liquid-glass fragment shader.
/// Only consumed when [SurfaceMaterialShader.mode] == glass. Every knob
/// maps to a real optical property:
///
///   [ior]         refractive index n. Drives Schlick F0, Cauchy
///                 dispersion strength, TIR critical angle, and the
///                 lensmaker focal length that positions the internal
///                 caustic. Typical values:
///                   1.46 fused silica   (cold, pure)
///                   1.52 BK7 crown      (workhorse optical glass)
///                   1.55 soft flint
///                   1.62 dense flint    (stronger dispersion)
///                   1.78 sapphire-ish   (dense, sharp rim)
///
///   [roughness]   GGX microfacet α. 0.02..0.08 reads as polished
///                 optical glass; 1.0 is fully matte. Also modulates
///                 the micro-grain amplitude.
///
///   [absorption]  Beer-Lambert extinction. `.rgb` is per-channel
///                 coefficient (1/px); `.a` is master strength. Clear
///                 glass = transparent black. Absorbed channels are
///                 the ones the glass removes from transmitted light,
///                 so an `absorption` of red/green gives a blue-ish tint.
///
///   [lightColor]  Light-source color. Specular and rim reflect this
///                 (physical: spec is the light source's color, not
///                 the material's). Null defers to theme accent.
class GlassMaterial {
  final double ior;
  final double roughness;
  final Color absorption;
  final Color? lightColor;

  const GlassMaterial({
    this.ior = 1.52,
    this.roughness = 0.05,
    this.absorption = const Color(0x00000000),
    this.lightColor,
  });

  /// Used by solid themes as a no-op placeholder; never reaches the shader.
  static const GlassMaterial none = GlassMaterial();
}

/// CRT-phosphor material profile. Only consumed when
/// [SurfaceMaterialShader.mode] == phosphor. Each knob maps to a real
/// CRT property:
///
///   [tint]           emissive phosphor color (P22 green by default —
///                    the original IBM/EIA monochrome standard;
///                    alpha scales the constant glow)
///   [maskPitch]      pixels per RGB aperture-grille triplet (3 = native
///                    subpixel, larger reads as coarser shadow mask)
///   [beamSigma]      horizontal beam Gaussian spread in px
///                    (0 = pin-sharp, larger blurs along scanlines)
///   [scanlineDepth]  inter-scanline darkening, 0..1
///                    (0 = no visible scanlines, 1 = half-dark bands)
///   [barrelAmount]   faceplate curvature / edge bow
///                    (0 = flat, 0.12+ reads as fishbowl)
class PhosphorMaterial {
  final Color tint;
  final double maskPitch;
  final double beamSigma;
  final double scanlineDepth;
  final double barrelAmount;

  const PhosphorMaterial({
    this.tint = const Color(0x5500FF88),
    this.maskPitch = 3.0,
    this.beamSigma = 0.55,
    this.scanlineDepth = 0.18,
    this.barrelAmount = 0.09,
  });

  static const PhosphorMaterial none = PhosphorMaterial();
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
  /// Per-theme text drop-shadows. Themes lean into a pixel-font
  /// identity (Crafty) attach a 1px offset black shadow here; the
  /// app's TextTheme threads it through every TextStyle so every
  /// glyph picks it up without widget-level changes.
  final List<Shadow>? textShadow;
  final SurfaceMaterialGeometry geometry;
  /// PBR glass parameters. Only consulted when [mode] == glass.
  final GlassMaterial glassMaterial;
  /// CRT phosphor parameters. Only consulted when [mode] == phosphor.
  final PhosphorMaterial phosphorMaterial;

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
    this.textShadow,
    this.geometry = const SurfaceMaterialGeometry(),
    this.glassMaterial = GlassMaterial.none,
    this.phosphorMaterial = PhosphorMaterial.none,
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
  final Color textStrong;
  final Color textNormal;
  final Color textMuted;
  final Color textFaint;
  final Color stateAdded;
  final Color stateModified;
  final Color stateDeleted;
  final Color stateConflicted;
  final Color stateStaged;
  final Color accentBright;
  final Color eventStartTone;
  final Color chromeBorder;
  final Color chromeAccent;
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
  final Color sliderTrack;
  final Color sliderThumb;
  final Color sliderThumbBorder;
  final Color itemHoverBg;
  final Color itemActiveBg;
  final Color itemActiveBorder;
  final Color secondaryBtnBorder;
  final Color secondaryBtnHoverBg;
  final Color rowBg;
  final Color scrollbarThumb;
  final Color shadowElev;
  final Color hyperChromatic1;
  final Color hyperChromatic2;
  final Color hyperCore;
  final Color hypercubePositive;
  final Color hypercubeNegative;
  final Color? _focusRingOverride;
  final Color? _dangerOverride;
  final Color? _inputFocusBorderOverride;
  final Color? themeAmbient;
  final double themeSparkOpacity;
  final Duration themeSparkSpeed;
  final double backdropBlur;
  final double backdropSaturate;
  final List<Color> appGradientColors;
  final List<AlignmentGeometry> appGradientAlignments;

  // These tokens share semantic defaults unless a theme opts out.
  Color get focusRing => _focusRingOverride ?? accentBright;
  Color get danger => _dangerOverride ?? stateDeleted;
  Color get inputFocusBorder => _inputFocusBorderOverride ?? focusRing;

  AppTokens._({
    required this.id,
    required this.isDark,
    required List<int> colors,
    int? focusRingOverride,
    int? dangerOverride,
    int? inputFocusBorderOverride,
    required this.themeAmbient,
    required this.themeSparkOpacity,
    required this.themeSparkSpeed,
    required this.backdropBlur,
    required this.backdropSaturate,
    required this.appGradientColors,
    required this.appGradientAlignments,
  })  : assert(colors.length == 47),
        bg0 = Color(colors[0]),
        bg1 = Color(colors[1]),
        bg2 = Color(colors[2]),
        bg3 = Color(colors[3]),
        surface0 = Color(colors[4]),
        surface1 = Color(colors[5]),
        surface2 = Color(colors[6]),
        textStrong = Color(colors[7]),
        textNormal = Color(colors[8]),
        textMuted = Color(colors[9]),
        stateAdded = Color(colors[10]),
        stateModified = Color(colors[11]),
        stateDeleted = Color(colors[12]),
        stateConflicted = Color(colors[13]),
        stateStaged = Color(colors[14]),
        accentBright = Color(colors[15]),
        chromeBorder = Color(colors[16]),
        chromeAccent = Color(colors[17]),
        panelOverlay = Color(colors[18]),
        panelOverlayStrong = Color(colors[19]),
        inputOverlay = Color(colors[20]),
        diffOverlay = Color(colors[21]),
        btnBg = Color(colors[22]),
        btnHoverBg = Color(colors[23]),
        btnBorder = Color(colors[24]),
        btnText = Color(colors[25]),
        inputBg = Color(colors[26]),
        inputBorder = Color(colors[27]),
        itemHoverBg = Color(colors[28]),
        itemActiveBg = Color(colors[29]),
        itemActiveBorder = Color(colors[30]),
        secondaryBtnBorder = Color(colors[31]),
        secondaryBtnHoverBg = Color(colors[32]),
        rowBg = Color(colors[33]),
        scrollbarThumb = Color(colors[34]),
        shadowElev = Color(colors[35]),
        hyperChromatic1 = Color(colors[36]),
        hyperChromatic2 = Color(colors[37]),
        hyperCore = Color(colors[38]),
        hypercubePositive = Color(colors[39]),
        hypercubeNegative = Color(colors[40]),
        textFaint = Color(colors[41]),
        sliderTrack = Color(colors[42]),
        sliderThumb = Color(colors[43]),
        sliderThumbBorder = Color(colors[44]),
        dangerOverlay = Color(colors[45]),
        eventStartTone = Color(colors[46]),
        _focusRingOverride = focusRingOverride == null
            ? null
            : Color(focusRingOverride),
        _dangerOverride = dangerOverride == null ? null : Color(dangerOverride),
        _inputFocusBorderOverride = inputFocusBorderOverride == null
            ? null
            : Color(inputFocusBorderOverride);

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
      0xFF322B24,
      0xFF4D453B,
      0xFF8E8579,
      0xFF36A47A,
      0xFFB5955A,
      0xFFCA5A56,
      0xFFD87C50,
      0xFF41B98D,
                  //                  gold matches the theme accent and is
                  //                  legible as a focus indicator.
      0xFFD4AF37,
      0xFFEBDEC9,
      0xFFEBD7B4,
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
      0x1AF3E5AB,
      0x2EF3E5AB,
      0x40D4AF37,
      0x1FD4AF37,
      0xCCFFFFFF,
      0x40FFFFFF,
      0x1AD4AF37,
      0x14184B0B,
      0xFFD4AF37,
      0xFFEDC9AF, // 37 hyperChromatic2 — rose-gold (was textNormal brown,
                  //                       which made the cybercube animation
                  //                       just two gold/brown colors with no
                  //                       chromatic split — divine palette
                  //                       wants warm-pink + gold + halo white)
      0xFFE89B4F, // 38 hyperCore — sunset amber-gold. Halo wants RADIANT,
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
      // Tight surface stepping — big jumps between surface tones read
      // as seams on this palette's near-black base.
      0xFF090909,
      0xFF0B0B0D,
      0xFF101014,
      0xFF16161A,
      0xD90A0A0C,
      0xEB0F0F12,
      0xFA141418,
      0xFFFFFFFF,
      0xFFCCCCCC,
      0xFF777777,
      0xFF00FFAA,
      0xFF00F0FF,
      0xFFFF3333,
      0xFFFF7700,
      0xFF00FF88,
      0xFF00F0FF,
      0xFF28282D,
      0xFF00F0FF,
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
      0x0800F0FF,
      0x1400F0FF,
      0xFF00F0FF,
      0xFF28282C,
      0xCC1E1E23,
      0x660A0A0C,
      0xFF28282C,
      0xCC000000,
      0xFF00F0FF,
      0xFFFF00CC, // 37 hyperChromatic2 — magenta (was green-cyan, which made
                  //                       hyper1+hyper2 both blue-greens with
                  //                       no split — true cyan/magenta CRT
                  //                       aberration is what nightwalker's
                  //                       chromatic core wants)
      0xFFFFFFFF,
      0xFF00FFAA,
      0xFF00F0FF,
      0xFF444444,
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
      0xFF23323D,
      0xFF40515F,
      0xFF70818F,
      0xFF289374,
      0xFFA67F1B,
      0xFFC25752,
      0xFFD47A31,
      0xFF37A987,
      0xFF4B95AF,
      0xFF8199AA,
      0xFF5D98B2,
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
      0x1A8199AA,
      0x1F5D98B2,
      0x4C5D98B2,
      0x408199AA,
      0x1F8199AA,
      0x0F8199AA,
      0x408199AA,
      0x3337495A,
      0xFF4B95AF,
      0xFF40515F,
      0xFF23323D,
      0xFF40515F,
      0xFF4B95AF,
      0xFF9AA7B2,
      0x338199AA,
      0xFF4B95AF,
      0x00000000,
      0xDBFBE7E6,
      0xFF7E98A7,
    ],
    focusRingOverride: 0xFF6CA3BB,
    inputFocusBorderOverride: 0x805D98B2,
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
      0xFF2F2519,
      0xFF49372A,
      0xFF755F4C,
      0xFF258A5A,
      0xFF9D7100,
      0xFFBE463F,
      0xFFD24F22,
      0xFF2F9F71,
      0xFF0F8F74,
      0xFFA58A6E,
      0xFFCD7F2D,
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
      0x1AA58A6E,
      0x1FCD7F2D,
      0x4CCD7F2D,
      0x40A58A6E,
      0x1FA58A6E,
      0x0FA58A6E,
      0x40A58A6E,
      0x3D5C4524,
      0xFFCD7F2D,
      0xFF4E7F5E,
      0xFFFFCC66, // 38 hyperCore — warm honey (was dark brown text, which
                  //                  made the hypercube core invisible at
                  //                  small sizes and identical to chrome)
      0xFF0F8F5E, // 39 hypercubePositive — rich deep emerald
      0xFF4E7F5E, // 40 hypercubeNegative — muted sage (previous positive)
      0xFF9B835D,
      0x33A58A6E,
      0xFF0F8F74,
      0x00000000,
      0xD6FFE6E0,
      0xFF9B835D,
    ],
    focusRingOverride: 0xFF4E7F5E,
    inputFocusBorderOverride: 0x80CD7F2D,
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
      0xFF1F1A2A, // 7  textStrong    — deep ink with a violet hint
      0xFF3A3447, // 8  textNormal
      0xFF6F6878, // 9 textMuted
      0xFF3FA98E, // 10 stateAdded    — sea green
      0xFFC58A4E, // 11 stateModified — amber
      0xFFC44A6F, // 12 stateDeleted  — rose
      0xFFD8643F, // 13 stateConflicted — coral
      0xFF4FB39A, // 14 stateStaged
      0xFFB89BE6, // 15 accentBright
      0xFFD8CCDC, // 16 chromeBorder  — pale violet hairline
      0xFFB89BE6, // 17 chromeAccent
      0xB8FAF4EC, // 18 panelOverlay
      0xD4F7EFE3, // 19 panelOverlayStrong
      0x80FFFAF2, // 20 inputOverlay
      0xCCFAF4EC, // 21 diffOverlay
      0xFFF7EEDF, // 22 btnBg
      0xFFEFE3D0, // 23 btnHoverBg
      0x4DD8CCDC, // 24 btnBorder — translucent (was 0xFFD8CCDC fully opaque,
                  //                  which stamped a hard violet box around
                  //                  every button and fought Nacre's soft
                  //                  pearl character; ~30% lets buttons
                  //                  whisper instead of shout)
      0xFF3A3447, // 25 btnText
      0xFFFCF6EC, // 26 inputBg
      0x66D8CCDC, // 27 inputBorder — translucent for the same reason; inputs
                  //                    should melt into the surface, not box
                  //                    out of it. ~40% reads as defined-but-soft.
      0x22B89BE6, // 28 itemHoverBg
      0x40B89BE6, // 29 itemActiveBg
      0xFFB89BE6, // 30 itemActiveBorder
      0x4DD8CCDC, // 31 secondaryBtnBorder — same translucent treatment as
                  //                          btnBorder; ghost buttons in the
                  //                          X-Ray header used the full-alpha
                  //                          version and looked stamped-on
      0x14B89BE6, // 32 secondaryBtnHoverBg
      0xFFFAF4EC, // 33 rowBg
      0xFFC8BCD2, // 34 scrollbarThumb
      0x33B89BE6, // 35 shadowElev    — soft opal glow
      0xFF8FD3FF, // 36 hyperChromatic1 — cyan shimmer
      0xFFFF9CD9, // 37 hyperChromatic2 — pink shimmer
      0xFFB89BE6, // 38 hyperCore       — lavender (logo glow)
      0xFF3FA98E, // 39 hypercubePositive
      0xFFC44A6F, // 40 hypercubeNegative
      0xFFA59EB0, // 41 textFaint
      0xFFEFE3D0, // 42 sliderTrack
      0xFFFFFFFF, // 43 sliderThumb
      0xFFB89BE6, // 44 sliderThumbBorder
      0xCCFCEFE9, // 45 dangerOverlay
      0xFFB89BE6, // 46 eventStartTone
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
      0xFFF0E8FF, // 7  textStrong    — near-white, lavender-tinted
      0xFFD4C8F0, // 8  textNormal    — lavender-white
      0xFF9080B8, // 9 textMuted     — medium lavender
      0xFF5ECC9B, // 10 stateAdded    — mint
      0xFFE8A84E, // 11 stateModified — amber
      0xFFFF6B8A, // 12 stateDeleted  — rose-red
      0xFFFF7A5C, // 13 stateConflicted — coral
      0xFF7ADEB8, // 14 stateStaged
      0xFFFF6EB4, // 15 accentBright  — hot pink (identity colour)
      0xFFB09AE0, // 16 chromeBorder  — lavender hairline
      0xFFFF6EB4, // 17 chromeAccent  — hot pink
      0xFF120A0E, // 18 panelOverlay        — solid
      0xFF180E14, // 19 panelOverlayStrong  — solid
      0xFF100E1A, // 20 inputOverlay        — solid
      0xFF180E14, // 21 diffOverlay         — solid
      0xFF1A1014, // 22 btnBg
      0xFF221418, // 23 btnHoverBg
      0x44FF6EB4, // 24 btnBorder     — translucent pink; whisper treatment
      0xFFD4C8F0, // 25 btnText
      0xFF160E12, // 26 inputBg
      0x55B09AE0, // 27 inputBorder   — translucent lavender; melts into surface
      0x22FF6EB4, // 28 itemHoverBg   — 13% pink
      0x40FF6EB4, // 29 itemActiveBg  — 25% pink
      0xFFFF6EB4, // 30 itemActiveBorder
      0x44B09AE0, // 31 secondaryBtnBorder — translucent lavender
      0x1AFF6EB4, // 32 secondaryBtnHoverBg
      0xFF120B0F, // 33 rowBg
      0xFF6A5490, // 34 scrollbarThumb — dim lavender
      0x55FF6EB4, // 35 shadowElev    — pink glow shadow
      0xFFC4A8F5, // 36 hyperChromatic1 — soft lavender shimmer
      0xFFFF6EB4, // 37 hyperChromatic2 — hot pink shimmer
      0xFFFF6EB4, // 38 hyperCore       — pink logo glow
      0xFF4DE0F0, // 39 hypercubePositive — cyan (full CMYK with the pink)
      0xFFF5E050, // 40 hypercubeNegative — yellow
      0xFF5A4E7A, // 41 textFaint      — deep lavender (ghosted)
      0xFF221418, // 42 sliderTrack
      0xFFFFFFFF, // 43 sliderThumb
      0xFFFF6EB4, // 44 sliderThumbBorder — pink
      0xCC1A0812, // 45 dangerOverlay  — dark rose tint
      0xFFFF6EB4, // 46 eventStartTone
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
      0xFFF1F4FA,
      0xFFCFD7E7,
      0xFF8C98AD,
      0xFF49BE8F,
      0xFFDDBA61,
      0xFFE97571,
      0xFFF29A62,
      0xFF65CFA7,
      0xFF9DB2FF,
      0xFF51617E,
      0xFF7899FF,
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
      0x1A51617E,
      0x1F7899FF,
      0x4C7899FF,
      0x4051617E,
      0x1F51617E,
      0x0F51617E,
      0x4051617E,
      0x99080A1C,
      0xFFFF00FF,
      0xFF00FFFF,
      0xFFFFFFFF,
      0xFF00FFFF,
      0xFFFF00FF,
      0xFF5F6B7E,
      0x3351617E,
      0xFF9DB2FF,
      0x00000000,
      0xDB3B181D,
      0xFF96A6CB,
    ],
    focusRingOverride: 0xFF90A7FF,
    inputFocusBorderOverride: 0x807899FF,
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
      0xFFF0FFF4,
      0xFFC7D6CC,
      0xFF7A8C81,
      0xFF00FF88,
      0xFF00E0FF,
      0xFFFF4A4A,
      0xFFFF9900,
      0xFF00FFAA,
      0xFF00FFAA,
      0xFF192D23,
      0xFF00FF88,
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
      0x0A00FF88,
      0x1400FF88,
      0xFF00FF88,
      0xFF1A3A25,
      0x990A190F,
      0x4D050C08,
      0xFF1A3A25,
      0xB300120C,
      0xFF00FF88,
      0xFF00E0FF,
      0xFFFF00CC, // 37 hyperChromatic2 — magenta (was pure white, which
                  //                       isn't chromatic at all — quanta's
                  //                       cybercube needs cyan + magenta to
                  //                       split into actual aberration)
      0xFFFFFFFF, // 38 hyperCore — pure white (was duplicate of chromatic1)
      0xFF00FF88,
      0xFF445249,
      0x33192D23,
      0xFF00FFAA,
      0x00000000,
      0x1A280505,
      0xFF7EA68A,
    ],
    focusRingOverride: 0xFF00FF88,
    inputFocusBorderOverride: 0x8000FF88,
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
      0xFFFFF5F7,
      0xFFD9B8C0,
      0xFF8C6A72,
      0xFF00FF88,
      0xFFFFCC44, // 11 stateModified — warm amber (was theme red 0xFFFF0044
                  //                     which conflicted with deleted's
                  //                     destructive semantics; modified is
                  //                     in-between, deserves a distinct hue)
      0xFFFF0044, // 12 stateDeleted — theme red (was 0xFF3D2A2E dark mauve,
                  //                    completely invisible on dark bg —
                  //                    "deleted" should be the strong negative
                  //                    color, which IS the redshift signature)
      0xFFFF7700,
      0xFF00FFAA,
      0xFFFF3366,
      0xFF782832,
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
      0x0DFF0044,
      0x1AFF0044,
      0x4CFF0044,
      0xFF220B12,
      0xB214080C,
      0x0F782832,
      0xFF1C0A0F,
      0xCC160408,
      0xFFFF0044,
      0xFFFF7700,
      0xFFFFFFFF,
      0xFFFF7700,
      0xFFFF0044,
      0xFF433236,
      0x33782832,
      0xFFFF3366,
      0x00000000,
      0x4C280508,
      0xFFA67E8A,
    ],
    focusRingOverride: 0xFFFF0044,
    inputFocusBorderOverride: 0x80FF0044,
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
      0xFF14141A, // 7  textStrong   — process black ink
      0xFF24242C, // 8  textNormal
      0xFF5A5040, // 9 textMuted    — old-newsprint muted
      0xFF6B9F3D, // 10 stateAdded   — pulled CMYK green
      0xFFB8860B, // 11 stateModified — darkgoldenrod (process yellow on
                  //                    cream paper would be invisible; this
                  //                    is the "yellow ink baked into newsprint
                  //                    for 50 years" version: same hue family,
                  //                    finally readable on bg0)
      0xFFE63946, // 12 stateDeleted — comic spot red
      0xFFFF8C42, // 13 stateConflicted — printed orange
      0xFF00ACC8, // 14 stateStaged  — process cyan
      0xFF00ACC8, // 15 accentBright — process cyan (the cool accent)
      0xFF14141A, // 16 chromeBorder — INK LINE — every panel border
      0xFFE91E5F, // 17 chromeAccent — magenta highlight
      0xCCF2EAC6, // 18 panelOverlay
      0xE6E5D8AC, // 19 panelOverlayStrong
      0x99FCF6E0, // 20 inputOverlay
      0xCCF2EAC6, // 21 diffOverlay
      0xFFF8F1D6, // 22 btnBg        — clean page
      0xFFFFD300, // 23 btnHoverBg   — process yellow on hover (POW)
      0xFF14141A, // 24 btnBorder    — INK
      0xFF14141A, // 25 btnText      — INK
      0xFFFCF6E0, // 26 inputBg
      0xFF14141A, // 27 inputBorder
      0x40FFD300, // 28 itemHoverBg  — yellow wash
      0x66FFD300, // 29 itemActiveBg
      0xFF14141A, // 30 itemActiveBorder — INK
      0xFF14141A, // 31 secondaryBtnBorder
      0x33FFD300, // 32 secondaryBtnHoverBg
      0xFFF8F1D6, // 33 rowBg
      0xFF5A5040, // 34 scrollbarThumb
      0x99000000, // 35 shadowElev   — hard ink-shadow drop
      0xFFE91E5F, // 36 hyperChromatic1 — magenta plate
      0xFF00ACC8, // 37 hyperChromatic2 — cyan plate
      0xFF14141A, // 38 hyperCore — process black (K of CMYK). Yellow plate
                  //                  was invisible on cream paper bg; black
                  //                  ink IS the defining color of the comic
                  //                  aesthetic and matches every chromeBorder
                  //                  in the theme. Cyan/magenta chromatic
                  //                  edges now wrap a true inked silhouette.
      0xFFC9272E, // 39 hypercubePositive — Marvel newsprint hero red.
                  //                       Eyedropped from the Spider-Man
                  //                       chest on Amazing Fantasy #15
                  //                       and Cap's stripes on Tales of
                  //                       Suspense. Muted by absorbent
                  //                       newsprint, NOT modern-screen
                  //                       saturated — sits on the cream
                  //                       paper bg without screaming.
      0xFF2A4A98, // 40 hypercubeNegative — Marvel newsprint hero blue.
                  //                       Spider-Man's web-suit blue,
                  //                       Cap's field, Reed Richards'
                  //                       uniform — same plate, same era.
                  //                       Slightly purple-tinted from
                  //                       the magenta bleed printers
                  //                       got on absorbent stock.
      0xFF8A7E68, // 41 textFaint
      0xFFD2C18A, // 42 sliderTrack
      0xFF14141A, // 43 sliderThumb
      0xFF14141A, // 44 sliderThumbBorder
      0xCCFCE5E0, // 45 dangerOverlay
      0xFF00ACC8, // 46 eventStartTone — cyan
    ],
    focusRingOverride: 0xFFE91E5F,
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
      0xFFFFFFFF,
      0xFFE6E6EB,
      0xFF9BA0A5,
      0xFF49BE8F,
      0xFFDDBA61,
      0xFFE97571,
      0xFFF29A62,
      0xFF65CFA7,
      0xFFFFFFFF,
      0xFFDCDCE1,
      0xFF96D2FF,
      0x66FFFFFF, // 18 panelOverlay — chalk wash. Was 5% (invisible), then
                  //                    20% (still too sheer). 40% lifts the
                  //                    panel without making content fight
                  //                    the workspace bleed-through.
      0xB3FFFFFF, // 19 panelOverlayStrong — heavy chalk wash for the X-Ray
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
      0x0DFFFFFF,
      0x1A96D2FF,
      0x6696D2FF,
      0x33FFFFFF,
      0x0DFFFFFF,
      0x00000000,
      0x33FFFFFF,
      0x00000000,
      0xFF96D2FF,
      0xFFFFFFFF, // 36 hyperChromatic1 — white chalk
      0xFF96D2FF, // 37 hyperChromatic2 — blue chalk (was white — three white
                  //                       slots gave the cybercube no
                  //                       chromatic separation; chalkboards
                  //                       are about COLORED chalks)
      0xFFFFFFCC, // 38 hyperCore — yellow chalk (warm cream, distinct from
                  //                  pure white so the core glows)
      0xFF96D2FF,
      0xFF5F6368,
      0x26FFFFFF,
      0xFFFFFFFF,
      0xFFFFFFFF,
      0x1AFF7896,
      0xFF96A6CB,
    ],
    focusRingOverride: 0xFF90A7FF,
    dangerOverride: 0xFFFF828C,
    inputFocusBorderOverride: 0xFFFFFFFF,
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
      0xFF332821, // tightened from 0xFF3F342D — old step was ~4× the
                  // earlier bg steps and read as a seam.
      0xFF29211C,
      0xFF332821,
      0xFF40342B,
      0xFFFEFEFE,
      0xFFDCD4C8,
      0xFFA4968C,
      0xFF49BE8F,
      0xFFDDBA61,
      0xFFE97571,
      0xFFF29A62,
      0xFF65CFA7,
      0xFF70D655,
      0xFF100906,
      0xFF55AF41,
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
      0xFF3F342D,
      0xFF4C4038,
      0xFF70D655,
      0xFF100906,
      0xFF4C4038,
      0xFF1C1511,
      0xFF3D2918,
      0xCC000000,
      0xFF8B5A2B,
      0xFF70D655,
      0xFFFFFFFF,
      0xFF70D655,
      0xFF8B5A2B,
      0xFF7A6E66,
      0xFF1C1511,
      0xFF55AF41,
      0xFF3D2918,
      0xD95A1414,
      0xFF96A6CB,
    ],
    focusRingOverride: 0xFF90A7FF,
    dangerOverride: 0xFFE83C3C,
    inputFocusBorderOverride: 0xFF70D655,
    themeAmbient: const Color(0xFF55AF41),
    themeSparkOpacity: 0,
    themeSparkSpeed: const Duration(seconds: 10),
    backdropBlur: 0,
    backdropSaturate: 1,
    appGradientColors: const [Color(0xFF17110E), Color(0xFF1C1511)],
    appGradientAlignments: const [Alignment.topCenter, Alignment.bottomCenter],
  ),
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
      0xFF7CFF99, // 7  textStrong   — bright phosphor — slightly desaturated
                  //                    so it doesn't burn the eye
      0xFF55CC77, // 8  textNormal   — phosphor body — readable, restful
      0xFF3D8855, // 9 textMuted    — dim phosphor
      0xFF77FF44, // 10 stateAdded   — bright lime
      0xFFFFB000, // 11 stateModified — amber (the OTHER CRT color)
      0xFFFF3344, // 12 stateDeleted — alarm red
      0xFFFF6622, // 13 stateConflicted — orange alert
      0xFF00DD55, // 14 stateStaged  — phosphor green
      0xFFFFB000, // 15 accentBright — amber (secondary CRT phosphor)
      0xFF005522, // 16 chromeBorder — dim green hairline
      0xFF00FF66, // 17 chromeAccent — bright green
      0xCC020806, // 18 panelOverlay
      0xE6051A0E, // 19 panelOverlayStrong
      0x99030D08, // 20 inputOverlay
      0xCC020806, // 21 diffOverlay
      0xFF03100A, // 22 btnBg
      0xFF0A2418, // 23 btnHoverBg   — slight phosphor bloom
      0xFF00853A, // 24 btnBorder    — dim green
      0xFF00FF66, // 25 btnText      — bright phosphor
      0xFF030D08, // 26 inputBg
      0xFF005522, // 27 inputBorder
      0x2200FF66, // 28 itemHoverBg  — green wash
      0x4400FF66, // 29 itemActiveBg — stronger
      0xFF00FF66, // 30 itemActiveBorder
      0xFF005522, // 31 secondaryBtnBorder
      0x1100FF66, // 32 secondaryBtnHoverBg
      0xFF030D08, // 33 rowBg
      0xFF00853A, // 34 scrollbarThumb
      0xCC00FF66, // 35 shadowElev   — phosphor glow shadow
      0xFF00FF66, // 36 hyperChromatic1 — phosphor green
      0xFFFFB000, // 37 hyperChromatic2 — amber
      0xFF7CFF99, // 38 hyperCore       — light phosphor (logo glow)
      0xFF77FF44, // 39 hypercubePositive — P1 lime phosphor
                  //                       (primary CRT emission)
      0xFFFFB000, // 40 hypercubeNegative — P3 amber phosphor
                  //                       (the other commercial CRT
                  //                       coating; same accent the
                  //                       theme already uses across
                  //                       focus rings + accentBright)
      0xFF005522, // 41 textFaint
      0xFF0A1814, // 42 sliderTrack
      0xFF00FF66, // 43 sliderThumb
      0xFF00853A, // 44 sliderThumbBorder
      0xCC1A0606, // 45 dangerOverlay
      0xFFFFB000, // 46 eventStartTone — amber
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
  AppThemeId.barbie: AppTokens._(
    id: AppThemeId.barbie,
    isDark: false,
    // Bibble. Text tones stay plum-family (magenta in shadow) so the
    // palette reads as one world, not pink on top of gray.
    colors: const [
      0xFFFFF5F9, // 0  bg0 — strawberry-milk cream
      0xFFFFEAF2, // 1  bg1
      0xFFFFDCE9, // 2  bg2
      0xFFFFC8DC, // 3  bg3
      0xFFFFF5F9, // 4  surface0
      0xFFFFEAF2, // 5  surface1
      0xFFFFDCE9, // 6  surface2
      0xFF3A1222, // 7  textStrong — plum-black, readable on pink
      0xFF5E2340, // 8  textNormal
      0xFFA87090, // 9  textMuted
      0xFF2EC5C1, // 10 stateAdded — turquoise. green fights the palette.
      0xFFFFC727, // 11 stateModified — logo yellow
      0xFFFF4D6D, // 12 stateDeleted — coral, not pure red (fights accent)
      0xFFFF7A5C, // 13 stateConflicted
      0xFFFF9EC7, // 14 stateStaged
      0xFFE0218A, // 15 accentBright — pantone 219c
      0xFFFF6EB4, // 16 chromeBorder
      0xFFE0218A, // 17 chromeAccent
      0xFFFFEAF2, // 18 panelOverlay
      0xFFFFDCE9, // 19 panelOverlayStrong
      0xFFFFF0F6, // 20 inputOverlay
      0xFFFFE8F1, // 21 diffOverlay
      0xFFFFDCE9, // 22 btnBg
      0xFFFFC8DC, // 23 btnHoverBg
      0x55E0218A, // 24 btnBorder
      0xFF3A1222, // 25 btnText
      0xFFFFFFFF, // 26 inputBg — pure white so inputs look inset vs bg0
      0x66E0218A, // 27 inputBorder
      0x1AE0218A, // 28 itemHoverBg — 10%, base is already pink
      0x33E0218A, // 29 itemActiveBg
      0xFFE0218A, // 30 itemActiveBorder
      0x44E0218A, // 31 secondaryBtnBorder
      0x1AE0218A, // 32 secondaryBtnHoverBg
      0xFFFFF0F6, // 33 rowBg
      0xFFE0218A, // 34 scrollbarThumb
      0x44E0218A, // 35 shadowElev — colored shadow, not black
      0xFFFFC727, // 36 hyperChromatic1 — yellow
      0xFFE0218A, // 37 hyperChromatic2 — magenta
      0xFFE0218A, // 38 hyperCore
      0xFF2EC5C1, // 39 hypercubePositive — turquoise (CMY trio)
      0xFFFFC727, // 40 hypercubeNegative — yellow
      0xFFD9B0C4, // 41 textFaint
      0xFFFFDCE9, // 42 sliderTrack
      0xFFFFFFFF, // 43 sliderThumb
      0xFFE0218A, // 44 sliderThumbBorder
      0xCCFFE0EC, // 45 dangerOverlay — pink-tinted so cream doesn't read bloody
      0xFFE0218A, // 46 eventStartTone
    ],
    themeAmbient: const Color(0xFFE0218A),
    themeSparkOpacity: 0.45,
    // matches the glitter particle cycle so logo + backdrop share tempo
    themeSparkSpeed: const Duration(seconds: 14),
    backdropBlur: 0,
    backdropSaturate: 1.2,
    appGradientColors: const [
      Color(0xFFFFF5F9),
      Color(0xFFFFEAF2),
      Color(0xFFFFDCE9),
    ],
    appGradientAlignments: const [
      Alignment.topLeft,
      Alignment.center,
      Alignment.bottomRight,
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
      // Crown glass, pristine polish. Warm-white light leans into the
      // angelic "halo" identity; every other term stays physical.
      glassMaterial: GlassMaterial(
        ior: 1.52,
        roughness: 0.02,
        lightColor: Color(0xFFFDECC5),
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
      // Sapphire-range IOR for a dense, sharp rim; slightly rougher than
      // optical glass for a fractured-crystal feel. Cool absorption eats
      // the warm end so transmitted light is "cold obsidian."
      glassMaterial: GlassMaterial(
        ior: 1.78,
        roughness: 0.06,
        absorption: Color.fromARGB(255, 2, 3, 4),
        lightColor: Color(0xFFA0C5E0),
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
      // Promoted from solid to glass so the name can stop lying. Surfaces
      // now transmit the emerald backdrop through an amber-absorbing
      // medium — the "honey drizzled over emeralds" rendered as real
      // optics, with embers floating above the golden-green transmission.
      mode: SurfaceMaterialMode.glass,
      blurPx: 14,
      saturatePct: 140,
      opacityScale: 0.80,
      edgeIntensity: 0.9,
      texture: ThemeTexture.grain,
      textureOpacity: 0.15,
      motion: ThemeMotion.snappy,
      luminescence: 0.1,
      particles: ThemeParticles.embers,
      parallaxStrength: 0.12,
      interaction: ThemeInteraction.caustic,
      textEffect: ThemeTextEffect.emeraldStamp,
      // Honey/amber: IOR ≈ 1.49 (real honey is 1.48–1.50). Moderate
      // roughness for viscous softness. Absorption heavy in blue and
      // moderate in green → red/yellow transmits cleanly; emerald
      // backdrop arrives as warm golden-green, the exact "honey over
      // emeralds" the name promises.
      glassMaterial: GlassMaterial(
        ior: 1.49,
        roughness: 0.08,
        absorption: Color.fromARGB(255, 0, 2, 4),
        lightColor: Color(0xFFFFD98C),
      ),
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
      // BK7 crown glass, polished. Clear — the theme's accent-tinted
      // light source gives pearl its chromatic personality.
      glassMaterial: GlassMaterial(
        ior: 1.52,
        roughness: 0.05,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.loverboy,
      'Loverboy',
      '"i love you," into a void of overflowing thoughts.',
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
      // Fused silica: lower IOR than crown, optically the purest kind of
      // glass. A whisper of red absorption casts transmitted light cool —
      // "somewhere between the last star and the first thought."
      glassMaterial: GlassMaterial(
        ior: 1.46,
        roughness: 0.03,
        absorption: Color.fromARGB(255, 1, 0, 0),
      ),
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
      // Dense flint glass: higher IOR = stronger Cauchy dispersion, so the
      // rim throws a visible prismatic fringe — the chromatic pop quanta's
      // sparkle/quantum-particle identity asks for. Clear body.
      glassMaterial: GlassMaterial(
        ior: 1.62,
        roughness: 0.04,
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
      // Now rendered through the real PBR-CRT fragment shader: aperture
      // grille + beam Gaussian + scanline darkening + barrel distortion
      // over the live backdrop. "Still warm to the touch" finally maps
      // to optics.
      mode: SurfaceMaterialMode.phosphor,
      blurPx: 0,
      saturatePct: 120,
      opacityScale: 1,
      edgeIntensity: 0.4,
      // Legacy scanlines texture stays off — the shader emits its own,
      // frequency-locked to the framebuffer grid rather than a noise
      // overlay.
      texture: ThemeTexture.none,
      textureOpacity: 0,
      motion: ThemeMotion.snappy,
      luminescence: 0.7,
      particles: ThemeParticles.none,
      parallaxStrength: 0,
      interaction: ThemeInteraction.etch,
      textEffect: ThemeTextEffect.phosphor,
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: AppFonts.mono,
        fontScale: 0.98,
        letterSpacingEm: 0.01,
      ),
      // P22 green (EIA standard phosphor). Mask pitch 3 = native
      // subpixel granularity. Mild beam spread + scanlines + small
      // barrel for faceplate curvature. Tuned to read as "old terminal"
      // not "noisy overlay."
      phosphorMaterial: PhosphorMaterial(
        tint: Color(0x4400FFAA),
        maskPitch: 3.0,
        beamSigma: 0.55,
        scanlineDepth: 0.22,
        barrelAmount: 0.06,
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
      // Warp ripple on tap — the spacetime-distortion metaphor the
      // rest of the theme is already leaning into.
      interaction: ThemeInteraction.warp,
      parallaxStrength: 0.35,
      outlineWidth: 0.6, // kirby-style hairline, directional shading
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: 'JetBrains Mono',
        letterSpacingEm: 0.01,
      ),
      // Soft-flint IOR + slightly rougher surface reads as heat-warped
      // glass. Heavy green/blue absorption transmits red only — the
      // spacetime-Doppler metaphor baked into the material.
      glassMaterial: GlassMaterial(
        ior: 1.55,
        roughness: 0.08,
        absorption: Color.fromARGB(255, 0, 2, 3),
        lightColor: Color(0xFFE06050),
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
      edgeIntensity: 1.0,
      texture: ThemeTexture.pixels,
      textureOpacity: 0.15,
      motion: ThemeMotion.snappy,
      luminescence: 0.62,
      particles: ThemeParticles.voxels,
      textEffect: ThemeTextEffect.blockify,
      interaction: ThemeInteraction.blockBreak,
      outlineWidth: 1,
      parallaxStrength: 0.3,
      // Minecraft's signature 1px offset black drop-shadow — every
      // character in the vanilla UI renders this, and without it the
      // theme reads as "a retro theme" instead of "Minecraft".
      textShadow: [
        Shadow(
          offset: Offset(1, 1),
          color: Color(0xCC000000),
        ),
      ],
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        pixelated: true,
        typography: 'VT323',
        fontScale: 1.2,
        letterSpacingEm: 0.02,
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.barbie,
      'Bibble',
      'mipitomipit. fluff, wings, and everything pink.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.solid,
      blurPx: 0,
      saturatePct: 140,
      opacityScale: 1.0,
      // strong molded-plastic rim. below 1.5 reads as painted.
      edgeIntensity: 1.8,
      texture: ThemeTexture.gloss,
      textureOpacity: 0.55,
      // plastic clicks, it doesn't float
      motion: ThemeMotion.snappy,
      luminescence: 1.35,
      particles: ThemeParticles.glitter,
      textEffect: ThemeTextEffect.shimmer,
      parallaxStrength: 0.35,
      interaction: ThemeInteraction.gloss,
      outlineWidth: 0,
      // soft pink halo so text doesn't read as flat-printed on pink bg
      textShadow: [
        Shadow(
          color: Color(0x33FF6EB4),
          offset: Offset(0, 1),
          blurRadius: 2,
        ),
      ],
      geometry: SurfaceMaterialGeometry(
        // max. every surface is a pebble.
        radius: 18,
        typography: null,
        fontScale: 1.06,
        letterSpacingEm: 0.018,
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

extension RepoTintColors on AppTokens {
  static const tintSlotCount = 5;

  Color repoTint(int slot) => switch (slot % tintSlotCount) {
        0 => hyperChromatic1,
        1 => hyperChromatic2,
        2 => stateAdded,
        3 => eventStartTone,
        _ => stateDeleted,
      };
}
