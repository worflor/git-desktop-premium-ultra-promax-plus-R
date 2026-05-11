import 'dart:ui' as ui;
import 'dart:ui' show FragmentProgram;

import 'tokens.dart';

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
  static FragmentProgram? _phosphor;
  static Future<FragmentProgram>? _phosphorFuture;
  static FragmentProgram? _petrichorFog;
  static Future<FragmentProgram>? _petrichorFogFuture;

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

  /// Loverboy background: real Conway's Game of Life. Shader samples
  /// the previous frame (bound via [setImageSampler]) to count neighbors
  /// and applies B3/S23 rules per-cell. First frame receives a blank
  /// placeholder image; the shader's early-seed branch populates the
  /// initial generation via hash.
  ///
  /// Uniforms (declaration order):
  ///   0..1  uSize          (vec2)
  ///   2     uIntensity
  ///   3     uTime
  ///   4..5  uTilt          (vec2)
  ///   6     uSnapshotTime  (seconds, when last snapshot was captured)
  /// Samplers:
  ///   0     uPrevious      (sampler2D) — previous-frame snapshot
  static FragmentProgram? loveboyBg() {
    if (_loveboyBg != null) return _loveboyBg;
    _loveboyBgFuture ??=
        FragmentProgram.fromAsset('shaders/loverboy_bg.frag').then((p) {
      _loveboyBg = p;
      return p;
    });
    return null;
  }

  /// 1×1 transparent image, cached. Used as a fallback when a shader
  /// requires a sampler2D uniform but no upstream image is available
  /// yet (first frame of a feedback loop).
  static ui.Image? _blankSamplerImage;
  static ui.Image _blankSampler() {
    if (_blankSamplerImage != null) return _blankSamplerImage!;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(
      const ui.Color(0x00000000),
      ui.BlendMode.src,
    );
    _blankSamplerImage = recorder.endRecording().toImageSync(1, 1);
    return _blankSamplerImage!;
  }

  static ui.FragmentShader? loveboyBgShader({
    required double width,
    required double height,
    double intensity = 1.0,
    double time = 0,
    double tiltX = 0,
    double tiltY = 0,
    double snapshotTime = -10.0,
    ui.Image? previous,
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
      ..setFloat(5, tiltY)
      ..setFloat(6, snapshotTime)
      ..setImageSampler(0, previous ?? _blankSampler());
    return s;
  }

  /// PBR liquid-glass program used as an `ImageFilter.shader` on
  /// `BackdropFilter`. Impeller auto-binds the live backdrop to the first
  /// sampler and the surface size into the first `vec2` uniform. Every
  /// glass theme routes through this; no per-theme specialization needed.
  static FragmentProgram? glass() {
    if (_glass != null) return _glass;
    _glassFuture ??= FragmentProgram.fromAsset('shaders/glass.frag').then((p) {
      _glass = p;
      return p;
    });
    return null;
  }

  /// Build a configured liquid-glass `FragmentShader`. The shader is a
  /// forward-synthesis model (no backdrop sampling); appearance derives
  /// from three real physical parameters plus the environment.
  ///
  /// Physical material:
  ///   [ior]         — refractive index n. Drives Schlick F0, Cauchy
  ///                   dispersion, TIR critical angle, focal length.
  ///                   Defaults to 1.52 (BK7 crown glass).
  ///   [roughness]   — GGX microfacet α. 0.02..0.1 reads as polished
  ///                   optical glass; 1.0 is fully matte. Defaults to 0.05.
  ///   [absorption]  — Beer-Lambert extinction. `.rgb` is the per-channel
  ///                   coefficient (1/px); `.a` is master strength. Pass
  ///                   transparent black for perfectly clear glass.
  ///
  /// Uniform order matches the `.frag` declaration:
  ///   0..1   uSize          (vec2)
  ///   2..5   uAbsorption    (vec4: rgb = 1/px extinction, a = strength)
  ///   6..9   uLightColor    (vec4 rgba) — light-source color (spec/rim)
  ///  10..11  uLightDir      (vec2) — direction TO the light
  ///  12..13  uTilt          (vec2) — window-delta tilt, [-1..1]
  ///  14      uTime          (seconds, monotonic)
  ///  15      uIntensity     (master output mix)
  ///  16      uCornerRadius  (SDF footprint radius, px)
  ///  17      uIOR           (refractive index n)
  ///  18      uRoughness     (GGX α)
  ///  19      uAnim          (motion master, 0..1)
  static ui.FragmentShader? glassShader({
    required double width,
    required double height,
    required ui.Color absorption,
    required ui.Color lightColor,
    double lightDirX = -0.7,
    double lightDirY = -0.7,
    double tiltX = 0,
    double tiltY = 0,
    double time = 0,
    double intensity = 1,
    double cornerRadius = 14,
    double ior = 1.52,
    double roughness = 0.05,
    double anim = 1,
  }) {
    final program = glass();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, absorption.r)
      ..setFloat(3, absorption.g)
      ..setFloat(4, absorption.b)
      ..setFloat(5, absorption.a)
      ..setFloat(6, lightColor.r)
      ..setFloat(7, lightColor.g)
      ..setFloat(8, lightColor.b)
      ..setFloat(9, lightColor.a)
      ..setFloat(10, lightDirX)
      ..setFloat(11, lightDirY)
      ..setFloat(12, tiltX)
      ..setFloat(13, tiltY)
      ..setFloat(14, time)
      ..setFloat(15, intensity)
      ..setFloat(16, cornerRadius)
      ..setFloat(17, ior)
      ..setFloat(18, roughness)
      ..setFloat(19, anim);
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

  /// CRT phosphor program used as an `ImageFilter.shader` on
  /// `BackdropFilter`. Impeller auto-binds the live backdrop so the
  /// whole scene gets barrel-warped, beam-spread, aperture-gridded, and
  /// scanline-darkened in one pass.
  static FragmentProgram? phosphor() {
    if (_phosphor != null) return _phosphor;
    _phosphorFuture ??=
        FragmentProgram.fromAsset('shaders/phosphor.frag').then((p) {
      _phosphor = p;
      return p;
    });
    return null;
  }

  /// Uniform layout (declaration order):
  ///   0..1   uSize          (vec2) — auto-set by ImageFilter.shader
  ///   2      uIntensity
  ///   3      uTime
  ///   4..7   uPhosphorTint  (vec4 rgba)
  ///   8      uMaskPitch     (px per RGB triplet)
  ///   9      uBeamSigma     (horizontal Gaussian spread, px)
  ///  10      uScanlineDepth (0..1)
  ///  11      uBarrelAmount  (0..0.2 — faceplate curvature)
  /// Samplers:
  ///   0      uBackdrop      — auto-bound live scene
  static ui.FragmentShader? phosphorShader({
    required double width,
    required double height,
    double intensity = 1.0,
    double time = 0,
    ui.Color tint = const ui.Color(0x5500FF88), // P22 green default
    double maskPitch = 3.0,
    double beamSigma = 0.55,
    double scanlineDepth = 0.18,
    double barrelAmount = 0.09,
  }) {
    final program = phosphor();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, intensity)
      ..setFloat(3, time)
      ..setFloat(4, tint.r)
      ..setFloat(5, tint.g)
      ..setFloat(6, tint.b)
      ..setFloat(7, tint.a)
      ..setFloat(8, maskPitch)
      ..setFloat(9, beamSigma)
      ..setFloat(10, scanlineDepth)
      ..setFloat(11, barrelAmount);
    return s;
  }

  static FragmentProgram? petrichorFog() {
    if (_petrichorFog != null) return _petrichorFog;
    _petrichorFogFuture ??=
        FragmentProgram.fromAsset('shaders/petrichor_fog.frag').then((p) {
      _petrichorFog = p;
      return p;
    });
    return null;
  }

  static ui.FragmentShader? petrichorFogShader({
    required double width,
    required double height,
    double time = 0,
    double tiltX = 0,
    double tiltY = 0,
    double intensity = 0.06,
    double sessionAge = 0,
  }) {
    final program = petrichorFog();
    if (program == null) return null;
    final s = program.fragmentShader();
    s
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, time)
      ..setFloat(3, tiltX)
      ..setFloat(4, tiltY)
      ..setFloat(5, intensity)
      ..setFloat(6, sessionAge);
    return s;
  }

  static void warmFor(AppThemeId id) {
    glass();
    switch (id) {
      case AppThemeId.kirby:
        cellshade();
      case AppThemeId.nacre:
        iridescent();
      case AppThemeId.loverboy:
        darkIridescent();
        loveboyBg();
      case AppThemeId.barbie:
        plastic();
      case AppThemeId.phosphor:
        phosphor();
      case AppThemeId.petrichor:
        petrichorFog();
      default:
        break;
    }
  }
}
