import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/preferences_state.dart';
import '../app/window_activity.dart';

// Re-export the motion-off threshold so UI code can import just
// `motion.dart` and still reach the constant without a direct
// `preferences_state` dependency. Single source of truth lives in
// `preferences_state.dart`; this file re-surfaces it for the UI layer.
export '../app/preferences_state.dart' show kMotionRateOff;

/// Central gating for the app's motion preference. The user's "Reduce
/// motion" control now writes a continuous `motionRate` in [0, 2]:
///   * 0.0 — no motion (same effective behavior as the old boolean toggle)
///   * 1.0 — authored speed
///   * 2.0 — double-time
/// Rather than scatter `context.watch<PreferencesState>().motionRate`
/// across dozens of animated widgets, every animation in the app should
/// consult [BuildContextMotion] so a rate change silently rescales
/// durations, skips scroll animations at rate=0, and stops repeating
/// controllers.
/// Entry points:
///   * `context.motionRate` / `Read` — continuous scalar (subscribe / read).
///   * `context.reduceMotion` / `Read` — legacy boolean view (rate ≤ ε).
///   * `context.motion(normal)` — returns `normal / rate`, or zero at rate=0.
///   * `scrollCtrl.motionAnimateTo` — falls back to jumpTo under reduce.
///   * `MotionLoopSync` mixin — repeating controller stays in sync with
///     the pref, including running FASTER when rate > 1.
extension BuildContextMotion on BuildContext {
  /// Subscribed motion-rate scalar. Rebuild when the pref changes.
  double get motionRate => watch<PreferencesState>().motionRate;

  /// One-shot read with no subscription. Safe in callbacks / outside build().
  double get motionRateRead => read<PreferencesState>().motionRate;

  /// Legacy boolean view. True iff the rate is at or below the "off"
  /// threshold. Preserved so existing call sites continue to compile.
  bool get reduceMotion => watch<PreferencesState>().reduceMotion;

  /// As [reduceMotion] but without subscribing.
  bool get reduceMotionRead => read<PreferencesState>().reduceMotion;

  /// Scale a duration by the current motion rate. Rate=0 collapses to
  /// [Duration.zero] (the old reduce-motion behavior). Rate=1 is
  /// pass-through. Rate>1 shortens durations so the animation appears
  /// faster; rate<1 lengthens them.
  Duration motion(Duration normal) => _scale(normal, motionRate);

  /// As [motion], but without subscribing — for use in callbacks.
  Duration motionRead(Duration normal) => _scale(normal, motionRateRead);
}

Duration _scale(Duration normal, double rate) {
  // Rate ≤ 0 → no motion. Rate = 1 → exact pass-through (avoids a divide
  // that could introduce rounding drift at zoom-unity). Otherwise the
  // inverse: faster rate shortens the duration, slower stretches it.
  if (rate <= kMotionRateOff) return Duration.zero;
  if (rate == 1.0) return normal;
  final micros = (normal.inMicroseconds / rate).round();
  return Duration(microseconds: micros);
}

extension MotionScrollControllerExt on ScrollController {
  /// Scroll to [offset], falling back to an instant `jumpTo` when the user
  /// has reduce-motion enabled. Always awaitable.
  Future<void> motionAnimateTo(
    double offset, {
    required BuildContext context,
    required Duration duration,
    required Curve curve,
  }) {
    if (!hasClients) return Future.value();
    if (context.reduceMotionRead) {
      jumpTo(offset);
      return Future.value();
    }
    return animateTo(offset, duration: duration, curve: curve);
  }
}

/// Mixin for State<T> that owns a repeating [AnimationController] driving
/// constant motion (pulses, shimmers, idle loops).
/// Implementing states declare [motionLoops], a list of controllers that
/// should repeat while motion is allowed. The mixin subscribes to
/// [PreferencesState] and, on each pref change, either stops + resets the
/// controllers (reduce-motion on) or starts them repeating (off). No need
/// for per-widget listener boilerplate.
mixin MotionLoopSync<T extends StatefulWidget> on State<T> {
  PreferencesState? _prefsRef;

  /// Controllers that should `.repeat()` while motion is allowed.
  /// Implementers return them fresh on every call; the mixin does no
  /// caching of its own.
  List<AnimationController> get motionLoops;

  /// Optional `reverse` flag for each loop. Defaults to `false` (no reverse).
  /// Override to return a list of same length as [motionLoops].
  List<bool> get motionLoopReverse => const [];

  bool _windowListenerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesState>();
    if (prefs != _prefsRef) {
      _prefsRef?.removeListener(_syncMotionLoops);
      prefs.addListener(_syncMotionLoops);
      _prefsRef = prefs;
    }
    if (!_windowListenerAttached) {
      WindowActivity.instance.addListener(_syncMotionLoops);
      _windowListenerAttached = true;
    }
    _syncMotionLoops();
  }

  @override
  void dispose() {
    if (_windowListenerAttached) {
      WindowActivity.instance.removeListener(_syncMotionLoops);
    }
    _prefsRef?.removeListener(_syncMotionLoops);
    super.dispose();
  }

  void _syncMotionLoops() {
    if (!mounted) return;
    // Keyed off the scalar rate, not just the legacy bool. Rate ≤ ε means
    // "no motion" → stop + reset. Any positive rate means the loop should
    // be running. Per-controller duration scaling is left to the widget
    // (it knows the authored speed) — this mixin only toggles run/stop.
    //
    // WindowActivity folds in window-focus / minimize / lifecycle state,
    // so every consumer of MotionLoopSync (sidebar pulsing dots, shape
    // icons, progress sweeps, …) automatically stops its repeating
    // controller the instant the app window loses focus, and resumes on
    // re-focus. One gate, fan-out to every idle animation.
    final rate = _prefsRef?.motionRate ?? 1.0;
    final awake = WindowActivity.instance.awake;
    final reduce = rate <= kMotionRateOff || !awake;
    final loops = motionLoops;
    final reverse = motionLoopReverse;
    for (var i = 0; i < loops.length; i++) {
      final c = loops[i];
      final doReverse = i < reverse.length && reverse[i];
      if (reduce) {
        if (c.isAnimating) c.stop();
        // When window wakes back up the mixin will restart the loop.
        // Don't reset value to 0 on a transient window-blur — only when
        // reduce-motion is explicitly set, so we preserve the rotation
        // phase across an alt-tab.
        if (rate <= kMotionRateOff) c.value = 0;
      } else {
        if (!c.isAnimating) c.repeat(reverse: doReverse);
      }
    }
  }
}
