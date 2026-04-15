import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app/app_identity.dart';
import 'app/ai_settings_state.dart';
import 'app/preferences_state.dart';
import 'app/repository_state.dart';
import 'app/repository_xray_state.dart';
import 'app/file_coupling_state.dart';
import 'app/symbol_frequency_state.dart';
import 'app/logos_git_state.dart';
import 'app/worktree_state.dart';
import 'app/desk_pr_state.dart';
import 'app/desk_issue_state.dart';
import 'app/remote_issue_cache_state.dart';
import 'app/hyper_reactivity.dart';
import 'app/brand_lockup.dart';
import 'app/sidebar_rail.dart';
import 'app/window_activity.dart';
import 'app/theme_state.dart';
import 'app/workspace_shell.dart';
import 'backend/engram_bootstrap.dart';
import 'backend/logos_git_resolver.dart' as logos_resolver;
import 'backend/settings_store.dart';
import 'diagnostics/diagnostics_state.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'features/onboarding/onboarding_state.dart';
import 'ui/liquid_glass.dart';
import 'ui/material_surface.dart';
import 'ui/theme.dart';
import 'ui/theme_shaders.dart';
import 'ui/tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // Settings drive identity + onboarding gate — load once up front so
  // first paint reflects persisted state (the user's chosen name and
  // whether they've already completed onboarding).
  final settings = await SettingsStore.load();
  final appIdentityState = AppIdentityState();
  appIdentityState.loadFromSettings(settings);
  final onboardingState = OnboardingState();
  onboardingState.hydrateFromSettings(settings);

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

  // Kick off shader compilation in the background — fire-and-forget.
  // First paint that needs cellshade falls back to the non-shader path
  // until the program is ready (typically <100ms after launch).
  ThemeShaders.cellshade();
  ThemeShaders.iridescent();
  ThemeShaders.glass();

  // Same idea for the Alexandria engram + GloVe vocab: ~12MB of asset
  // bytes need to be parsed before the first hunk-ranking can use them.
  // Fire-and-forget: the EngramRuntime singleton memoises the future,
  // so the first `await EngramRuntime.instance.assets()` inside the
  // diff prompt builder either finds them ready or waits on the same
  // load we kicked off here. Failure is silent — H_sym degrades to
  // pure Jaccard.
  EngramRuntime.instance.assets();

  final themeState = ThemeState();
  await themeState.load();

  final repoState = RepositoryState();
  await repoState.loadRecents();

  // Pre-warm the most-recently-used repo's LogosGit engine in the
  // background. By the time the user clicks through the repo picker
  // (or if they auto-land on the MRU), the engine's git-log walks,
  // engram file index, and graph build have already happened in
  // another isolate — what used to be a visible 1–2s repo-switch
  // latency becomes a ~50ms cache lookup.
  //
  // Fire-and-forget; never awaited on the main thread. Silent on
  // failure (network drive disappeared, repo deleted, corrupted
  // HEAD) — the user's first explicit interaction still works, it
  // just pays the cold cost then instead of getting the preload
  // discount.
  final mruRepo = repoState.recentPaths.isNotEmpty
      ? repoState.recentPaths.first
      : null;
  if (mruRepo != null) {
    logos_resolver.resolveLogosGit(mruRepo).then((_) {}, onError: (_) {});
  }
  final repoXrayState = RepositoryXrayState();
  final fileCouplingState = FileCouplingState();
  final symbolFrequencyState = SymbolFrequencyState();
  final logosGitState = LogosGitState();
  final worktreeState = WorktreeState(repoState);
  final deskPrState = DeskPrState(repoState, appIdentityState);
  final deskIssueState = DeskIssueState(repoState, appIdentityState);
  final remoteIssueCacheState = RemoteIssueCacheState(repoState);
  // Wire the cache so DeskIssueState's remote writes (promote/push) auto-
  // refresh the cache — keeps cross-cutting UI surfaces in sync.
  deskIssueState.attachRemoteCache(remoteIssueCacheState);

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
        ChangeNotifierProvider.value(value: fileCouplingState),
        ChangeNotifierProvider.value(value: symbolFrequencyState),
        ChangeNotifierProvider.value(value: logosGitState),
        ChangeNotifierProvider.value(value: worktreeState),
        ChangeNotifierProvider.value(value: deskPrState),
        ChangeNotifierProvider.value(value: deskIssueState),
        ChangeNotifierProvider.value(value: remoteIssueCacheState),
        ChangeNotifierProvider.value(value: preferencesState),
        ChangeNotifierProvider.value(value: aiSettingsState),
        ChangeNotifierProvider.value(value: diagnosticsState),
        ChangeNotifierProvider.value(value: appIdentityState),
        ChangeNotifierProvider.value(value: onboardingState),
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

    final onboardingComplete =
        context.select<OnboardingState, bool>((o) => o.isComplete);

    return MaterialApp(
      title: identity.shortName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(tokens),
      home: LiquidGlassProvider(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: onboardingComplete
              ? const _AppFrame(key: ValueKey('workspace'))
              : const OnboardingFlow(key: ValueKey('onboarding')),
        ),
      ),
    );
  }
}

class _AppFrame extends StatefulWidget {
  const _AppFrame({super.key});

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
                  // MaterialTextureLayer wraps in pulse subscription
                  // when the texture is iridescent — so the app-root
                  // backdrop gets the same time-drift + window-tilt
                  // parallax as per-surface iridescent passes. Other
                  // texture kinds (grain/scanlines/pixels/halftone)
                  // route through a plain CustomPaint, no overhead.
                  child: MaterialTextureLayer(
                    tokens: t,
                    shader: definition.shader,
                    blendMode: _rootTextureBlendMode(t),
                    opacityScale: _rootTextureOpacity(t),
                  ),
                ),
              ),
            if (t.id == AppThemeId.loverboy)
              Positioned.fill(
                child: IgnorePointer(
                  child: _LoveboyBackground(),
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
                              : t.accentBright.withValues(alpha: 0),
                        ),
                      ),
                    ),
                  ),
                ),
                const Expanded(child: WorkspaceShell()),
              ],
            ),
            // Brand lockup floats above all panels so the hypercube
            // never clips behind content during drag.
            const Positioned(
              left: 12,
              top: 12,
              child: IgnorePointer(
                ignoring: false,
                child: BrandLockup(),
              ),
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
    // Faint shimmer over the dark. Background is otherwise solid.
    AppThemeId.loverboy => 0.06,
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, WindowListener {
  late final AnimationController _controller;

  /// Delta from the first-captured window position. As the user drags the
  /// window around the screen, this tracks `current - base`. The painter
  /// uses it (scaled by `shader.parallaxStrength`) to shift particles
  /// opposite the drag, so they read as anchored in world-space rather
  /// than glued to the window — the "distant stars" depth illusion.
  final ValueNotifier<Offset> _windowDelta = ValueNotifier(Offset.zero);
  Offset? _baseWindowPos;
  /// Cached merged listenable for the AnimatedBuilder. Was being
  /// reallocated every build (which is every parent rebuild — and the
  /// parent is `_AppFrame`, which currently rebuilds on every theme
  /// notification). Refreshed only on shader-kind change.
  Listenable? _backdropSignal;

  // Redshift's `ThemeParticles.whisps` runs a tiny physics sim: up to 3
  // trailing ribbons drift around the backdrop in normalized coords, and
  // when any two heads come within a few percent of each other they
  // annihilate into a small debris burst that fades out over ~700ms.
  // All coords are [0, 1] so resolution/window changes don't affect
  // behavior. Sim updates are dt-based (wall clock), independent of the
  // controller's 0→1 cycle.
  final List<_Whisp> _whisps = [];
  final List<_Debris> _debris = [];
  // Time-seeded so each session reads as a fresh weather pattern instead
  // of the same three ribbons drifting the same paths every launch.
  final math.Random _simRng = math.Random();
  // Last edge a whisp spawned from. Re-roll if the next pick matches —
  // cheap way to keep ribbons feeling like they come from everywhere
  // instead of clustering on the same side.
  int _lastSpawnEdge = -1;
  DateTime? _lastSimAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    WindowActivity.instance.addListener(_syncAwake);
    _controller = AnimationController(
      vsync: this,
      duration: _particleAnimationDuration(widget.shader),
    );
    _controller.addListener(_tickSim);
    if (_particlesAnimate(widget.shader) && WindowActivity.instance.awake) {
      _controller.repeat();
    }
    _rebuildBackdropSignal();
    _captureBaseWindowPos();
  }

  /// Window-focus / minimize / lifecycle observer drives this. The N²
  /// whisp collision loop and blur-glow CustomPaint are pure background
  /// ornament — burning cycles on them while the user is looking at a
  /// different app is waste. Stop hard when the window loses focus;
  /// resume when it comes back.
  void _syncAwake() {
    if (!mounted) return;
    final shouldAnimate =
        _particlesAnimate(widget.shader) && WindowActivity.instance.awake;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  void _rebuildBackdropSignal() {
    _backdropSignal = _particlesAnimate(widget.shader)
        ? Listenable.merge([_controller, _windowDelta])
        : _windowDelta;
  }

  void _tickSim() {
    if (widget.shader.particles != ThemeParticles.whisps) return;
    final now = DateTime.now();
    final dt = _lastSimAt == null
        ? 0.016
        : now.difference(_lastSimAt!).inMicroseconds / 1e6;
    _lastSimAt = now;
    _simulateWhisps(dt.clamp(0.0, 0.05));
  }

  void _simulateWhisps(double dt) {
    // Maintain up to 3 whisps. Spawn at most one per frame so two
    // whisps dying together don't replace themselves in lockstep —
    // staggered births read as wind, not a metronome.
    if (_whisps.length < 3) {
      _whisps.add(_spawnWhisp());
    }
    for (final w in _whisps) {
      if (w.alive) w.update(dt, _simRng);
    }
    // Head-to-head collisions → annihilation + debris burst.
    for (var i = 0; i < _whisps.length; i++) {
      for (var j = i + 1; j < _whisps.length; j++) {
        final a = _whisps[i];
        final b = _whisps[j];
        if (!a.alive || !b.alive) continue;
        if ((a.head - b.head).distance < 0.04) {
          final mid = (a.head + b.head) / 2;
          for (var k = 0; k < 10; k++) {
            final angle = k * math.pi * 2 / 10 + _simRng.nextDouble() * 0.4;
            final speed = 0.25 + _simRng.nextDouble() * 0.2;
            _debris.add(_Debris(
              position: mid,
              velocity: Offset(math.cos(angle), math.sin(angle)) * speed,
            ));
          }
          a.alive = false;
          b.alive = false;
        }
      }
    }
    // One `pow()` call shared across every debris particle this tick —
    // was being called per-particle (10+ calls/frame) at ~20–50× the
    // cost of a multiply.
    final drag = math.pow(0.94, dt * 60).toDouble();
    for (final d in _debris) {
      d.update(dt, drag);
    }
    _whisps.removeWhere((w) => !w.alive || w.offScreen);
    _debris.removeWhere((d) => d.dead);
  }

  _Whisp _spawnWhisp() {
    // Spawn on a random edge, aim roughly inward with a bit of drift.
    // Avoid repeating the previous edge so consecutive whisps don't
    // pile in from the same side.
    var edge = _simRng.nextInt(4);
    if (edge == _lastSpawnEdge) edge = (edge + 1 + _simRng.nextInt(3)) % 4;
    _lastSpawnEdge = edge;
    // Bias cross-position into [0.15, 0.85] so whisps don't clip the
    // corners; corners are visually cramped and the ribbon barely shows
    // before exiting.
    final cross = 0.15 + _simRng.nextDouble() * 0.70;
    final baseSpeed = 0.08 + _simRng.nextDouble() * 0.12;
    Offset head;
    Offset velocity;
    switch (edge) {
      case 0: // top
        head = Offset(cross, -0.05);
        velocity = Offset(0, baseSpeed);
      case 1: // right
        head = Offset(1.05, cross);
        velocity = Offset(-baseSpeed, 0);
      case 2: // bottom
        head = Offset(cross, 1.05);
        velocity = Offset(0, -baseSpeed);
      default: // left
        head = Offset(-0.05, cross);
        velocity = Offset(baseSpeed, 0);
    }
    velocity = Offset(
      velocity.dx + (_simRng.nextDouble() - 0.5) * 0.06,
      velocity.dy + (_simRng.nextDouble() - 0.5) * 0.06,
    );
    return _Whisp(head: head, velocity: velocity);
  }

  Future<void> _captureBaseWindowPos() async {
    try {
      final pos = await windowManager.getPosition();
      if (!mounted) return;
      _baseWindowPos = pos;
    } catch (_) {
      // Non-desktop platforms or misconfigured environments — no parallax.
    }
  }

  // Throttle the native `getPosition()` round-trip. Window move events
  // fire at up to native event-loop rate (120+ Hz on fast drags), but
  // the parallax only needs to repaint once per frame. Skipping
  // redundant calls avoids the cost of an async platform channel
  // round-trip 60+ times per second during a single drag gesture.
  DateTime? _lastWindowMovePoll;
  bool _windowMoveInFlight = false;

  @override
  void onWindowMove() {
    if (_windowMoveInFlight) return;
    final now = DateTime.now();
    if (_lastWindowMovePoll != null &&
        now.difference(_lastWindowMovePoll!).inMilliseconds < 16) {
      return;
    }
    _lastWindowMovePoll = now;
    _windowMoveInFlight = true;
    // Fire-and-forget; the async round-trip updates the ValueNotifier
    // which drives the CustomPaint via AnimatedBuilder.
    () async {
      try {
        final pos = await windowManager.getPosition();
        if (!mounted) return;
        final base = _baseWindowPos ??= pos;
        _windowDelta.value = pos - base;
      } catch (_) {/* ignore */} finally {
        _windowMoveInFlight = false;
      }
    }();
  }

  @override
  void didUpdateWidget(covariant _ParticleBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration = _particleAnimationDuration(widget.shader);
    if (oldWidget.shader.particles != widget.shader.particles ||
        _controller.duration != duration) {
      _controller.duration = duration;
      if (_particlesAnimate(widget.shader) && WindowActivity.instance.awake) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
      // Particle-active state may have flipped; refresh the cached
      // listenable so the AnimatedBuilder picks up the controller
      // (or drops it when particles go quiet).
      _rebuildBackdropSignal();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lifecycle is already folded into [WindowActivity.awake]; defer to
    // the shared observer so the start/stop decision is made in exactly
    // one place, not split between two overlapping code paths.
    _syncAwake();
  }

  @override
  void dispose() {
    WindowActivity.instance.removeListener(_syncAwake);
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _windowDelta.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _backdropSignal!,
        builder: (context, _) => CustomPaint(
          painter: _ParticleBackdropPainter(
            tokens: widget.tokens,
            shader: widget.shader,
            progress:
                _particlesAnimate(widget.shader) ? _controller.value : 0,
            windowDelta: _windowDelta.value,
            whisps: _whisps,
            debris: _debris,
          ),
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
    case ThemeParticles.whisps:
    case ThemeParticles.inkblots:
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
    case ThemeParticles.whisps:
      // Whisps use their own wall-clock dt; controller just needs to
      // tick every frame. A short repeat cycle keeps the ticker alive.
      return const Duration(seconds: 10);
    case ThemeParticles.inkblots:
      // Slow drift across the page. Long period so blots glide rather
      // than zip — keeps the comic-book stillness while still moving.
      return const Duration(seconds: 45);
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
  /// Window-drag delta. Particles shift by `-windowDelta * parallaxStrength`
  /// so they feel anchored in world-space as the window moves — the
  /// "distant stars stay put" depth illusion.
  final Offset windowDelta;
  final List<_Whisp> whisps;
  final List<_Debris> debris;

  const _ParticleBackdropPainter({
    required this.tokens,
    required this.shader,
    required this.progress,
    this.windowDelta = Offset.zero,
    this.whisps = const [],
    this.debris = const [],
  });

  /// World-space offset applied to every particle layer.
  Offset get _parallaxOffset => -windowDelta * shader.parallaxStrength;

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
          offset: Offset(0, -1000 + 2000 * progress) + _parallaxOffset,
          drawTile: _drawVoidTile,
        );
      case ThemeParticles.voxels:
        _drawRepeatedTile(
          canvas,
          size,
          tileSize: 1000,
          opacity: 0.6,
          offset: Offset(0, -1000 + 2000 * progress) + _parallaxOffset,
          drawTile: _drawVoxelTile,
        );
      case ThemeParticles.chalkdust:
        _drawRepeatedTile(
          canvas,
          size,
          tileSize: size.shortestSide.clamp(760, 1500).toDouble(),
          opacity: 0.46,
          // Chalk dust shifts minimally — it's a near-field texture.
          offset: _parallaxOffset * 0.3,
          drawTile: _drawChalkTile,
        );
      case ThemeParticles.whisps:
        _drawWhisps(canvas, size);
      case ThemeParticles.inkblots:
        _drawInkblots(canvas, size);
    }
  }

  /// Kirby ambient — a handful of black ink blots drift across
  /// the cream paper. Each blot is a stable Path keyed by its index +
  /// progress, so positions move smoothly but shapes are constant.
  /// All blots share one Paint; total cost is ~6 path draws/frame.
  /// Color updated per call from `tokens.chromeBorder` so the blot ink
  /// stays in sync with the theme's panel-border ink line.
  static final Paint _inkblotPaint = Paint()..style = PaintingStyle.fill;
  // Reusable Path — `reset()`+rebuild each blot avoids allocating a
  // fresh `Path` per blot per frame. Same pattern as `edgePath` in
  // the timeline painter.
  static final Path _inkblotPath = Path();

  void _drawInkblots(Canvas canvas, Size size) {
    _inkblotPaint.color = tokens.chromeBorder.withValues(alpha: 0.05);
    const blots = 6;
    final w = size.width;
    final h = size.height;
    final base = progress; // 0..1 cycling once per controller period
    final parallax = _parallaxOffset * 0.4;
    for (var i = 0; i < blots; i++) {
      // Each blot has its own slow phase + horizontal lane. Wraps with
      // modulo so blots loop without snap.
      final phase = (base + i / blots) % 1.0;
      final lane = (i * 0.17 + 0.08) % 1.0;
      final cx = (lane * w) + parallax.dx + math.sin(phase * math.pi * 2) * 30;
      final cy = phase * (h + 80) - 40 + parallax.dy;
      final radius = 18.0 + (i % 3) * 6.0;
      // Hand-drawn-feeling blot: a circle nudged with two off-center
      // bumps via quadratic bezier. Stable shape per blot index.
      _inkblotPath
        ..reset()
        ..moveTo(cx + radius, cy)
        ..quadraticBezierTo(cx + radius * 1.2, cy - radius * 0.3,
            cx + radius * 0.4, cy - radius)
        ..quadraticBezierTo(cx - radius * 0.6, cy - radius * 1.1,
            cx - radius, cy - radius * 0.2)
        ..quadraticBezierTo(cx - radius * 1.1, cy + radius * 0.7,
            cx - radius * 0.3, cy + radius)
        ..quadraticBezierTo(cx + radius * 0.8, cy + radius * 1.0,
            cx + radius, cy)
        ..close();
      canvas.drawPath(_inkblotPath, _inkblotPaint);
    }
  }

  // Paints hoisted out of the inner loops — reused across every whisp
  // and debris particle per frame. Mutating `.shader`/`.color` on an
  // existing Paint is free; allocating new `Paint()` + `MaskFilter` on
  // every iteration was thrashing the GPU kernel cache.
  static final Paint _whispPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
  static final Paint _debrisPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);

  void _drawWhisps(Canvas canvas, Size size) {
    // Whisp ribbons: gradient from transparent red (tail) to bright
    // blue-white (head). Paint + MaskFilter are shared across iterations;
    // we only swap the gradient shader per whisp.
    final w0 = size.width;
    final h0 = size.height;
    for (final w in whisps) {
      final len = w.trail.length;
      if (len < 2) continue;
      final first = w.trail.first;
      final last = w.trail.last;
      final startPt = Offset(first.dx * w0, first.dy * h0);
      final endPt = Offset(last.dx * w0, last.dy * h0);
      final path = Path()..moveTo(startPt.dx, startPt.dy);
      // Build path directly from normalized coords — skipping the
      // intermediate List<Offset> allocation (~30 allocs per whisp).
      for (var i = 1; i < len; i++) {
        final p = w.trail[i];
        path.lineTo(p.dx * w0, p.dy * h0);
      }
      _whispPaint.shader = ui.Gradient.linear(
        startPt,
        endPt,
        const [
          Color(0x00FF2244),
          Color(0x59FF5566),
          Color(0xBF77DDFF),
        ],
        const [0.0, 0.55, 1.0],
      );
      canvas.drawPath(path, _whispPaint);
    }
    // Debris: small bright flashes decaying out. Drawn after whisps so
    // collision bursts read in front of any surviving trails nearby.
    for (final d in debris) {
      final a = d.life.clamp(0.0, 1.0);
      _debrisPaint.color = Color.fromRGBO(255, 240, 230, a * 0.75);
      canvas.drawCircle(
        Offset(d.position.dx * w0, d.position.dy * h0),
        1.2 + a * 2.2,
        _debrisPaint,
      );
    }
  }

  /// Per-layer parallax depth multiplier. Closer (visually bigger/brighter)
  /// layers shift MORE as the window moves — same physics as passing fence
  /// posts vs. distant mountains. Uniform parallax would look flat; this
  /// gives real depth.
  Offset _layerOffset(double depth) => _parallaxOffset * depth;

  void _drawStardustLayers(Canvas canvas, Size size) {
    // Depth multipliers rise with visual size/brightness: smallest stars
    // sit at infinity (barely move), the brightest foreground stars drift
    // the most as the window moves.
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 560,
      opacity: 0.4,
      offset: _layerOffset(0.4),
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 34, 0.14, 0.46, 89.4),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1940,
      opacity: 0.6,
      offset: _layerOffset(0.7),
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 28, 0.29, 0.66, 57.8),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1540,
      opacity: 0.6,
      offset: _layerOffset(1.0),
      drawTile: (tile, scale) =>
          _drawStardustTile(tile, scale, 20, 0.48, 1.04, 31.2),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1120,
      opacity: 0.6,
      offset: _layerOffset(1.4),
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
      offset: _layerOffset(0.4),
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 10, 0.22, 0.7, 72.9, 5, 290),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1700,
      opacity: 0.6,
      offset: _layerOffset(0.7),
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 14, 0.33, 0.84, 47.6, 4, 255),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 1320,
      opacity: 0.6,
      offset: _layerOffset(1.0),
      drawTile: (tile, scale) =>
          _drawQuantumTile(tile, scale, 20, 0.48, 1, 21.4, 3, 215),
    );
    _drawRepeatedTile(
      canvas,
      size,
      tileSize: 900,
      opacity: 0.6,
      offset: _layerOffset(1.4),
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
    final scale = tileSize / 1000;
    // ONE saveLayer around the entire grid for opacity modulation
    // instead of one per tile — 4–16 tile cells would otherwise each
    // allocate a full offscreen buffer per frame.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: opacity),
    );
    for (var x = startX; x < endX; x += tileSize) {
      for (var y = startY; y < endY; y += tileSize) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(scale);
        drawTile(canvas, scale);
        canvas.restore();
      }
    }
    canvas.restore();
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
      offset:
          Offset(-180 * progress, 120 * progress) + _layerOffset(0.5),
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
      offset: Offset(120 * progress, -840 * progress) + _layerOffset(0.9),
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
      offset:
          Offset(-90 * progress, -1220 * progress) + _layerOffset(1.3),
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
      (_particlesAnimate(shader) && oldDelegate.progress != progress) ||
      (shader.parallaxStrength > 0 &&
          oldDelegate.windowDelta != windowDelta);
}

class _SourceRandom {
  int _state;
  _SourceRandom(this._state);

  double next() {
    _state = (1664525 * _state + 1013904223) & 0xffffffff;
    return _state / 0xffffffff;
  }
}

// Tiny self-contained physics for the redshift backdrop. 3 ribbons drift
// in normalized [0,1] space; when any two heads come within ~4% of each
// other they annihilate into a burst of short-lived debris. All state
// lives in `_ParticleBackdropState`; these classes are plain data.

class _Whisp {
  Offset head;
  Offset velocity;
  final List<Offset> trail = [];
  bool alive = true;

  _Whisp({required this.head, required this.velocity});

  bool get offScreen =>
      head.dx < -0.15 ||
      head.dx > 1.15 ||
      head.dy < -0.15 ||
      head.dy > 1.15;

  void update(double dt, math.Random rng) {
    // Gentle curl so whisps don't just fly in straight lines — each axis
    // gets a small random nudge scaled by dt, giving the trails their
    // organic wander.
    velocity = Offset(
      velocity.dx + (rng.nextDouble() - 0.5) * 0.12 * dt,
      velocity.dy + (rng.nextDouble() - 0.5) * 0.12 * dt,
    );
    final speed = velocity.distance;
    // Clamp speed so curl never stalls a whisp or lets it rocket away.
    if (speed > 0.28) {
      velocity = velocity * (0.28 / speed);
    } else if (speed < 0.08) {
      velocity = velocity * (0.08 / speed);
    }
    head = head + velocity * dt;
    trail.add(head);
    if (trail.length > 30) {
      trail.removeAt(0);
    }
  }
}

class _Debris {
  Offset position;
  Offset velocity;
  double life = 1.0;

  _Debris({required this.position, required this.velocity});

  bool get dead => life <= 0;

  void update(double dt, double dragFactor) {
    position = position + velocity * dt;
    // Drag factor is precomputed per-frame in the simulator (one `pow()`
    // call shared across all particles in a tick) instead of paying the
    // math-library call per-particle.
    velocity = velocity * dragFactor;
    life -= dt * 1.5;
  }
}

/// Loverboy app-root cellular background. Subscribes to the
/// [LiquidGlassProvider] pulse so the shader's time + tilt uniforms
/// drive repaints in lockstep with the rest of the theme's parallax.
class _LoveboyBackground extends StatelessWidget {
  const _LoveboyBackground();

  @override
  Widget build(BuildContext context) {
    final pulse = LiquidGlassProvider.of(context);
    return RepaintBoundary(
      child: ValueListenableBuilder<LiquidGlassPulse>(
        valueListenable: pulse,
        builder: (_, value, __) => CustomPaint(
          painter: _LoveboyBgPainter(pulse: value),
        ),
      ),
    );
  }
}

class _LoveboyBgPainter extends CustomPainter {
  final LiquidGlassPulse pulse;
  const _LoveboyBgPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final fragShader = ThemeShaders.loveboyBgShader(
      width: size.width,
      height: size.height,
      intensity: 1.0,
      time: pulse.time,
      tiltX: pulse.tilt.dx,
      tiltY: pulse.tilt.dy,
    );
    if (fragShader == null) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = fragShader
        ..blendMode = BlendMode.srcOver,
    );
  }

  @override
  bool shouldRepaint(_LoveboyBgPainter old) =>
      old.pulse.time != pulse.time || old.pulse.tilt != pulse.tilt;
}
