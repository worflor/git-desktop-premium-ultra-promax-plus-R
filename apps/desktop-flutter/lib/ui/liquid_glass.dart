import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../app/window_activity.dart';

/// Per-frame state consumed by the liquid-glass fragment shader.
/// `time` is monotonic seconds; the shader uses sin/cos of it to drive
/// continuous "breathing" drift so glass surfaces stay alive when the
/// window is still. `tilt` is the window-position delta normalized to
/// roughly [-1, 1] per axis — a reflection-shift cue for when the user
/// drags the window across the screen.
@immutable
class LiquidGlassPulse {
  final double time;
  final Offset tilt;

  const LiquidGlassPulse({this.time = 0, this.tilt = Offset.zero});

  static const zero = LiquidGlassPulse();
}

/// Provides a `ValueListenable<LiquidGlassPulse>` to descendants. Glass
/// surfaces opt in by reading `LiquidGlassProvider.of(context)` and
/// wrapping their paint in an `AnimatedBuilder` against the listenable.
///
/// Cost is bounded: a single 30Hz Ticker drives `notifyListeners`, and
/// only subscribed surfaces repaint. Themes without glass mode never
/// touch this notifier so they pay nothing.
class LiquidGlassProvider extends StatefulWidget {
  final Widget child;
  const LiquidGlassProvider({super.key, required this.child});

  static ValueListenable<LiquidGlassPulse> of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_LiquidGlassScope>();
    return scope?.notifier ?? _stillNotifier;
  }

  // Fallback for callers below no provider (tests, isolated widgets).
  // A perpetually-still pulse so glass shaders still render, just frozen.
  static final ValueNotifier<LiquidGlassPulse> _stillNotifier =
      ValueNotifier<LiquidGlassPulse>(LiquidGlassPulse.zero);

  @override
  State<LiquidGlassProvider> createState() => _LiquidGlassProviderState();
}

class _LiquidGlassProviderState extends State<LiquidGlassProvider>
    with SingleTickerProviderStateMixin, WindowListener {
  late final Ticker _ticker;
  final ValueNotifier<LiquidGlassPulse> _pulse =
      ValueNotifier(LiquidGlassPulse.zero);

  Offset? _basePos;
  Offset _tilt = Offset.zero;
  Duration _accumulated = Duration.zero;
  Duration _lastTick = Duration.zero;

  // 30Hz update cadence. Glass drift is slow enough that anything past
  // this is wasted CPU + invalidations; halving the rate vs vsync also
  // halves repaint cost on screens full of glass surfaces.
  static const _tickInterval = Duration(milliseconds: 33);

  // 400px of window drag = full tilt magnitude. Past that we clamp.
  static const double _tiltSaturation = 400;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _ticker = createTicker(_onTick);
    if (WindowActivity.instance.awake) _ticker.start();
    WindowActivity.instance.addListener(_syncAwake);
  }

  /// Ride [WindowActivity] so the 30Hz pulse — which fans out to every
  /// glass surface in the tree — stops the instant the window loses
  /// focus / gets minimized. This kills the perpetual repaint storm
  /// across glass surfaces that the audit identified as a top idle-CPU
  /// contributor, without any behavior change for the focused case.
  void _syncAwake() {
    if (!mounted) return;
    final awake = WindowActivity.instance.awake;
    if (awake && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _accumulated = Duration.zero;
      _ticker.start();
    } else if (!awake && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    // Cold-start guard. `elapsed` is monotonic since the Ticker was
    // CREATED, so after a stop/start cycle the first tick can deliver a
    // multi-second delta, which would blow past [_tickInterval] on a
    // single frame and publish a jarring time jump to every glass
    // surface. Seed _lastTick on the first tick of a session and return.
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    _accumulated += delta;
    if (_accumulated < _tickInterval) return;
    _accumulated = Duration.zero;
    _pulse.value = LiquidGlassPulse(
      time: elapsed.inMicroseconds / 1e6,
      tilt: _tilt,
    );
  }

  @override
  void onWindowMove() {
    _refreshTilt();
  }

  Future<void> _refreshTilt() async {
    try {
      final pos = await windowManager.getPosition();
      if (!mounted) return;
      final base = _basePos ??= pos;
      final raw = pos - base;
      _tilt = Offset(
        (raw.dx / _tiltSaturation).clamp(-1.0, 1.0),
        (raw.dy / _tiltSaturation).clamp(-1.0, 1.0),
      );
    } catch (_) {/* non-desktop or platform error — leave tilt as-is */}
  }

  @override
  void dispose() {
    WindowActivity.instance.removeListener(_syncAwake);
    _ticker.dispose();
    windowManager.removeListener(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LiquidGlassScope(notifier: _pulse, child: widget.child);
}

class _LiquidGlassScope extends InheritedWidget {
  final ValueListenable<LiquidGlassPulse> notifier;
  const _LiquidGlassScope({required this.notifier, required super.child});

  @override
  bool updateShouldNotify(_LiquidGlassScope oldWidget) =>
      notifier != oldWidget.notifier;
}
