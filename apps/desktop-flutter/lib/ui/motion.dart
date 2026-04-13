import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/preferences_state.dart';

/// Central gating for the app's "Reduce motion" preference.
///
/// Rather than scatter `context.watch<PreferencesState>().reduceMotion`
/// across dozens of animated widgets, every animation in the app should
/// consult [BuildContextMotion] so a single pref flip silently collapses
/// durations, skips scroll animations, and stops repeating controllers.
///
/// Three entry points:
///   * `context.reduceMotion`        — subscribes; use inside build().
///   * `context.reduceMotionRead`    — one-shot read; use in callbacks.
///   * `context.motion(normal)`      — returns Duration.zero under reduce.
///   * `scrollCtrl.motionAnimateTo`  — falls back to jumpTo.
///   * `MotionSync` mixin            — keeps a repeating controller in sync
///                                     with the pref, reacting live to
///                                     toggles without the widget needing
///                                     its own listener plumbing.
extension BuildContextMotion on BuildContext {
  /// True when the user has enabled Reduce Motion. Subscribes — the widget
  /// rebuilds when the pref flips.
  bool get reduceMotion => watch<PreferencesState>().reduceMotion;

  /// One-shot read with no subscription. Safe to call in callbacks and
  /// outside build().
  bool get reduceMotionRead => read<PreferencesState>().reduceMotion;

  /// Returns [Duration.zero] under reduce-motion, otherwise [normal].
  /// Use for any `AnimatedX(duration: ...)` value.
  Duration motion(Duration normal) => reduceMotion ? Duration.zero : normal;

  /// As [motion], but without subscribing — for use in callbacks.
  Duration motionRead(Duration normal) =>
      reduceMotionRead ? Duration.zero : normal;
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
///
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<PreferencesState>();
    if (prefs != _prefsRef) {
      _prefsRef?.removeListener(_syncMotionLoops);
      prefs.addListener(_syncMotionLoops);
      _prefsRef = prefs;
    }
    _syncMotionLoops();
  }

  @override
  void dispose() {
    _prefsRef?.removeListener(_syncMotionLoops);
    super.dispose();
  }

  void _syncMotionLoops() {
    if (!mounted) return;
    final reduce = _prefsRef?.reduceMotion ?? false;
    final loops = motionLoops;
    final reverse = motionLoopReverse;
    for (var i = 0; i < loops.length; i++) {
      final c = loops[i];
      final doReverse = i < reverse.length && reverse[i];
      if (reduce) {
        if (c.isAnimating) c.stop();
        // Reset to a neutral value so the visual ends up at its idle pose
        // instead of frozen mid-animation.
        c.value = 0;
      } else {
        if (!c.isAnimating) c.repeat(reverse: doReverse);
      }
    }
  }
}
