import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app/app_identity.dart';
import 'app/ai_settings_state.dart';
import 'app/preferences_state.dart';
import 'app/repository_state.dart';
import 'app/repository_xray_state.dart';
import 'app/hyper_reactivity.dart';
import 'app/sidebar_rail.dart';
import 'app/theme_state.dart';
import 'app/workspace_shell.dart';
import 'diagnostics/diagnostics_state.dart';
import 'ui/material_surface.dart';
import 'ui/theme.dart';
import 'ui/tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  final appIdentityState = AppIdentityState();
  final windowOptions = WindowOptions(
    size: Size(980, 660),
    minimumSize: Size(620, 500),
    center: true,
    title: appIdentityState.identity.shortName,
    backgroundColor: Color(0xFF0A0D12),
    titleBarStyle: TitleBarStyle.normal,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final themeState = ThemeState();
  await themeState.load();

  final repoState = RepositoryState();
  await repoState.loadRecents();
  final repoXrayState = RepositoryXrayState();

  final preferencesState = PreferencesState();
  await preferencesState.load();

  final aiSettingsState = AiSettingsState();
  await aiSettingsState.load();

  final diagnosticsState = DiagnosticsState.instance;
  await diagnosticsState.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeState),
        ChangeNotifierProvider.value(value: repoState),
        ChangeNotifierProvider.value(value: repoXrayState),
        ChangeNotifierProvider.value(value: preferencesState),
        ChangeNotifierProvider.value(value: aiSettingsState),
        ChangeNotifierProvider.value(value: diagnosticsState),
        ChangeNotifierProvider.value(value: appIdentityState),
        ChangeNotifierProvider(create: (_) => HyperReactivity()),
      ],
      child: const GitDesktopApp(),
    ),
  );
}

class GitDesktopApp extends StatefulWidget {
  const GitDesktopApp({super.key});

  @override
  State<GitDesktopApp> createState() => _GitDesktopAppState();
}

class _GitDesktopAppState extends State<GitDesktopApp> {
  AppIdentityState? _appIdentityState;
  String? _windowTitle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextState = context.read<AppIdentityState>();
    if (_appIdentityState != nextState) {
      _appIdentityState?.removeListener(_syncWindowTitle);
      _appIdentityState = nextState;
      _appIdentityState!.addListener(_syncWindowTitle);
    }
    _syncWindowTitle();
  }

  Future<void> _syncWindowTitle() async {
    final shortName = _appIdentityState?.identity.shortName;
    if (shortName == null || shortName == _windowTitle) {
      return;
    }
    _windowTitle = shortName;
    await windowManager.setTitle(shortName);
  }

  @override
  void dispose() {
    _appIdentityState?.removeListener(_syncWindowTitle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final identity = context.watch<AppIdentityState>().identity;
    final tokens = themeState.tokens;

    return MaterialApp(
      title: identity.shortName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(tokens),
      home: const _AppFrame(),
    );
  }
}

class _AppFrame extends StatefulWidget {
  const _AppFrame();

  @override
  State<_AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends State<_AppFrame> {
  double _sidebarWidth = 188;
  bool _resizing = false;
  double _resizeStartX = 0;
  double _resizeStartWidth = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final themeState = context.watch<ThemeState>();
    final definition = themeDefinitionFor(themeState.themeId);
    _sidebarWidth = themeState.sidebarWidth;

    final gradient = t.appGradientColors.length <= 2
        ? LinearGradient(
            begin: t.appGradientAlignments.first as Alignment,
            end: t.appGradientAlignments.last as Alignment,
            colors: t.appGradientColors,
          )
        : RadialGradient(
            center: Alignment.topLeft,
            radius: 1.4,
            colors: t.appGradientColors,
            stops: const [0.14, 0.44, 1.0],
          );

    return Scaffold(
      backgroundColor: t.bg0,
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_showsParticleBackdrop(definition.shader))
              Positioned.fill(
                child: _ParticleBackdrop(
                  tokens: t,
                  shader: definition.shader,
                ),
              ),
            if (_showsTextureBackdrop(definition.shader))
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: MaterialTexturePainter(
                        tokens: t,
                        shader: definition.shader,
                        blendMode: _rootTextureBlendMode(t),
                        opacityScale: _rootTextureOpacity(t),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                SizedBox(width: _sidebarWidth, child: const SidebarRail()),
                SizedBox(
                  width: 1,
                  child: OverflowBox(
                    minWidth: 9,
                    maxWidth: 9,
                    alignment: Alignment.center,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (d) {
                          _resizing = true;
                          _resizeStartX = d.globalPosition.dx;
                          _resizeStartWidth = _sidebarWidth;
                        },
                        onHorizontalDragUpdate: (d) {
                          if (!_resizing) return;
                          final newWidth = _resizeStartWidth +
                              (d.globalPosition.dx - _resizeStartX);
                          context
                              .read<ThemeState>()
                              .setSidebarWidth(_snapSidebarWidth(newWidth));
                        },
                        onHorizontalDragEnd: (_) {
                          _resizing = false;
                          context.read<ThemeState>().setSidebarWidth(
                              _snapSidebarWidth(_sidebarWidth));
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          width: 9,
                          color: _resizing
                              ? t.accentBright.withValues(alpha: 0.22)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
                const Expanded(child: WorkspaceShell()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _snapSidebarWidth(double value) {
    final snapped = (value / 8).round() * 8.0;
    return (snapped - 188).abs() <= 8 ? 188 : snapped;
  }

  bool _showsParticleBackdrop(SurfaceMaterialShader shader) =>
      shader.particles != ThemeParticles.none && shader.parallaxStrength > 0;

  bool _showsTextureBackdrop(SurfaceMaterialShader shader) =>
      shader.texture != ThemeTexture.none && shader.textureOpacity > 0;
}

BlendMode _rootTextureBlendMode(AppTokens tokens) {
  return switch (tokens.id) {
    AppThemeId.quanta => BlendMode.srcOver,
    _ => BlendMode.overlay,
  };
}

double _rootTextureOpacity(AppTokens tokens) {
  return switch (tokens.id) {
    AppThemeId.aether => 0.72,
    AppThemeId.quanta => 0.5,
    _ => 1,
  };
}

class _ParticleBackdrop extends StatefulWidget {
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  const _ParticleBackdrop({required this.tokens, required this.shader});

  @override
  State<_ParticleBackdrop> createState() => _ParticleBackdropState();
}

class _ParticleBackdropState extends State<_ParticleBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: _particleAnimationDuration(widget.shader),
    );
    if (_particlesAnimate(widget.shader)) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ParticleBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration = _particleAnimationDuration(widget.shader);
    if (oldWidget.shader.particles != widget.shader.particles ||
        _controller.duration != duration) {
      _controller.duration = duration;
      if (_particlesAnimate(widget.shader)) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_particlesAnimate(widget.shader)) {
      return CustomPaint(
        painter: _ParticleBackdropPainter(
          tokens: widget.tokens,
          shader: widget.shader,
          progress: 0,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _ParticleBackdropPainter(
          tokens: widget.tokens,
          shader: widget.shader,
          progress: _controller.value,
        ),
      ),
    );
  }
}

bool _particlesAnimate(SurfaceMaterialShader shader) {
  switch (shader.particles) {
    case ThemeParticles.embers:
    case ThemeParticles.voidRain:
    case ThemeParticles.voxels:
    case ThemeParticles.chalkdust:
      return true;
    case ThemeParticles.none:
    case ThemeParticles.stardust:
    case ThemeParticles.ethereal:
    case ThemeParticles.quantum:
      return false;
  }
}

Duration _particleAnimationDuration(SurfaceMaterialShader shader) {
  switch (shader.particles) {
    case ThemeParticles.voidRain:
      return const Duration(seconds: 3);
    case ThemeParticles.embers:
      return const Duration(seconds: 20);
    case ThemeParticles.voxels:
      return const Duration(seconds: 18);
    case ThemeParticles.chalkdust:
      return const Duration(seconds: 200);
    case ThemeParticles.stardust:
    case ThemeParticles.quantum:
    case ThemeParticles.ethereal:
    case ThemeParticles.none:
      return const Duration(seconds: 60);
  }
}

class _ParticleBackdropPainter extends CustomPainter {
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final double progress;

  const _ParticleBackdropPainter({
    required this.tokens,
    required this.shader,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (shader.particles) {
      case ThemeParticles.none:
      case ThemeParticles.ethereal:
        return;
      case ThemeParticles.stardust:
        _drawStardustLayers(canvas, size);
      case ThemeParticles.quantum:
        _drawQuantumLayers(canvas, size);
      case ThemeParticles.embers:
        _drawEmberLayers(canvas, size);
      case ThemeParticles.voidRain:
        _drawRepeatedTile(
          canvas,
          size,
          tileSize: 1000,
          opacity: 0.3,
          offset: Offset(0, -1000 + 2000 * progress),
          drawTile: _drawVoidTile,
        );
      case ThemeParticles.voxels:
        _drawRepeatedTile(
          canvas,
          size,
          tileSize: 1000,
          opacity: 0.6,
          offset: Offset(0, -1000 + 2000 * progress),
          drawTile: _drawVoxelTile,
        );
      case ThemeParticles.chalkdust:
        _drawRepeatedTile(
          canvas,
          size,
          tileSize: size.shortestSide.clamp(760, 1500).toDouble(),
          opacity: 0.46,
          offset: Offset.zero,
          drawTile: _drawChalkTile,
        );
    }
  }

  void _drawStardustLayers(Canvas canvas, Size size) {
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 560,
      opacity: 0.4,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 34, 0.14, 0.46, 89.4),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1940,
      opacity: 0.6,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 28, 0.29, 0.66, 57.8),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1540,
      opacity: 0.6,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 20, 0.48, 1.04, 31.2),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1120,
      opacity: 0.6,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 14, 0.78, 1.65, 1.7),
    );
  }

  void _drawQuantumLayers(Canvas canvas, Size size) {
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 460,
      opacity: 0.46,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 10, 0.22, 0.7, 72.9, 5, 290),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1700,
      opacity: 0.6,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 14, 0.33, 0.84, 47.6, 4, 255),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1320,
      opacity: 0.6,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 20, 0.48, 1, 21.4, 3, 215),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 900,
      opacity: 0.6,
      offset: Offset.zero,
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 26, 0.62, 1.22, 3.2, 2, 170),
    );
  }

  void _drawRepeatedTile(
    Canvas canvas,
    Size size, {
    required double tileSize,
    required double opacity,
    required Offset offset,
    double? viewportPadding,
    required void Function(Canvas canvas, double scale) drawTile,
  }) {
    final overscan =
        viewportPadding ?? (tileSize * 0.18).clamp(40.0, 240.0).toDouble();
    final wrapped = Offset(offset.dx % tileSize, offset.dy % tileSize);
    final startX = -tileSize - overscan + wrapped.dx;
    final startY = -tileSize - overscan + wrapped.dy;
    final endX = size.width + tileSize + overscan;
    final endY = size.height + tileSize + overscan;
    for (var x = startX; x < endX; x += tileSize) {
      for (var y = startY; y < endY; y += tileSize) {
        canvas.saveLayer(
          Rect.fromLTWH(
            x - overscan,
            y - overscan,
            tileSize + overscan * 2,
            tileSize + overscan * 2,
          ),
          Paint()..color = Colors.white.withValues(alpha: opacity),
        );
        canvas.translate(x, y);
        final scale = tileSize / 1000;
        canvas.scale(scale);
        drawTile(canvas, scale);
        canvas.restore();
      }
    }
  }

  void _drawStardustTile(
    Canvas canvas,
    double scale,
    int count,
    double alpha,
    double radiusScale,
    double seed,
  ) {
    final rng = _SourceRandom((seed * 1000).round() + count * 97);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final glintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Consume the same RNG sequence as the old haze circles so that
    // removing them doesn't shift the star positions below.
    for (var haze = 0; haze < 3; haze++) {
      rng.next(); rng.next(); rng.next(); // hazeX, hazeY, hazeRadius
    }

    for (var i = 0; i < count; i++) {
      final x = rng.next() * 1000;
      final y = rng.next() * 1000;
      final brightness = rng.next();
      final r = (0.3 + brightness * brightness * 1.7) * radiusScale;
      final glow = alpha * (0.35 + brightness * 0.75);
      final tint = _stardustTint(rng.next());

      fillPaint.color = tint.withValues(alpha: glow * 0.14);
      canvas.drawCircle(Offset(x, y), r * (2.1 + rng.next() * 0.9), fillPaint);

      if (brightness > 0.82) {
        glintPaint
          ..color = tint.withValues(alpha: glow * 0.28)
          ..strokeWidth = 0.6 + r * 0.24;
        final glint = 4 + brightness * 10;
        canvas.drawLine(Offset(x - glint, y), Offset(x + glint, y), glintPaint);
        canvas.drawLine(Offset(x, y - glint), Offset(x, y + glint), glintPaint);
      }

      fillPaint.color = Colors.white.withValues(alpha: glow);
      canvas.drawCircle(Offset(x, y), r, fillPaint);
    }
  }

  void _drawEmberLayers(Canvas canvas, Size size) {
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1320,
      opacity: 0.2,
      offset: Offset(-180 * progress, 120 * progress),
      drawTile: (tile, scale) => _drawEmberFieldTile(
        tile,
        seed: 0x0E8B3A12,
        ashCount: 64,
        emberCount: 14,
        sparkCount: 0,
        minCoreRadius: 0.5,
        maxCoreRadius: 1.5,
        trailMin: 8,
        trailMax: 18,
        angleCenter: -1.08,
        angleSpread: 0.48,
        coolBias: 0,
      ),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 980,
      opacity: 0.3,
      offset: Offset(120 * progress, -840 * progress),
      drawTile: (tile, scale) => _drawEmberFieldTile(
        tile,
        seed: 0x0E8B3A7F,
        ashCount: 24,
        emberCount: 24,
        sparkCount: 4,
        minCoreRadius: 0.9,
        maxCoreRadius: 2.6,
        trailMin: 12,
        trailMax: 28,
        angleCenter: -1.2,
        angleSpread: 0.62,
        coolBias: 0.1,
      ),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1180,
      opacity: 0.18,
      offset: Offset(-90 * progress, -1220 * progress),
      drawTile: (tile, scale) => _drawEmberFieldTile(
        tile,
        seed: 0x0E8B401D,
        ashCount: 18,
        emberCount: 8,
        sparkCount: 12,
        minCoreRadius: 0.7,
        maxCoreRadius: 1.8,
        trailMin: 10,
        trailMax: 22,
        angleCenter: -1.34,
        angleSpread: 0.34,
        coolBias: 0.34,
      ),
    );
  }

  void _drawEmberFieldTile(
    Canvas canvas, {
    required int seed,
    required int ashCount,
    required int emberCount,
    required int sparkCount,
    required double minCoreRadius,
    required double maxCoreRadius,
    required double trailMin,
    required double trailMax,
    required double angleCenter,
    required double angleSpread,
    required double coolBias,
  }) {
    final rng = _SourceRandom(seed);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final warmPalette = <Color>[
      const Color(0xFFFF6D52),
      const Color(0xFFFF9750),
      const Color(0xFFFFBE72),
    ];

    // Fine ash keeps the field alive without reading as big drifting blobs.
    for (var i = 0; i < ashCount; i++) {
      final x = rng.next() * 1000;
      final y = rng.next() * 1000;
      final alpha = 0.022 + rng.next() * 0.05;
      final radius = 0.3 + rng.next() * 0.85;
      final colorPick = rng.next();
      final color = colorPick > 0.86
          ? const Color(0xFF00F0FF)
          : colorPick > 0.44
              ? const Color(0xFFFF8A70)
              : const Color(0xFFFFB066);
      fillPaint.color = color.withValues(alpha: alpha * 0.12);
      canvas.drawCircle(Offset(x, y), radius * 1.6, fillPaint);
      fillPaint.color = Colors.white.withValues(alpha: alpha * 0.55);
      canvas.drawCircle(Offset(x, y), radius, fillPaint);
    }

    // Main embers use short tilted smears so they read like cinders, not dots.
    for (var i = 0; i < emberCount; i++) {
      final x = 40 + rng.next() * 920;
      final y = 50 + rng.next() * 900;
      final radius =
          minCoreRadius + rng.next() * (maxCoreRadius - minCoreRadius);
      final energy = 0.07 + rng.next() * 0.13;
      final trail = trailMin + rng.next() * (trailMax - trailMin);
      final angle = angleCenter + (rng.next() - 0.5) * angleSpread;
      final useCool = rng.next() < coolBias;
      final color = useCool
          ? const Color(0xFF00F0FF)
          : warmPalette[(rng.next() * warmPalette.length).floor()];
      _drawEmberGlow(
        canvas,
        fillPaint,
        center: Offset(x, y),
        radius: radius,
        trailLength: trail,
        angle: angle,
        color: color,
        alpha: energy,
      );
    }

    // Blue signal flecks stay secondary and sharper than the warm ember bodies.
    for (var i = 0; i < sparkCount; i++) {
      final x = 70 + rng.next() * 860;
      final y = 70 + rng.next() * 860;
      final radius = 0.55 + rng.next() * 1.15;
      final alpha = 0.06 + rng.next() * 0.08;
      final angle = -1.4 + (rng.next() - 0.5) * 0.22;
      _drawNeedleSpark(
        canvas,
        fillPaint,
        center: Offset(x, y),
        radius: radius,
        length: 7 + rng.next() * 14,
        angle: angle,
        alpha: alpha,
      );
    }
  }

  void _drawEmberGlow(
    Canvas canvas,
    Paint fillPaint, {
    required Offset center,
    required double radius,
    required double trailLength,
    required double angle,
    required Color color,
    required double alpha,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    fillPaint.color = color.withValues(alpha: alpha * 0.14);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(trailLength * 0.12, 0),
        width: trailLength * 2.5,
        height: radius * 4.8,
      ),
      fillPaint,
    );

    fillPaint.color = color.withValues(alpha: alpha * 0.22);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(trailLength * 0.26, 0),
        width: trailLength * 1.4,
        height: radius * 2.8,
      ),
      fillPaint,
    );

    fillPaint.color = Colors.white.withValues(alpha: alpha * 0.9);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(trailLength * 0.05, 0),
        width: radius * 1.5,
        height: radius * 1.05,
      ),
      fillPaint,
    );
    canvas.restore();
  }

  void _drawNeedleSpark(
    Canvas canvas,
    Paint fillPaint, {
    required Offset center,
    required double radius,
    required double length,
    required double angle,
    required double alpha,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    fillPaint.color = const Color(0xFF00F0FF).withValues(alpha: alpha * 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: length * 1.9,
          height: radius * 2.4,
        ),
        Radius.circular(radius * 1.2),
      ),
      fillPaint,
    );

    fillPaint.color = const Color(0xFFB7F4FF).withValues(alpha: alpha);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(length * 0.08, 0),
          width: length * 0.7,
          height: radius * 1.1,
        ),
        Radius.circular(radius * 0.6),
      ),
      fillPaint,
    );
    canvas.restore();
  }

  void _drawVoxelTile(Canvas canvas, double scale) {
    final paint = Paint()..style = PaintingStyle.fill;
    final ambient = tokens.themeAmbient ?? Colors.white;
    paint.color = ambient.withValues(alpha: 0.03);
    for (var i = 0; i < 15; i++) {
      final x = math.sin(i * 444) * 500 + 500;
      final y = math.sin(i * 222 + 33) * 500 + 500;
      final side = math.sin(i * 33).abs() * 20 + 10;
      canvas.drawRect(Rect.fromLTWH(x, y, side, side), paint);
    }
  }

  void _drawChalkTile(Canvas canvas, double scale) {
    final colors = [
      (tokens.themeAmbient ?? Colors.white).withValues(alpha: 0.1),
      (tokens.themeAmbient ?? Colors.white).withValues(alpha: 0.1),
      const Color(0xFFFF828C).withValues(alpha: 0.6),
      const Color(0xFF96D2FF).withValues(alpha: 0.6),
      const Color(0xFFFFDC78).withValues(alpha: 0.6),
    ];
    for (var i = 1; i <= 5; i++) {
      final rng = _SourceRandom(i * 9173);
      final col = (i - 1) % 3;
      final row = (i - 1) ~/ 3;
      final cx = col * 300 + 200 + (rng.next() - 0.5) * 150;
      final cy = row * 300 + 200 + (rng.next() - 0.5) * 150;
      final a = (rng.next() * 4 + 2).floor();
      final b = (rng.next() * 4 + 2).floor();
      final absA = a == b ? a + 1 : a;
      final delta = rng.next() * math.pi * 2;
      final radius = rng.next() * 80 + 60;
      final rotation = rng.next() * math.pi * 2;
      final strokeWidth = rng.next() * 0.4 + 0.15;
      final reveal = _chalkReveal(progress, i);

      final points = <Offset>[];
      const steps = 140;
      for (var step = 0; step <= steps; step++) {
        final t = step * (math.pi * 2.1 / steps);
        final jitter = math.sin(t * 30 + i) * 0.7;
        final x = math.sin(absA * t + delta) * (radius + jitter);
        final y = math.sin(b * t) * (radius + jitter);
        final rotated = Offset(
          x * math.cos(rotation) - y * math.sin(rotation) + cx,
          x * math.sin(rotation) + y * math.cos(rotation) + cy,
        );
        points.add(rotated);
      }

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      final visible = (points.length * reveal).floor().clamp(1, points.length);
      for (var p = 1; p < visible; p++) {
        path.lineTo(points[p].dx, points[p].dy);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokeWidth
        ..color = colors[i % colors.length].withValues(alpha: 0.34 * reveal);
      canvas.drawPath(path, paint);
    }
  }

  double _chalkReveal(double value, int index) {
    final shifted = (value + index * 0.01) % 1;
    if (shifted < 0.12) return shifted / 0.12;
    if (shifted < 0.34) return 1;
    if (shifted < 0.88) return 1;
    return (1 - shifted) / 0.12;
  }

  void _drawVoidTile(Canvas canvas, double scale) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false
      ..color = const Color(0xFF00F0FF);
    final rng = _SourceRandom(0x00F0FF);
    for (var i = 0; i < 60; i++) {
      final x = (rng.next() * 998).floorToDouble();
      final y = (rng.next() * 980).floorToDouble();
      final h = (20 + rng.next() * 40).floorToDouble();
      final alpha = 0.3 + rng.next() * 0.5;
      paint.color = const Color(0xFF00F0FF).withValues(alpha: alpha);
      canvas.drawRect(Rect.fromLTWH(x, y, 1, h), paint);
    }
  }

  void _drawQuantumTile(
    Canvas canvas,
    double scale,
    int count,
    double alpha,
    double radiusScale,
    double seed,
    int orbitStride,
    double orbitRadius,
  ) {
    final rng = _SourceRandom((seed * 1000).round() + orbitStride * 53);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;

    // Consume the same RNG sequence as the old node/ring geometry so that
    // changing this doesn't shift the remaining spark positions.
    final nodeCount = (count / 6).round().clamp(2, 5).toInt();
    for (var nodeIndex = 0; nodeIndex < nodeCount; nodeIndex++) {
      rng.next(); rng.next(); // cx, cy
      rng.next(); // coreRadius
      rng.next(); // ringRadius rand
      final orbitCount = 4 + (rng.next() * 5).floor() + orbitStride ~/ 2;
      rng.next(); // strokeWidth rand
      rng.next(); // outer ring gate
      rng.next(); // outer ring radius rand
      for (var orbitIndex = 0; orbitIndex < orbitCount; orbitIndex++) {
        rng.next(); rng.next(); rng.next(); // angle, orbit, r
      }
    }

    final sparkCount = count;
    for (var i = 0; i < sparkCount; i++) {
      final x = rng.next() * 1000;
      final y = rng.next() * 1000;
      final r = 0.35 + rng.next() * 1.05 * radiusScale;
      final color =
          rng.next() > 0.72 ? const Color(0xFF9E6CFF) : const Color(0xFF50FFD2);
      fillPaint.color =
          color.withValues(alpha: alpha * (0.18 + rng.next() * 0.24));
      canvas.drawCircle(Offset(x, y), r * 1.8, fillPaint);
    }
  }

  Color _stardustTint(double value) {
    if (value > 0.88) return const Color(0xFFE5C8FF);
    if (value > 0.54) return const Color(0xFFB682FF);
    if (value > 0.24) return const Color(0xFF78B4FF);
    return const Color(0xFFBFE1FF);
  }

  @override
  bool shouldRepaint(_ParticleBackdropPainter oldDelegate) =>
      oldDelegate.tokens != tokens ||
      oldDelegate.shader != shader ||
      (_particlesAnimate(shader) && oldDelegate.progress != progress);
}

class _SourceRandom {
  int _state;
  _SourceRandom(this._state);

  double next() {
    _state = (1664525 * _state + 1013904223) & 0xffffffff;
    return _state / 0xffffffff;
  }
}
