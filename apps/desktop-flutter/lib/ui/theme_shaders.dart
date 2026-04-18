import 'dart:ui' as ui;
import 'dart:ui' show FragmentProgram;

/// Cached `FragmentProgram` loader. Each shader asset compiles ONCE on
/// first access and the resulting program is reused across every paint
/// call for the lifetime of the app. Per-paint cost is just creating a
/// fresh `FragmentShader` from the program (cheap — it's a uniform-state
/// container, no compilation) and setting uniforms.
class ThemeShaders {
  ThemeShaders._();

  static FragmentProgram? _cellshade;
  static Future<FragmentProgram>? _cellshadeFuture;
  static FragmentProgram? _iridescent;
  static Future<FragmentProgram>? _iridescentFuture;
  static FragmentProgram? _darkIridescent;
  static Future<FragmentProgram>? _darkIridescentFuture;
  static FragmentProgram? _loveboyBg;
  static Future<FragmentProgram>? _loveboyBgFuture;
  static FragmentProgram? _glass;
  static Future<FragmentProgram>? _glassFuture;
  static FragmentProgram? _plastic;
  static Future<FragmentProgram>? _plasticFuture;

  /// Kicks off loading the kirby fragment program if it hasn't
  /// been loaded yet. Safe to call repeatedly — only the first call
  /// triggers asset I/O. Returns `null` synchronously until the program
  /// is ready; subsequent paints will pick it up once loaded.
  static FragmentProgram? cellshade() {
    if (_cellshade != null) return _cellshade;
    _cellshadeFuture ??= FragmentProgram.fromAsset('shaders/cellshade.frag')
        .then((p) {
      _cellshade = p;
      return p;
    });
    return null;
  }

  /// Build a configured `FragmentShader` for kirby surface
  /// rendering. Uniforms are positional in the order declared in the
  /// `.frag` file:
  ///   0  uSize.x
  ///   1  uSize.y
  ///   2  uMode (0 = halftone, 1 = hatch)
  ///   3  uDotSize
  ///   4  uIntensity
  ///   5..8  uInkColor (rgba)
  ///   9..12 uPaperColor (rgba)
  ///  13  uOutline
  ///  14  uHatchAngle
  static ui.FragmentShader? cellshadeShader({
    required double width,
    required double height,
    required double mode,
    required double dotSize,
    required double intensity,
    required ui.Color ink,
    required ui.Color paper,
    double outline = 0,
    double hatchAngle = 0.785398,
  }) {
    final program = cellshade();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, mode)
      ..setFloat(3, dotSize)
      ..setFloat(4, intensity)
      ..setFloat(5, ink.r)
      ..setFloat(6, ink.g)
      ..setFloat(7, ink.b)
      ..setFloat(8, ink.a)
      ..setFloat(9, paper.r)
      ..setFloat(10, paper.g)
      ..setFloat(11, paper.b)
      ..setFloat(12, paper.a)
      ..setFloat(13, outline)
      ..setFloat(14, hatchAngle);
    return s;
  }

  /// Mother-of-pearl shimmer program. Used by Nacre as the backdrop
  /// texture; outputs a position-derived hue spectrum mixed with a
  /// pearl base color.
  static FragmentProgram? iridescent() {
    if (_iridescent != null) return _iridescent;
    _iridescentFuture ??=
        FragmentProgram.fromAsset('shaders/iridescent.frag').then((p) {
      _iridescent = p;
      return p;
    });
    return null;
  }

  /// Build a configured `FragmentShader` for iridescent surface paints.
  /// Uniform order matches the `.frag` declaration sequence:
  ///   0..1   uSize       (vec2)
  ///   2      uIntensity
  ///   3      uHueOffset  (legacy static rotation)
  ///   4..7   uPearlBase  (vec4 rgba)
  ///   8..9   uTilt       (vec2) — window-delta parallax, [-1..1]
  ///  10      uTime       (seconds, monotonic)
  static ui.FragmentShader? iridescentShader({
    required double width,
    required double height,
    required double intensity,
    required ui.Color pearlBase,
    double hueOffset = 0,
    double tiltX = 0,
    double tiltY = 0,
    double time = 0,
  }) {
    final program = iridescent();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, intensity)
      ..setFloat(3, hueOffset)
      ..setFloat(4, pearlBase.r)
      ..setFloat(5, pearlBase.g)
      ..setFloat(6, pearlBase.b)
      ..setFloat(7, pearlBase.a)
      ..setFloat(8, tiltX)
      ..setFloat(9, tiltY)
      ..setFloat(10, time);
    return s;
  }

  /// Loverboy dark rose iridescence program. Same uniform layout as
  /// [iridescent] — hue cycle compressed to pink–lavender–violet band,
  /// saturation raised, spec crest tinted pink. Separate program cache
  /// so both can be live simultaneously without evicting each other.
  static FragmentProgram? darkIridescent() {
    if (_darkIridescent != null) return _darkIridescent;
    _darkIridescentFuture ??=
        FragmentProgram.fromAsset('shaders/dark_iridescent.frag').then((p) {
      _darkIridescent = p;
      return p;
    });
    return null;
  }

  /// Build a configured `FragmentShader` for dark iridescent surfaces.
  /// Uniform order is identical to [iridescentShader] — the `.frag`
  /// files share the same declaration sequence.
  static ui.FragmentShader? darkIridescentShader({
    required double width,
    required double height,
    required double intensity,
    required ui.Color pearlBase,
    double hueOffset = 0,
    double tiltX = 0,
    double tiltY = 0,
    double time = 0,
  }) {
    final program = darkIridescent();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, intensity)
      ..setFloat(3, hueOffset)
      ..setFloat(4, pearlBase.r)
      ..setFloat(5, pearlBase.g)
      ..setFloat(6, pearlBase.b)
      ..setFloat(7, pearlBase.a)
      ..setFloat(8, tiltX)
      ..setFloat(9, tiltY)
      ..setFloat(10, time);
    return s;
  }

  /// Loverboy background: GoL-inspired fractal cellular field.
  /// Uniforms: 0..1 uSize, 2 uIntensity, 3 uTime, 4..5 uTilt
  static FragmentProgram? loveboyBg() {
    if (_loveboyBg != null) return _loveboyBg;
    _loveboyBgFuture ??=
        FragmentProgram.fromAsset('shaders/loverboy_bg.frag').then((p) {
      _loveboyBg = p;
      return p;
    });
    return null;
  }

  static ui.FragmentShader? loveboyBgShader({
    required double width,
    required double height,
    double intensity = 1.0,
    double time = 0,
    double tiltX = 0,
    double tiltY = 0,
  }) {
    final program = loveboyBg();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, intensity)
      ..setFloat(3, time)
      ..setFloat(4, tiltX)
      ..setFloat(5, tiltY);
    return s;
  }

  /// Real-time glass program: fresnel rim + specular streak +
  /// chromatic edge fringe. Used by Nacre per-surface; existing
  /// cosmic-glass themes keep the legacy `_SurfaceGlazePainter`.
  static FragmentProgram? glass() {
    if (_glass != null) return _glass;
    _glassFuture ??= FragmentProgram.fromAsset('shaders/glass.frag').then((p) {
      _glass = p;
      return p;
    });
    return null;
  }

  /// Build a configured liquid-glass `FragmentShader`. Uniform order
  /// matches the `.frag` declaration sequence:
  ///   0..1   uSize          (vec2)
  ///   2..5   uTint          (vec4 rgba)
  ///   6..9   uHighlight     (vec4 rgba) — primary warm rim/spec color
  ///  10..13  uHighlightCool (vec4 rgba) — dichroic cool wash
  ///  14..15  uLightDir      (vec2)
  ///  16..17  uTilt          (vec2) — window-delta tilt, [-1..1]
  ///  18      uTime          (seconds, monotonic)
  ///  19      uIntensity     (master strength)
  ///  20      uFresnelPx     (rim falloff distance)
  ///  21      uChromatic     (chromatic offset px)
  ///  22      uSpecSharp     (spec exponent — higher = crispier)
  ///  23      uSpecCore      (hot-core exponent multiplier)
  ///  24      uThickness     (center darken amount)
  ///  25      uCornerRadius  (rim SDF corner radius — gloopy meniscus)
  ///  26      uNoise         (rim micro-grain)
  ///  27      uAnim          (multiplier on time + tilt motion)
  static ui.FragmentShader? glassShader({
    required double width,
    required double height,
    required ui.Color tint,
    required ui.Color highlight,
    ui.Color? highlightCool,
    double lightDirX = -0.7,
    double lightDirY = -0.7,
    double tiltX = 0,
    double tiltY = 0,
    double time = 0,
    double intensity = 1,
    double fresnelPx = 22,
    double chromatic = 1.4,
    double specSharp = 8,
    double specCore = 3.5,
    double thickness = 0.6,
    double cornerRadius = 14,
    double noise = 0.6,
    double anim = 1,
  }) {
    final program = glass();
    if (program == null) return null;
    final cool = highlightCool ?? highlight;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, tint.r)
      ..setFloat(3, tint.g)
      ..setFloat(4, tint.b)
      ..setFloat(5, tint.a)
      ..setFloat(6, highlight.r)
      ..setFloat(7, highlight.g)
      ..setFloat(8, highlight.b)
      ..setFloat(9, highlight.a)
      ..setFloat(10, cool.r)
      ..setFloat(11, cool.g)
      ..setFloat(12, cool.b)
      ..setFloat(13, cool.a)
      ..setFloat(14, lightDirX)
      ..setFloat(15, lightDirY)
      ..setFloat(16, tiltX)
      ..setFloat(17, tiltY)
      ..setFloat(18, time)
      ..setFloat(19, intensity)
      ..setFloat(20, fresnelPx)
      ..setFloat(21, chromatic)
      ..setFloat(22, specSharp)
      ..setFloat(23, specCore)
      ..setFloat(24, thickness)
      ..setFloat(25, cornerRadius)
      ..setFloat(26, noise)
      ..setFloat(27, anim);
    return s;
  }

  /// Plastic-gloss program for Bibble. Mono-hue surface with a moving
  /// specular band, bottom-right inner shadow, and magenta fresnel
  /// rim. Distinct from [iridescent] (hue cycles) and [glass]
  /// (transmissive).
  static FragmentProgram? plastic() {
    if (_plastic != null) return _plastic;
    _plasticFuture ??=
        FragmentProgram.fromAsset('shaders/plastic.frag').then((p) {
      _plastic = p;
      return p;
    });
    return null;
  }

  /// Build a configured `FragmentShader` for plastic-gloss surfaces.
  /// Uniform order matches the `.frag` declaration sequence:
  ///   0..1   uSize       (vec2)
  ///   2      uIntensity
  ///   3..6   uBase       (vec4 rgba) — surface base
  ///   7..10  uHighlight  (vec4 rgba) — specular + rim (magenta)
  ///  11..14  uShadow     (vec4 rgba) — bottom-right inner shadow
  ///  15..16  uTilt       (vec2) — window-delta tilt [-1..1]
  ///  17      uTime       (seconds, monotonic)
  ///  18      uEdgePx     (rim falloff in px)
  static ui.FragmentShader? plasticShader({
    required double width,
    required double height,
    required double intensity,
    required ui.Color base,
    required ui.Color highlight,
    required ui.Color shadow,
    double tiltX = 0,
    double tiltY = 0,
    double time = 0,
    double edgePx = 18,
  }) {
    final program = plastic();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, intensity)
      ..setFloat(3, base.r)
      ..setFloat(4, base.g)
      ..setFloat(5, base.b)
      ..setFloat(6, base.a)
      ..setFloat(7, highlight.r)
      ..setFloat(8, highlight.g)
      ..setFloat(9, highlight.b)
      ..setFloat(10, highlight.a)
      ..setFloat(11, shadow.r)
      ..setFloat(12, shadow.g)
      ..setFloat(13, shadow.b)
      ..setFloat(14, shadow.a)
      ..setFloat(15, tiltX)
      ..setFloat(16, tiltY)
      ..setFloat(17, time)
      ..setFloat(18, edgePx);
    return s;
  }
}
