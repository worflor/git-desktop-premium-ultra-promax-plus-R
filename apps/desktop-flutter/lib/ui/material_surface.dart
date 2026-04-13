import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'liquid_glass.dart';
import 'theme_shaders.dart';
import 'tokens.dart';

enum AppMaterialTone {
  surface0,
  surface1,
  surface2,
  panel,
  panelStrong,
  input,
  diff,
  danger,
}

/// Derived per-theme surface tones. Lets feature code ask "what's the right
/// tone for the topbar/rail/panel chrome?" without branching on `t.id`.
/// Single source of truth for any per-theme UI quirk.
extension AppTokenSurfaceTones on AppTokens {
  /// Tone used for chrome that sits inside the window frame (topbar,
  /// sidebar rail, floating command palette). Most themes use `surface0`
  /// (lightest translucent layer); Redshift uses `surface1` so its
  /// red-leaning chrome reads as an inset rather than bleeding out of the
  /// gradient underneath.
  AppMaterialTone get chromeTone => id == AppThemeId.redshift
      ? AppMaterialTone.surface1
      : AppMaterialTone.surface0;

  /// Tone for panels that float one depth below the chrome (command
  /// palettes, floating popovers). Steps one tone deeper than [chromeTone]
  /// so the panel reads as elevated above chrome, not flush with it.
  AppMaterialTone get innerPanelTone => id == AppThemeId.redshift
      ? AppMaterialTone.surface2
      : AppMaterialTone.surface1;

  /// Aether & Quanta darken their glass fills slightly so the backdrop
  /// blur reads as a pane, not a wash. Other glass themes (halo, redshift)
  /// keep the declared alpha. Returns 1.0 = no damping.
  bool get glassNeedsOpacityDamping =>
      id == AppThemeId.aether || id == AppThemeId.quanta;

  /// Crafty paints hard stamped drop-shadows (minecraft-block aesthetic)
  /// instead of the soft elevated glow every other theme uses. Opt-in flag
  /// so shadow logic stays declarative.
  bool get usesStampedShadow => id == AppThemeId.crafty;

  /// Design-system border scale. Three tiers let feature code pick by
  /// intent (hairline vs. subtle vs. emphasized) instead of rolling
  /// bespoke alphas. Tuned against the 40+ scattered chromeBorder.withValues
  /// sites that drifted across 0.05–0.30.
  ///
  /// faint (0.08)  — inner grid lines, near-invisible dividers
  /// subtle (0.14) — standard card chrome, default choice
  /// strong (0.28) — accent dividers, emphasis
  Color get chromeBorderFaint => chromeBorder.withValues(alpha: 0.08);
  Color get chromeBorderSubtle => chromeBorder.withValues(alpha: 0.14);
  Color get chromeBorderStrong => chromeBorder.withValues(alpha: 0.28);
}

class SurfaceMaterialRuntime {
  final ImageFilter? filter;
  final double alphaScale;
  final double ambientWeight;
  final Color cellShadow;
  final Color rimLight;
  final Color glowColor;
  // Precomputed glaze colors — cached per (theme, shader, dpr) via
  // MaterialRuntimeCache so the painter doesn't redo the withValues math
  // on every paint call.
  final Color glazeTopTint;
  final Color glazeMidTint;

  const SurfaceMaterialRuntime({
    required this.filter,
    required this.alphaScale,
    required this.ambientWeight,
    required this.cellShadow,
    required this.rimLight,
    required this.glowColor,
    required this.glazeTopTint,
    required this.glazeMidTint,
  });
}

class MaterialSurface extends StatelessWidget {
  final Widget child;
  final AppMaterialTone tone;
  final double? width;
  final double? height;
  final double? radius;
  final Color? borderColor;
  final BoxBorder? border;
  final double borderAlpha;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final bool elevated;
  final bool texture;
  final bool innerHighlight;
  final bool hardShadow;
  final bool glaze;
  final Clip clipBehavior;

  const MaterialSurface({
    super.key,
    required this.child,
    this.tone = AppMaterialTone.surface1,
    this.width,
    this.height,
    this.radius,
    this.borderColor,
    this.border,
    this.borderAlpha = 0.18,
    this.padding,
    this.constraints,
    this.elevated = true,
    this.texture = false,
    this.innerHighlight = false,
    this.hardShadow = false,
    this.glaze = false,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final runtime = MaterialRuntimeCache.of(t, shader);
    final resolvedRadius =
        radius ?? shader.geometry.radius.clamp(0, 18).toDouble();
    final fill = _resolvedFill(t, shader, runtime);
    final border = borderColor ?? t.chromeBorder;
    // Kirby (and any future ink-line theme) opts into a thick
    // opaque border via shader.outlineWidth. Real cell-shading reads
    // as DIRECTIONAL — like a fixed light source from the top-left —
    // so the border is asymmetric: bright accent rim on top + left
    // (catches the imaginary key light), heavier ink line on bottom +
    // right (the shadow side).
    final inkOutline = shader.outlineWidth > 0;
    final BoxBorder? resolvedBorder;
    if (this.border != null) {
      resolvedBorder = this.border;
    } else if (inkOutline) {
      // Variable line weight — the #1 thing that separates a real
      // comic-book ink line from a CAD stroke. Top+left are the
      // lightest (rim of the form catching key light), right is
      // heavier (shadow side), bottom is heaviest (the line carries
      // the form's weight, settles into the page). This 1:1.4:2 ratio
      // is roughly what you'd see in a Coipel or Maleev panel.
      final w = shader.outlineWidth;
      final rimColor = t.accentBright;
      resolvedBorder = Border(
        top: BorderSide(color: rimColor, width: w * 0.5),
        left: BorderSide(color: rimColor, width: w * 0.5),
        right: BorderSide(color: border, width: w * 1.2),
        bottom: BorderSide(color: border, width: w * 1.5),
      );
    } else {
      resolvedBorder =
          Border.all(color: border.withValues(alpha: borderAlpha));
    }
    Widget content = SizedBox(
      width: width,
      height: height,
      child: ConstrainedBox(
        constraints: constraints ?? const BoxConstraints(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(resolvedRadius),
            border: resolvedBorder,
            boxShadow:
                _materialShadows(t, shader, runtime, elevated, hardShadow),
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (texture && shader.texture != ThemeTexture.none)
                Positioned.fill(
                  child: IgnorePointer(
                    child: MaterialTextureLayer(tokens: t, shader: shader),
                  ),
                ),
              if (_showsStructuralGlaze(t, shader))
                Positioned.fill(
                  child: IgnorePointer(
                    child: _GlazeLayer(
                      tokens: t,
                      runtime: runtime,
                      radius: resolvedRadius,
                      isGlass: shader.mode == SurfaceMaterialMode.glass,
                    ),
                  ),
                ),
              if (innerHighlight)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(resolvedRadius),
                        border: Border(
                          top: BorderSide(
                            color: runtime.rimLight.withValues(
                              alpha: shader.mode == SurfaceMaterialMode.glass
                                  ? 0.16
                                  : 0.11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (padding == null)
                child
              else
                Padding(padding: padding!, child: child),
            ],
          ),
        ),
      ),
    );

    content = ClipRRect(
      borderRadius: BorderRadius.circular(resolvedRadius),
      clipBehavior: clipBehavior,
      child: content,
    );

    if (runtime.filter == null) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(resolvedRadius),
      clipBehavior: clipBehavior,
      child: BackdropFilter(filter: runtime.filter!, child: content),
    );
  }

  Color _baseColor(AppTokens t) {
    switch (tone) {
      case AppMaterialTone.surface0:
        return t.surface0;
      case AppMaterialTone.surface1:
        return t.surface1;
      case AppMaterialTone.surface2:
        return t.surface2;
      case AppMaterialTone.panel:
        return t.panelOverlay;
      case AppMaterialTone.panelStrong:
        return t.panelOverlayStrong;
      case AppMaterialTone.input:
        return t.inputOverlay;
      case AppMaterialTone.diff:
        return t.diffOverlay;
      case AppMaterialTone.danger:
        return t.dangerOverlay;
    }
  }

  Color _resolvedFill(
    AppTokens t,
    SurfaceMaterialShader shader,
    SurfaceMaterialRuntime runtime,
  ) {
    final base = _usesRuntimeOverlay
        ? _runtimeOverlay(t, shader, runtime, _baseColor(t))
        : _baseColor(t);
    if (shader.mode != SurfaceMaterialMode.glass) {
      return base;
    }

    if (t.glassNeedsOpacityDamping) {
      final alpha = _alphaOf(base);
      final factor = switch (tone) {
        AppMaterialTone.surface0 => 0.88,
        AppMaterialTone.surface1 => 0.9,
        AppMaterialTone.surface2 => 0.93,
        AppMaterialTone.panel => 0.94,
        AppMaterialTone.panelStrong => 0.96,
        AppMaterialTone.input => 0.92,
        AppMaterialTone.diff => 0.92,
        AppMaterialTone.danger => 0.94,
      };
      return base.withValues(alpha: (alpha * factor).clamp(0.0, 0.985));
    }

    return base;
  }

  bool _showsStructuralGlaze(AppTokens t, SurfaceMaterialShader shader) {
    if (!glaze) return false;
    if (shader.mode != SurfaceMaterialMode.glass) return false;
    return t.id != AppThemeId.nightwalker;
  }


  bool get _usesRuntimeOverlay {
    switch (tone) {
      case AppMaterialTone.surface0:
      case AppMaterialTone.surface1:
      case AppMaterialTone.surface2:
        return false;
      case AppMaterialTone.panel:
      case AppMaterialTone.panelStrong:
      case AppMaterialTone.input:
      case AppMaterialTone.diff:
      case AppMaterialTone.danger:
        return true;
    }
  }
}

class MaterialRuntimeCache {
  // Two-level identity-keyed cache. Was a single Map<String,_> with a
  // per-call key built via string-interpolation +
  // `dpr.toStringAsFixed(2)` — that ran on every `MaterialSurface.build`,
  // which is every visible surface every rebuild. Now: per-theme map,
  // identity-compared shader → no allocation in the hot path.
  static final Map<AppThemeId,
          Map<SurfaceMaterialShader, SurfaceMaterialRuntime>>
      _cache = {};

  static SurfaceMaterialRuntime of(
      AppTokens tokens, SurfaceMaterialShader shader) {
    final perTheme = _cache.putIfAbsent(tokens.id, () => {});
    final cached = perTheme[shader];
    if (cached != null) return cached;
    final dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
    final r = _compute(tokens, shader, dpr);
    perTheme[shader] = r;
    return r;
  }

  static SurfaceMaterialRuntime _compute(
    AppTokens tokens,
    SurfaceMaterialShader shader,
    double devicePixelRatio,
  ) {
    final dpr = devicePixelRatio.clamp(1.0, 2.5);
    final glass = shader.mode == SurfaceMaterialMode.glass ? 1.0 : 0.0;
    final blur = math.sqrt(dpr) * shader.blurPx * glass;
    final clampedBlur = blur.clamp(0.0, 24.0);
    final edgeGain = (1 + shader.edgeIntensity * 0.22 * glass).clamp(1.0, 1.26);
    final alphaScale =
        ((shader.opacityScale / edgeGain) * (glass > 0 ? 1.0 : 1.12))
            .clamp(0.68, 1.55);
    final ambientWeight =
        ((shader.edgeIntensity * 40 * glass).round().clamp(0, 256)) / 256.0;
    final ambient = tokens.themeAmbient;
    final glow = ambient ?? Colors.white;
    final glowColor =
        glow.withValues(alpha: (0.2 * shader.luminescence).clamp(0.0, 0.8));
    final glazeStrength = switch (tokens.id) {
      AppThemeId.aether => 0.16,
      AppThemeId.quanta => 0.18,
      AppThemeId.redshift => 0.12,
      AppThemeId.halo => 0.18,
      _ => 0.1,
    };
    return SurfaceMaterialRuntime(
      filter: glass < 0.5 || clampedBlur < 0.25
          ? null
          : ImageFilter.blur(sigmaX: clampedBlur, sigmaY: clampedBlur),
      alphaScale: alphaScale,
      ambientWeight: ambientWeight,
      cellShadow: ambient == null
          ? const Color(0x80000000)
          : Color.lerp(Colors.black, ambient, 0.5)!.withValues(alpha: 0.45),
      rimLight: glow.withValues(alpha: (alphaScale * 0.35).clamp(0.05, 0.8)),
      glowColor: glowColor,
      glazeTopTint: Colors.white.withValues(alpha: glazeStrength * 0.28),
      glazeMidTint: glowColor.withValues(alpha: glazeStrength * 0.32),
    );
  }
}

Color _runtimeOverlay(
  AppTokens tokens,
  SurfaceMaterialShader shader,
  SurfaceMaterialRuntime runtime,
  Color base,
) {
  final ambient = tokens.themeAmbient;
  final mixed = ambient == null || runtime.ambientWeight <= 0
      ? base
      : Color.lerp(base.withAlpha(255), ambient, runtime.ambientWeight)!;
  final alpha =
      ((_alphaOf(base) * runtime.alphaScale).clamp(0, 0.985) * 255).round();
  return mixed.withAlpha(alpha);
}

double _alphaOf(Color color) => ((color.toARGB32() >> 24) & 0xff) / 255.0;

List<BoxShadow> _materialShadows(
  AppTokens t,
  SurfaceMaterialShader shader,
  SurfaceMaterialRuntime runtime,
  bool elevated,
  bool hardShadow,
) {
  // Kirby: comic-book "popped-off-page" hard shadow, no blur,
  // offset down-right. Color sourced from chromeBorder so the shadow
  // and the panel-border ink line stay matched if the theme palette
  // is ever retuned.
  if (shader.outlineWidth > 0) {
    if (!elevated) return const [];
    return [
      BoxShadow(
        color: t.chromeBorder,
        offset: const Offset(3, 3),
        blurRadius: 0,
      ),
    ];
  }
  if (t.usesStampedShadow) {
    final shadows = <BoxShadow>[];
    if (elevated) {
      shadows.add(
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.75),
          offset: const Offset(4, 4),
        ),
      );
    }
    if (hardShadow) {
      shadows.add(
          BoxShadow(color: runtime.rimLight, offset: const Offset(-1, -1)));
    }
    return shadows;
  }
  final shadows = <BoxShadow>[];
  if (hardShadow) {
    shadows.add(
      BoxShadow(
        color: runtime.cellShadow.withValues(
          alpha: shader.mode == SurfaceMaterialMode.glass ? 0.34 : 0.2,
        ),
        blurRadius: 0,
        offset: const Offset(2, 2),
      ),
    );
  }
  if (!elevated) {
    return shadows;
  }
  shadows.insert(
    0,
    BoxShadow(
      color: t.shadowElev,
      blurRadius: shader.mode == SurfaceMaterialMode.glass ? 20.0 : 12.0,
      offset: Offset(0, shader.mode == SurfaceMaterialMode.glass ? 12 : 6),
    ),
  );
  // Glass-only chromatic edge fringe: a hair of the theme's ambient color
  // bled into the rim, so light reads as refracted at the edge instead of
  // stopped dead. One extra shadow, no new allocations — ambient is already
  // a stored token.
  if (shader.mode == SurfaceMaterialMode.glass) {
    final ambient = t.themeAmbient ?? t.chromeAccent;
    shadows.add(
      BoxShadow(
        color: ambient.withValues(alpha: 0.12),
        blurRadius: 1,
        spreadRadius: -0.5,
      ),
    );
  }
  return shadows;
}

class MaterialTexturePainter extends CustomPainter {
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final BlendMode blendMode;
  final double opacityScale;
  /// Live state from `LiquidGlassProvider`. Only consumed by the
  /// `iridescent` texture path — drives the shader's time-drift and
  /// window-tilt parallax. Other texture types ignore it and the
  /// painter's `shouldRepaint` doesn't trigger on pulse changes for
  /// them, so they pay nothing.
  final LiquidGlassPulse pulse;

  const MaterialTexturePainter({
    required this.tokens,
    required this.shader,
    this.blendMode = BlendMode.overlay,
    this.opacityScale = 1,
    this.pulse = LiquidGlassPulse.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final intensity = (shader.textureOpacity * opacityScale).clamp(0.0, 1.0);
    if (intensity == 0 || shader.texture == ThemeTexture.none) return;
    final ambient = tokens.themeAmbient ?? tokens.chromeAccent;
    final paint = Paint()
      ..blendMode = blendMode
      ..style = PaintingStyle.fill;

    switch (shader.texture) {
      case ThemeTexture.grain:
        final count = (size.width * size.height / 1600).clamp(24, 280).round();
        // Per-surface seed so adjacent panels don't stamp identical noise
        // fields; stable across paints for the same size, so no flicker.
        final seed = size.width.toInt() * 37 + size.height.toInt() * 17;
        paint.color = ambient.withValues(alpha: intensity * 0.55);
        for (var i = 0; i < count; i++) {
          final x = (((i * 127) + seed) % 1000) / 1000 * size.width;
          final y = (((i * 313) + seed * 3) % 1000) / 1000 * size.height;
          canvas.drawCircle(Offset(x, y), 0.35 + (i % 4) * 0.16, paint);
        }
      case ThemeTexture.scanlines:
        // Scanline color: theme's ambient hue on dark themes (the
        // phosphor-coating-glows-between-rows effect), or pure black
        // on light themes (the standard darker-stripe-between-pixels
        // effect). Both produce visible contrast against the bg
        // — the old hardcoded black was invisible on dark themes
        // because dark-on-dark has no contrast.
        final scanColor = tokens.isDark
            ? (tokens.themeAmbient ?? tokens.textNormal)
            : Colors.black;
        paint.color = scanColor.withValues(alpha: intensity);
        for (var y = 0.0; y < size.height; y += 4) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
        }
      case ThemeTexture.pixels:
        // Precompute the two possible cell colors ONCE — the inner
        // nested loop previously allocated a new Color per drawn cell
        // via `.withValues()`, for up to ~180 cells on a typical panel.
        final dark = Color.lerp(tokens.bg0, Colors.black, 0.22)!;
        final cellAlpha = (intensity * 0.65).clamp(0.0, 1.0);
        final ambientCell = ambient.withValues(alpha: cellAlpha);
        final darkCell = dark.withValues(alpha: cellAlpha);
        for (var x = 0.0; x < size.width; x += 16) {
          for (var y = 0.0; y < size.height; y += 16) {
            final seed = (x ~/ 16) * 31 + (y ~/ 16) * 17;
            if (seed % 5 == 0 || seed % 11 == 0) {
              paint.color = seed.isEven ? ambientCell : darkCell;
              canvas.drawRect(Rect.fromLTWH(x, y, 4, 4), paint);
            }
          }
        }
      case ThemeTexture.halftone:
        // GPU shader pass: one drawRect with the cellshade fragment
        // program. Far cheaper than the per-cell software loops above
        // — it's a couple of dozen ALU ops per pixel running on the
        // GPU. Falls through to a flat ink overlay until the shader
        // asset finishes loading on first frame.
        final fragShader = ThemeShaders.cellshadeShader(
          width: size.width,
          height: size.height,
          mode: 0, // halftone
          dotSize: 6,
          intensity: intensity,
          ink: tokens.textStrong,
          paper: const Color(0x00000000), // transparent — paper bleeds through
          outline: 0, // surface borders carry the ink line, not this layer
        );
        if (fragShader != null) {
          canvas.drawRect(
            Offset.zero & size,
            Paint()..shader = fragShader,
          );
        }
      case ThemeTexture.iridescent:
        // GPU shader pass: position-derived hue spectrum + time-drift +
        // window-tilt parallax. Drawn srcOver (not overlay) at a
        // controlled alpha so the shimmer reads as the surface's own
        // optical character. The pulse sourcing comes from
        // `LiquidGlassProvider` — when the user drags the window, the
        // tilt vector slides the iridescent gradient like real
        // mother-of-pearl catching a different angle of light.
        final fragShader = ThemeShaders.iridescentShader(
          width: size.width,
          height: size.height,
          intensity: intensity,
          pearlBase: tokens.bg0.withValues(alpha: 1 - intensity * 0.65),
          tiltX: pulse.tilt.dx,
          tiltY: pulse.tilt.dy,
          time: pulse.time,
        );
        if (fragShader != null) {
          canvas.drawRect(
            Offset.zero & size,
            Paint()
              ..shader = fragShader
              ..blendMode = BlendMode.srcOver,
          );
        }
      case ThemeTexture.none:
        break;
    }
  }

  @override
  bool shouldRepaint(MaterialTexturePainter oldDelegate) =>
      oldDelegate.tokens != tokens ||
      oldDelegate.shader != shader ||
      oldDelegate.blendMode != blendMode ||
      oldDelegate.opacityScale != opacityScale ||
      // Pulse drives the iridescent shader's drift + parallax. For
      // non-iridescent textures the wrapper widget doesn't subscribe
      // to pulse, so old.pulse == new.pulse and this is a no-op.
      oldDelegate.pulse.time != pulse.time ||
      oldDelegate.pulse.tilt != pulse.tilt;
}

/// Wrapper around `MaterialTexturePainter` that subscribes the
/// iridescent texture to `LiquidGlassProvider` so the shader's time
/// drift + window-tilt parallax actually drive repaints. Other texture
/// kinds (grain, scanlines, pixels, halftone) get a plain CustomPaint
/// with no pulse subscription — they pay zero cost.
///
/// Used both for per-surface texture passes inside `MaterialSurface`
/// and for the app-root texture backdrop in `main.dart` so iridescent
/// parallax behaves identically wherever the texture appears.
class MaterialTextureLayer extends StatelessWidget {
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final BlendMode blendMode;
  final double opacityScale;

  const MaterialTextureLayer({
    super.key,
    required this.tokens,
    required this.shader,
    this.blendMode = BlendMode.overlay,
    this.opacityScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (shader.texture == ThemeTexture.iridescent) {
      final pulse = LiquidGlassProvider.of(context);
      return RepaintBoundary(
        child: ValueListenableBuilder<LiquidGlassPulse>(
          valueListenable: pulse,
          builder: (_, value, __) => CustomPaint(
            painter: MaterialTexturePainter(
              tokens: tokens,
              shader: shader,
              blendMode: blendMode,
              opacityScale: opacityScale,
              pulse: value,
            ),
          ),
        ),
      );
    }
    return CustomPaint(
      painter: MaterialTexturePainter(
        tokens: tokens,
        shader: shader,
        blendMode: blendMode,
        opacityScale: opacityScale,
      ),
    );
  }
}

/// Wrapper around `_SurfaceGlazePainter` that subscribes glass-using
/// nacre surfaces to `LiquidGlassProvider` so the shader's time/tilt
/// drift drives repaints. Other themes get a plain CustomPaint with no
/// subscription — they pay zero cost.
///
/// `RepaintBoundary` isolates the per-frame glass repaint from the rest
/// of the surface tree (text, borders, shadows). Without it, every
/// pulse tick would invalidate the whole surface subtree.
class _GlazeLayer extends StatelessWidget {
  final AppTokens tokens;
  final SurfaceMaterialRuntime runtime;
  final double radius;
  final bool isGlass;

  const _GlazeLayer({
    required this.tokens,
    required this.runtime,
    required this.radius,
    required this.isGlass,
  });

  @override
  Widget build(BuildContext context) {
    if (isGlass && tokens.id == AppThemeId.nacre) {
      final pulse = LiquidGlassProvider.of(context);
      return RepaintBoundary(
        child: ValueListenableBuilder<LiquidGlassPulse>(
          valueListenable: pulse,
          builder: (_, value, __) => CustomPaint(
            painter: _SurfaceGlazePainter(
              tokens: tokens,
              runtime: runtime,
              radius: radius,
              isGlass: isGlass,
              pulse: value,
            ),
          ),
        ),
      );
    }
    return CustomPaint(
      painter: _SurfaceGlazePainter(
        tokens: tokens,
        runtime: runtime,
        radius: radius,
        isGlass: isGlass,
      ),
    );
  }
}

/// Draws the structural glaze + (for glass) a bottom-right falloff wash.
/// Per-instance seeded from canvas size so adjacent surfaces read as
/// independent panes instead of stamped copies. Stable across paints:
/// same size → same seed → no flicker on scroll or rebuild.
class _SurfaceGlazePainter extends CustomPainter {
  final AppTokens tokens;
  final SurfaceMaterialRuntime runtime;
  final double radius;
  final bool isGlass;
  /// Live state from `LiquidGlassProvider` — drives the glass shader's
  /// time/tilt drift. Only consumed by the nacre branch; other themes
  /// ignore it and the painter compares-equal across pulse changes so
  /// they don't repaint.
  final LiquidGlassPulse pulse;

  const _SurfaceGlazePainter({
    required this.tokens,
    required this.runtime,
    required this.radius,
    required this.isGlass,
    this.pulse = LiquidGlassPulse.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rrect);

    // Nacre uses the real-time liquid-glass fragment shader: rounded-rect
    // SDF rim with chromatic dispersion, two-term spec (soft body + hot
    // core) wrapping a faux-dome normal, center darken for thickness,
    // and time/tilt drift driven by `LiquidGlassProvider`. The pulse's
    // tilt comes from window-position delta so the spec genuinely
    // shifts as the user drags the window. Falls back to no glaze on
    // first frame until the shader program finishes loading.
    if (isGlass && tokens.id == AppThemeId.nacre) {
      // Corner radius scales with the surface radius but biased larger
      // so the meniscus reads as gloopier than the actual clip rect.
      final cornerR = math.max(radius * 1.6, 12.0);
      final fragShader = ThemeShaders.glassShader(
        width: size.width,
        height: size.height,
        tint: const Color(0x00000000),
        highlight: Colors.white,
        // Cool dichroic — pearl-violet so Nacre's identity color shows
        // up in the dichroic side wash, not just generic white.
        highlightCool: tokens.accentBright,
        tiltX: pulse.tilt.dx,
        tiltY: pulse.tilt.dy,
        time: pulse.time,
        intensity: 1.0,
        fresnelPx: 24,
        chromatic: 1.6,
        specSharp: 10,
        specCore: 4,
        thickness: 0.55,
        cornerRadius: cornerR,
        noise: 0.55,
        anim: 1,
      );
      if (fragShader != null) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = fragShader
            ..blendMode = BlendMode.plus,
        );
      }
      canvas.restore();
      return;
    }

    // Per-instance geometry: rotation in [-0.14, 0.14] rad (~±8°) and
    // stop offset in [-0.04, 0.04] pulled from a hash of the surface size.
    // Two panels of different sizes get visually distinct glazes without
    // any randomness at paint-time.
    final seed = (size.width.toInt() * 73 + size.height.toInt() * 131) & 0xFFFF;
    final angle = ((seed % 29) - 14) / 100.0;
    final stopShift = (((seed >> 5) % 9) - 4) / 100.0;

    final mid = (0.24 + stopShift).clamp(0.1, 0.38);
    final far = (0.72 + stopShift).clamp(0.55, 0.9);

    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final dir = Offset(math.cos(angle - math.pi / 4), math.sin(angle - math.pi / 4));
    final start = center - dir * (diag / 2);
    final end = center + dir * (diag / 2);

    final rect = Offset.zero & size;
    final glazePaint = Paint()
      ..shader = LinearGradient(
        begin: FractionalOffset(start.dx / size.width, start.dy / size.height),
        end: FractionalOffset(end.dx / size.width, end.dy / size.height),
        colors: [runtime.glazeTopTint, runtime.glazeMidTint, const Color(0x00000000)],
        stops: [0.0, mid, far],
      ).createShader(rect);
    canvas.drawRect(rect, glazePaint);

    // Glass-only bottom-right falloff — reads as light dropping off across
    // the pane, not just a flat overlay. Uses runtime.cellShadow which is
    // already theme-tinted (ambient-blended black), so it inherits identity
    // for free.
    if (isGlass) {
      final falloff = Paint()
        ..shader = LinearGradient(
          begin: const FractionalOffset(0.45, 0.45),
          end: const FractionalOffset(1, 1),
          colors: [
            const Color(0x00000000),
            runtime.cellShadow.withValues(alpha: 0.12),
          ],
        ).createShader(rect);
      canvas.drawRect(rect, falloff);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SurfaceGlazePainter old) =>
      old.tokens != tokens ||
      old.runtime != runtime ||
      old.radius != radius ||
      old.isGlass != isGlass ||
      // Nacre is the only theme that consumes pulse — comparing on
      // every shouldRepaint is fine because the AnimatedBuilder above
      // already gates non-nacre surfaces from receiving pulse changes.
      old.pulse.time != pulse.time ||
      old.pulse.tilt != pulse.tilt;
}
