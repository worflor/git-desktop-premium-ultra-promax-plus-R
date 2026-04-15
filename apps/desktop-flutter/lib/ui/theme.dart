import 'package:flutter/material.dart';
import 'tokens.dart';

final _themeCache = <AppThemeId, ThemeData>{};

ThemeData buildTheme(AppTokens t) {
  return _themeCache.putIfAbsent(t.id, () => _buildTheme(t));
}

/// Flatten a translucent palette token against [t.bg0] to produce a
/// guaranteed-opaque equivalent.
/// **Why this exists**: Material3 widgets (Card, PopupMenu, anything
/// with an elevation overlay, anything reading `colorScheme.surface`)
/// internally call `Color.alphaBlend(surfaceTint, baseColor)` to
/// compute their final fill. `Color.alphaBlend` treats the BASE as
/// fully opaque before blending — so passing a translucent
/// `colorScheme.surface` produces a fully-opaque pixel regardless of
/// the declared alpha. This silently flattens any translucency the
/// theme palette intended.
/// **The invariant**: every Material-system color slot
/// (`ColorScheme.surface`, `CardTheme.color`, `PopupMenuTheme.color`,
/// any other widget theme that takes a "background" Color) must
/// receive a fully-opaque value. Translucent surface effects come
/// EXCLUSIVELY from `MaterialSurface`, which owns its own
/// `BackdropFilter` machinery and is not subject to `alphaBlend`
/// flattening.
/// `Color.alphaBlend(translucent, opaque)` here pre-bakes the visual
/// result the translucent token described, producing an opaque pixel
/// that Material widgets can use as a canvas without surprise.
Color _opaqueOnBg(AppTokens t, Color translucent) =>
    Color.alphaBlend(translucent, t.bg0);

ThemeData _buildTheme(AppTokens t) {
  final shader = themeDefinitionFor(t.id).shader;
  final radius = shader.geometry.radius.clamp(0, 18).toDouble();
  final fontFamily = shader.geometry.typography ?? 'DM Sans';
  final fontFallback = _fontFallbackFor(t.id);
  final fontScale = shader.geometry.fontScale;
  final letterSpacingEm = shader.geometry.letterSpacingEm;
  // Pre-flatten the canonical surface tone once. Reused across
  // ColorScheme + CardTheme + PopupMenuTheme so all Material widgets
  // see the same opaque substrate.
  final opaqueSurface = _opaqueOnBg(t, t.surface1);
  final colorScheme = ColorScheme(
    brightness: t.isDark ? Brightness.dark : Brightness.light,
    primary: t.accentBright,
    onPrimary: t.isDark ? Colors.black : Colors.white,
    secondary: t.chromeAccent,
    onSecondary: t.isDark ? Colors.black : Colors.white,
    error: t.danger,
    onError: Colors.white,
    surface: opaqueSurface,
    onSurface: t.textNormal,
    // Disable Material3's elevation tint. By default `surfaceTint`
    // falls back to `primary`, and Material widgets composite an
    // elevation-derived overlay of that color via `Color.alphaBlend`
    // onto every elevated surface — flattening any translucent fill
    // and painting an unwanted accent wash. `MaterialSurface` owns
    // all surface visuals; no Material widget should ever add tint.
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: t.bg0,
    fontFamily: fontFamily,
    extensions: [AppThemeExtension(t)],
    cardTheme: CardThemeData(
      color: opaqueSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: t.shadowElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: t.chromeBorder.withValues(alpha: 0.18)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return t.inputBg;
        return switch (t.id) {
          AppThemeId.blackboard => Colors.transparent,
          AppThemeId.crafty => t.sliderThumb,
          _ => t.accentBright,
        };
      }),
      checkColor: WidgetStatePropertyAll(
        switch (t.id) {
          AppThemeId.crafty => t.btnBorder,
          _ => t.bg0,
        },
      ),
      side: BorderSide(
        color: switch (t.id) {
          AppThemeId.blackboard => Colors.white,
          AppThemeId.crafty => t.btnBorder,
          _ => t.inputBorder,
        },
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          switch (t.id) {
            AppThemeId.crafty => 0,
            AppThemeId.loverboy => 0,
            AppThemeId.blackboard => 2,
            _ => 4,
          },
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius * 0.75),
        borderSide: BorderSide(color: t.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius * 0.75),
        borderSide: BorderSide(color: t.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius * 0.75),
        borderSide: BorderSide(color: t.inputFocusBorder),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.chromeAccent,
      inactiveTrackColor: t.sliderTrack,
      thumbColor: t.sliderThumb,
      overlayColor: t.chromeAccent.withValues(alpha: 0.14),
      valueIndicatorColor: t.sliderThumbBorder,
      trackHeight: 6,
      trackShape: _ThemedSliderTrackShape(t),
      thumbShape: _sliderThumbShape(t),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: opaqueSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: t.chromeBorder.withValues(alpha: 0.25)),
      ),
      textStyle: TextStyle(color: t.textNormal, fontSize: 12 * fontScale),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(
          color: t.textNormal,
          fontSize: 13 * fontScale,
          letterSpacing: _letterSpacingFor(13 * fontScale, letterSpacingEm),
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback),
      bodySmall: TextStyle(
          color: t.textMuted,
          fontSize: 11 * fontScale,
          letterSpacing: _letterSpacingFor(11 * fontScale, letterSpacingEm),
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback),
      labelMedium: TextStyle(
          color: t.textNormal,
          fontSize: 12 * fontScale,
          letterSpacing: _letterSpacingFor(12 * fontScale, letterSpacingEm),
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w500),
      labelSmall: TextStyle(
        color: t.textMuted,
        fontSize: 10 * fontScale,
        letterSpacing: _letterSpacingFor(10 * fontScale, letterSpacingEm),
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
      ),
      titleSmall: TextStyle(
          color: t.textStrong,
          fontSize: 12 * fontScale,
          letterSpacing: _letterSpacingFor(12 * fontScale, letterSpacingEm),
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w700),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(t.scrollbarThumb),
      thickness: WidgetStatePropertyAll(4),
      radius: const Radius.circular(4),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    // Material3 button widgets (IconButton/TextButton/ElevatedButton/etc)
    // ignore `hoverColor` and `splashFactory` — they resolve their own
    // per-state `WidgetStateProperty<Color?>` overlay, defaulting to
    // `colorScheme.onSurface @ 8%` on hover and 12% on press. That's
    // the gray flash visible on hover-in AND hover-out (since the
    // overlay fades in then back out). Disable it on every Material
    // button class so only our custom hover styling shows.
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(overlayColor: Colors.transparent),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(overlayColor: Colors.transparent),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(overlayColor: Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(overlayColor: Colors.transparent),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(overlayColor: Colors.transparent),
    ),
  );
}

double _letterSpacingFor(double fontSize, double letterSpacingEm) =>
    fontSize * letterSpacingEm;

List<String>? _fontFallbackFor(AppThemeId id) {
  switch (id) {
    case AppThemeId.blackboard:
      return const ['Georgia', 'Times New Roman', 'serif'];
    case AppThemeId.crafty:
      return const ['Consolas', 'Courier New', 'monospace'];
    case AppThemeId.nightwalker:
    case AppThemeId.redshift:
    case AppThemeId.phosphor:
      return const ['Consolas', 'Courier New', 'monospace'];
    case AppThemeId.halo:
      return const ['Georgia', 'Times New Roman', 'serif'];
    case AppThemeId.petrichor:
    case AppThemeId.helix:
    case AppThemeId.aether:
    case AppThemeId.quanta:
    case AppThemeId.kirby:
      return const ['Segoe UI', 'Arial', 'sans-serif'];
    case AppThemeId.nacre:
    case AppThemeId.loverboy:
      return const ['Georgia', 'Times New Roman', 'serif'];
  }
}

SliderComponentShape _sliderThumbShape(AppTokens t) => switch (t.id) {
      AppThemeId.aether => _GlassSliderThumbShape(
          size: 20,
          fillColor: Colors.white.withValues(alpha: 0.15),
          borderColor: Colors.white.withValues(alpha: 0.4),
          glowColor: t.chromeAccent.withValues(alpha: 0.3),
        ),
      AppThemeId.helix => const _BrassSliderThumbShape(size: 18),
      AppThemeId.petrichor => const _DropletSliderThumbShape(size: 20),
      AppThemeId.quanta => _DiamondSliderThumbShape(
          size: 14,
          fillColor: t.accentBright,
          borderColor: Colors.black.withValues(alpha: 0.5),
          glowColor: t.chromeAccent.withValues(alpha: 0.4),
        ),
      AppThemeId.redshift => _SightSliderThumbShape(
          size: const Size(12, 24),
          fillColor: t.accentBright,
          glowColor: const Color(0x66FF0044),
        ),
      AppThemeId.halo => _HaloSliderThumbShape(
          size: 18,
          fillColor: Colors.white,
          borderColor: t.accentBright,
        ),
      AppThemeId.crafty => const _SquareSliderThumbShape(
          size: 16,
          borderWidth: 3.5,
          insetShadow: true,
        ),
      AppThemeId.nightwalker => _RingSliderThumbShape(
          size: 22,
          ringColor: t.accentBright,
        ),
      AppThemeId.blackboard =>
        const _SquareSliderThumbShape(size: 16, radius: 2, borderWidth: 2),
      AppThemeId.kirby =>
        // Square inked thumb — chunky border matches the theme's ink line.
        const _SquareSliderThumbShape(
            size: 18, radius: 4, borderWidth: 2.5, insetShadow: false),
      AppThemeId.phosphor =>
        // Square block thumb — like a CRT cursor. Sharp, no fill,
        // monospaced-block aesthetic.
        const _SquareSliderThumbShape(
            size: 14, radius: 0, borderWidth: 2, insetShadow: false),
      AppThemeId.nacre => _GlassSliderThumbShape(
          size: 18,
          fillColor: Colors.white.withValues(alpha: 0.6),
          borderColor: t.accentBright,
          glowColor: t.accentBright.withValues(alpha: 0.4),
        ),
      AppThemeId.loverboy => _GlassSliderThumbShape(
          size: 18,
          fillColor: t.bg3.withValues(alpha: 0.75),
          borderColor: t.accentBright,
          glowColor: t.chromeBorder.withValues(alpha: 0.45),
        ),
    };

class _ThemedSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  final AppTokens tokens;

  const _ThemedSliderTrackShape(this.tokens);

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 6;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
      trackLeft,
      trackTop,
      parentBox.size.width,
      trackHeight,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular((sliderTheme.trackHeight ?? 6) / 2);
    final trackRRect = RRect.fromRectAndRadius(trackRect, radius);
    final activeRect = switch (textDirection) {
      TextDirection.ltr => Rect.fromLTRB(
          trackRect.left,
          trackRect.top,
          thumbCenter.dx.clamp(trackRect.left, trackRect.right),
          trackRect.bottom,
        ),
      TextDirection.rtl => Rect.fromLTRB(
          thumbCenter.dx.clamp(trackRect.left, trackRect.right),
          trackRect.top,
          trackRect.right,
          trackRect.bottom,
        ),
    };
    final activeRRect = RRect.fromRectAndRadius(activeRect, radius);
    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ??
          tokens.chromeBorder.withValues(alpha: 0.22);
    canvas.drawRRect(trackRRect, inactivePaint);

    final activeColor = sliderTheme.activeTrackColor ?? tokens.chromeAccent;
    final activePaint = Paint()..color = activeColor;
    canvas.drawRRect(activeRRect, activePaint);

    switch (tokens.id) {
      case AppThemeId.aether:
        _drawTrackGlow(
          canvas,
          trackRRect,
          Colors.black.withValues(alpha: 0.20),
          blur: 2,
          offset: const Offset(0, 1),
        );
        _strokeTrack(
          canvas,
          trackRRect,
          Colors.white.withValues(alpha: 0.15),
          width: 0.8,
        );
      case AppThemeId.helix:
        _strokeTrack(canvas, trackRRect, const Color(0xFF8C7657), width: 1);
      case AppThemeId.petrichor:
        _drawTrackGlow(
          canvas,
          trackRRect,
          Colors.black.withValues(alpha: 0.08),
          blur: 4,
        );
        _strokeTrack(
          canvas,
          trackRRect,
          tokens.chromeBorder.withValues(alpha: 0.10),
          width: 1,
        );
      case AppThemeId.redshift:
        _drawTrackGlow(
          canvas,
          trackRRect,
          const Color(0x33FF0044),
          blur: 4,
        );
        _strokeTrack(canvas, trackRRect, const Color(0x4DFF0044), width: 0.8);
      case AppThemeId.halo:
        _strokeTrack(canvas, trackRRect, const Color(0x33D4AF37), width: 1);
      case AppThemeId.nightwalker:
        _drawTrackGlow(
          canvas,
          trackRRect,
          const Color(0x2600F0FF),
          blur: 6,
        );
        _strokeTrack(
          canvas,
          trackRRect,
          const Color(0x1A00F0FF),
          width: 1,
        );
      case AppThemeId.blackboard:
      case AppThemeId.crafty:
      case AppThemeId.quanta:
        break;
      case AppThemeId.kirby:
        // Comic ink stroke around the entire track.
        _strokeTrack(canvas, trackRRect, tokens.textStrong, width: 2);
      case AppThemeId.phosphor:
        // Phosphor green hairline around the track — feels like a
        // CRT pixel rectangle.
        _strokeTrack(canvas, trackRRect, tokens.chromeAccent, width: 1);
      case AppThemeId.nacre:
      case AppThemeId.loverboy:
        _strokeTrack(
          canvas,
          trackRRect,
          tokens.accentBright.withValues(alpha: 0.35),
          width: 0.8,
        );
    }
  }

  void _strokeTrack(Canvas canvas, RRect track, Color color,
      {double width = 1}) {
    canvas.drawRRect(
      track.deflate(width / 2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  void _drawTrackGlow(
    Canvas canvas,
    RRect track,
    Color color, {
    double blur = 4,
    Offset offset = Offset.zero,
  }) {
    canvas.drawRRect(
      track.shift(offset),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)
        ..style = PaintingStyle.fill,
    );
  }
}

class _GlassSliderThumbShape extends SliderComponentShape {
  final double size;
  final Color fillColor;
  final Color borderColor;
  final Color glowColor;

  const _GlassSliderThumbShape({
    required this.size,
    required this.fillColor,
    required this.borderColor,
    required this.glowColor,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rimGlow = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center, size * 0.5, rimGlow);

    final fillPaint = Paint()..color = fillColor;
    canvas.drawCircle(center, size * 0.5, fillPaint);

    final rimPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, size * 0.5 - 0.6, rimPaint);

    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center.translate(0, -0.5), size * 0.28, innerPaint);
  }
}

class _DiamondSliderThumbShape extends SliderComponentShape {
  final double size;
  final Color fillColor;
  final Color borderColor;
  final Color glowColor;

  const _DiamondSliderThumbShape({
    required this.size,
    required this.fillColor,
    required this.borderColor,
    required this.glowColor,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(center: center, width: size, height: size);
    final diamond = Path()
      ..moveTo(center.dx, rect.top)
      ..lineTo(rect.right, center.dy)
      ..lineTo(center.dx, rect.bottom)
      ..lineTo(rect.left, center.dy)
      ..close();

    final rimGlow = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(diamond, rimGlow);

    final fillPaint = Paint()..color = fillColor;
    canvas.drawPath(diamond, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(diamond, borderPaint);
  }
}

class _BrassSliderThumbShape extends SliderComponentShape {
  final double size;

  const _BrassSliderThumbShape({required this.size});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(center: center, width: size, height: size);
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFE2D1B6), Color(0xFFCFB996)],
    );
    canvas.drawCircle(
      center,
      size / 2,
      Paint()..shader = gradient.createShader(rect),
    );
    canvas.drawCircle(
      center,
      size / 2 - 1,
      Paint()
        ..color = const Color(0xFF2F2519)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Inner dot centered on the thumb — previously offset by (1, 1) for a
    // 3D embossed look, which shifted the perceived center off the rail.
    canvas.drawCircle(
      center,
      size * 0.22,
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
  }
}

class _DropletSliderThumbShape extends SliderComponentShape {
  final double size;

  const _DropletSliderThumbShape({required this.size});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(0.78539816339);
    final rect =
        Rect.fromCenter(center: Offset.zero, width: size, height: size);
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(size / 2),
      topRight: Radius.circular(size / 2),
      bottomLeft: Radius.circular(size / 2),
      bottomRight: const Radius.circular(2),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
    canvas.drawRRect(
      rrect.deflate(1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }
}

class _SightSliderThumbShape extends SliderComponentShape {
  final Size size;
  final Color fillColor;
  final Color glowColor;

  const _SightSliderThumbShape({
    required this.size,
    required this.fillColor,
    required this.glowColor,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => size;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
    final path = Path()
      ..moveTo(rect.left, rect.top + rect.height * 0.15)
      ..lineTo(center.dx, rect.top)
      ..lineTo(rect.right, rect.top + rect.height * 0.15)
      ..lineTo(rect.right, rect.bottom - rect.height * 0.15)
      ..lineTo(center.dx, rect.bottom)
      ..lineTo(rect.left, rect.bottom - rect.height * 0.15)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = glowColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(path, Paint()..color = fillColor);
  }
}

class _HaloSliderThumbShape extends SliderComponentShape {
  final double size;
  final Color fillColor;
  final Color borderColor;

  const _HaloSliderThumbShape({
    required this.size,
    required this.fillColor,
    required this.borderColor,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, size / 2, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      size / 2 - 1,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      size * 0.22,
      Paint()..color = Colors.black.withValues(alpha: 0.05),
    );
  }
}

class _RingSliderThumbShape extends SliderComponentShape {
  final double size;
  final Color ringColor;

  const _RingSliderThumbShape({required this.size, required this.ringColor});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      size / 2,
      Paint()
        ..color = ringColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      size / 2 - 1.5,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      center,
      size * 0.18,
      Paint()
        ..color = ringColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
}

class _SquareSliderThumbShape extends SliderComponentShape {
  final double size;
  final double radius;
  final double borderWidth;
  final bool insetShadow;

  const _SquareSliderThumbShape({
    required this.size,
    this.radius = 0,
    this.borderWidth = 1,
    this.insetShadow = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = Rect.fromCenter(center: center, width: size, height: size);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final fill = sliderTheme.thumbColor ?? Colors.white;
    final border = sliderTheme.valueIndicatorColor ??
        sliderTheme.activeTrackColor ??
        Colors.white;
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = fill;
    canvas.drawRRect(rrect, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = border;
    canvas.drawRRect(rrect.deflate(borderWidth / 2), paint);
    if (insetShadow) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.4);
      canvas.drawLine(
        Offset(rect.right - 3, rect.top + 3),
        Offset(rect.right - 3, rect.bottom - 3),
        paint,
      );
      canvas.drawLine(
        Offset(rect.left + 3, rect.bottom - 3),
        Offset(rect.right - 3, rect.bottom - 3),
        paint,
      );
    }
  }
}
