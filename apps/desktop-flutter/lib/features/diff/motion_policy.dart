import 'package:flutter/foundation.dart';

/// What an animation is trying to *communicate*. The policy maps intent to a
/// decision (play it, skip it, or soften it) based on user preferences.
/// Before this existed, every animation in the diff shell was a DIY
/// AnimationController or TweenAnimationBuilder with no shared layer to gate
/// it. `reduce-motion` was honoured by exactly one of six animations, and
/// every new animation had to remember to read the preference. Now each
/// animation declares an intent; the policy decides.
enum MotionIntent {
  /// A thing came on-screen for the first time (temperature reveal, sticky
  /// header fade-in). Ornament, not information — skipped under reduce-motion.
  reveal,

  /// A value transitioned from A to B (pair melt, edit-unit re-bind). The
  /// motion carries the semantic ("old became new"); under reduce-motion the
  /// final state appears directly without the in-between.
  transition,

  /// Feedback for a user action (stage toggle, hunk collapse). Always plays,
  /// but softened under reduce-motion so it registers as confirmation rather
  /// than as ornament.
  confirm,

  /// The shell needs the reader to notice something (temporal-mark pulse,
  /// restored cursor, error flash). Always plays; the whole point is to
  /// break visual scan.
  attention,

  /// Purely decorative (parallax ghost drift, ambient easing on scroll).
  /// First thing to go under reduce-motion.
  peripheral,
}

/// Central motion-gating policy. Holds the user's continuous motion-rate
/// scalar (from `PreferencesState.motionRate`). Rate 0 = no motion
/// (equivalent to the old boolean reduce-motion), rate 1 = authored,
/// rate > 1 speeds up, rate < 1 slows down. Pass through the widget
/// tree so every animation site consults the same decision.
@immutable
class MotionPolicy {
  final double rate;

  const MotionPolicy({required this.rate});

  /// Full-speed motion (rate 1.0). Used when no pref-mediated reduction
  /// applies AND the scroll-stress LOD isn't active.
  static const MotionPolicy full = MotionPolicy(rate: 1.0);

  /// No-motion instance (rate 0.0). Matches the legacy reduce-motion
  /// behavior: reveal/transition/peripheral intents skip, confirm and
  /// attention still play (scaled via [scale]).
  static const MotionPolicy reduced = MotionPolicy(rate: 0.0);

  /// Convenience: construct from the legacy boolean. Kept so call sites
  /// in flux during refactor don't break.
  const MotionPolicy.fromReduceMotion(bool reduceMotion)
      : rate = reduceMotion ? 0.0 : 1.0;

  /// True iff the rate has collapsed to "no motion". Single source of
  /// truth for the `reveal/transition/peripheral` gate and all per-row
  /// skip logic.
  bool get reduceMotion => rate <= 0.0001;

  /// Returns true when an animation of this intent should actually play.
  /// Callers that are false-returning should render the final state
  /// directly (no zero-duration tween — that still schedules a frame and
  /// confuses telemetry).
  bool allow(MotionIntent intent) {
    if (!reduceMotion) return true;
    switch (intent) {
      case MotionIntent.confirm:
      case MotionIntent.attention:
        return true;
      case MotionIntent.reveal:
      case MotionIntent.transition:
      case MotionIntent.peripheral:
        return false;
    }
  }

  /// Scale a duration by the current motion rate. Rate ≤ ε collapses to
  /// a short fixed duration (45% of authored) so reduce-motion users still
  /// get a brief, perceptible "something happened" confirmation when an
  /// [MotionIntent.confirm] or [MotionIntent.attention] animation slips
  /// through the allow() gate. Rate = 1 is exact pass-through. Rate > 1
  /// shortens (faster); rate < 1 stretches (slower).
  Duration scale(Duration d) {
    if (reduceMotion) {
      // Soft floor for animations that still play under reduce-motion.
      return Duration(milliseconds: (d.inMilliseconds * 0.45).round());
    }
    if (rate == 1.0) return d;
    return Duration(microseconds: (d.inMicroseconds / rate).round());
  }

  @override
  bool operator ==(Object other) =>
      other is MotionPolicy && other.rate == rate;
  @override
  int get hashCode => rate.hashCode;
}
