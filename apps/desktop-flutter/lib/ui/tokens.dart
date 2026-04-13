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
  aether,
  quanta,
  redshift,
  blackboard,
  crafty,
}

enum SurfaceMaterialMode { solid, glass }

enum ThemeTexture { none, grain, scanlines, pixels }

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
}

enum ThemeInteraction { none, vibration, caustic, etch, warp, chalk }

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
      0xFFEBDFCC,
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
      0xFF4D453B,
      0xFF322B24,
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
      0xFF00FFAA,
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
      0xFF2F2519,
      0xFF4E7F5E,
      0xFFCD7F2D,
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
      0xFFFFFFFF,
      0xFF00E0FF,
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
      0xFFFF0044,
      0xFF3D2A2E,
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
      0x0DFFFFFF,
      0x17FFFFFF,
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
      0xFFFFFFFF,
      0xFFFFFFFF,
      0xFFFFFFFF,
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
      'Angelic white gold with ethereal clouds and divine radiance.',
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
      'Abyssal obsidian brutalism. The silent, technical shadow of the Halo.',
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
      'Misty cool light mode tuned for daytime readability.',
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
      'Warm daylight surfaces with soft amber chrome.',
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
      AppThemeId.aether,
      'Aether',
      'Crisp cosmic glass with cool contrast for long review sessions.',
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
      'Rich emerald obsidian with crystalline subatomic clarity and high-refraction glass.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 16,
      saturatePct: 142,
      opacityScale: 0.65,
      edgeIntensity: 0.8,
      texture: ThemeTexture.scanlines,
      textureOpacity: 0.06,
      motion: ThemeMotion.fluid,
      luminescence: 0.5,
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
      AppThemeId.redshift,
      'Redshift',
      'CRT glass on a ship that never stops, where things ahead sharpen into strangers and things behind soften into goodbyes.',
    ),
    SurfaceMaterialShader(
      mode: SurfaceMaterialMode.glass,
      blurPx: 24,
      saturatePct: 150,
      opacityScale: 0.9,
      edgeIntensity: 0.8,
      texture: ThemeTexture.scanlines,
      textureOpacity: 0.08,
      motion: ThemeMotion.fluid,
      luminescence: 0.45,
      particles: ThemeParticles.whisps,
      textEffect: ThemeTextEffect.burn,
      parallaxStrength: 0.35,
      geometry: SurfaceMaterialGeometry(
        radius: 0,
        typography: 'JetBrains Mono',
      ),
    ),
  ),
  AppThemeDefinition(
    ThemeOption(
      AppThemeId.blackboard,
      'Blackboard',
      'Raw slate geometry with physical chalk typographical rendering.',
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
      'Sharp 8-bit geometry with nostalgic block architecture and pixel-perfect surfaces.',
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
