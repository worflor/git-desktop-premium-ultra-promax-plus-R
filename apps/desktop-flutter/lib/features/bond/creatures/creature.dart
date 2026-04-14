// ═════════════════════════════════════════════════════════════════════════
// features/bond/creatures/creature.dart — modular creature framework
//
// Designed so jump-cuts are impossible by construction:
//
//   1. [BondCreatureClock] — single process-wide monotonic clock.
//      Every creature reads `now` from here. Widget rebuilds, page
//      navigations, and repo switches don't reset time because no
//      widget owns it.
//
//   2. [BondCreatureRuntime] — mutable continuous state lives on
//      the creature *type*, not the widget. There's exactly one
//      runtime per [BondCreature] subtype (keyed by `runtimeType`),
//      living in a static map for the app's lifetime. Widgets are
//      thin renderers that point at the runtime; remounting one
//      doesn't drop the runtime's state.
//
//   3. Signals + openness ease via half-life decay toward their
//      targets, never snap. Targets can change instantly (e.g. a
//      different repo's dirty count); the runtime catches up
//      smoothly with frame-rate-independent timing.
//
//   4. The widget's [Ticker] is a frame-pump; it has no time of its
//      own. It just asks the runtime to tick and the painter to
//      redraw. Multiple widgets pointing at the same creature share
//      a runtime, so the strip's asleep fox and the drawer header's
//      awake fox are literally the same moving creature.
//
// All animation primitives ([Oscillator], [Beat]) sample the clock,
// not a per-widget elapsed time — so a sleeping fox that wakes up
// continues phase rather than restarting.
// ═════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// ═════════════════════════════════════════════════════════════════════════
// Clock — global monotonic time

/// Single source of truth for "what time is it" across every
/// creature in the process. Built on [Stopwatch] (microsecond
/// monotonic, immune to wallclock skew) so there are no leap-second
/// or NTP-step surprises during long sessions.
class BondCreatureClock {
  static final Stopwatch _sw = Stopwatch()..start();

  /// Continuous seconds since process start. Always-increasing,
  /// always-defined. Read from anywhere; never reset.
  static double get seconds => _sw.elapsedMicroseconds / 1e6;
}

// ═════════════════════════════════════════════════════════════════════════
// Mood + signals

enum BondCreatureMood { asleep, waking, awake }

/// Signals derived from the host context (repo state, user activity)
/// and pushed at the creature as *targets*. The runtime eases its
/// internal value toward the target; the painter only ever sees the
/// smoothed value, never the raw input.
@immutable
class BondCreatureSignals {
  const BondCreatureSignals({
    this.excitement = 0,
    this.attention = 0,
    this.restlessness = 0,
    this.lastEventMs,
    this.lastPetMs,
    this.goal,
    this.cursor,
    this.windowFocused = true,
    this.userIdle = false,
  });

  final double excitement;
  final double attention;
  final double restlessness;
  final int? lastEventMs;

  /// Timestamp of the last "pet" interaction (user held pointer on
  /// the creature's pen). Triggers a one-shot affection response —
  /// tail curl, slow blink, contented breath — distinct from the
  /// commit-event flourish. Null = never petted.
  final int? lastPetMs;

  /// Where in pen-normalised space (0..1, 0..1) the host wants the
  /// creature to drift toward. Null = no specific destination,
  /// creature picks its own idle orbit. Re-evaluated every frame
  /// by the host — useful for "follow the chevron" / "look at the
  /// hovered button" style behaviours derived from real layout
  /// positions, not magic numbers.
  final Offset? goal;

  /// User's mouse position in pen-normalised coords when the cursor
  /// is inside a tracked region. Null = cursor is elsewhere / not
  /// being tracked. Drives eye gaze and the rare "look at you" —
  /// the creature acknowledges the actual user, not a fake signal.
  final Offset? cursor;

  /// Whether the host application window has OS-level focus. False
  /// means the user is looking at something else; creature dims,
  /// breathes slower, curls a touch. Reads as living inside the
  /// window rather than painted on it.
  final bool windowFocused;

  /// True when the user hasn't moved the mouse anywhere in the
  /// window for a while (~20s). Meta beats (look-around, notice-you)
  /// only fire when this is true — so they never pull focus while
  /// the user is actively working, only when the fox has a chance
  /// to actually be noticed.
  final bool userIdle;

  static const empty = BondCreatureSignals();
}

@immutable
class BondCreatureFrame {
  const BondCreatureFrame({
    required this.mood,
    required this.timeSeconds,
    required this.openness,
    required this.stroke,
    required this.accent,
    required this.muted,
    required this.strokeWidth,
    required this.signals,
    required this.position,
    required this.facing,
    required this.cursor,
    required this.cursorPresence,
    required this.focus,
  });

  /// Authoritative mood — the *target*, not the smoothed value.
  /// Use [openness] for "how awake right now"; use [mood] for
  /// branching behaviour that doesn't need to interpolate (e.g.
  /// "is the creature *currently* in the asleep regime").
  final BondCreatureMood mood;

  /// Wallclock seconds (continuous, monotonic). Animators sample
  /// this rather than a widget-lifetime offset.
  final double timeSeconds;

  /// 0 = fully asleep, 1 = fully awake. Eased smoothly via the
  /// runtime; never snaps even when the mood input flips
  /// instantaneously.
  final double openness;

  final Color stroke;
  final Color accent;
  final Color muted;
  final double strokeWidth;

  /// **Smoothed** signals — eased values from the runtime, not raw
  /// targets. Painters use these directly without further easing.
  final BondCreatureSignals signals;

  /// Smoothed pen-normalised anchor position. Painters draw the
  /// creature centred here; ambient micro-orbit is the painter's
  /// own concern (small Lissajous on top of this).
  final Offset position;

  /// Smoothed facing in [-1, 1]. Painters mirror x via
  /// `canvas.scale(facing.sign * |facing|, 1)` — when the value
  /// crosses zero the wire visually folds vertical and unfolds the
  /// other way (the canonical hyperfold flip).
  final double facing;

  /// Smoothed gaze target (pen-normalised). When [cursorPresence]
  /// > 0 the painter should bias eye/head features toward this
  /// point. Reads as the creature actually noticing the mouse.
  final Offset cursor;

  /// How strongly the gaze should bend toward [cursor]. 0 = ignore
  /// it (cursor is away); 1 = fully tracked. Eased, so leaving the
  /// pen releases gaze back to neutral instead of snapping.
  final double cursorPresence;

  /// Host window focus, smoothed (0..1). Painters can dim / curl
  /// when focus drops — the creature goes a little sleepy when the
  /// user alt-tabs away. Separate from [BondCreatureMood] so a
  /// focused-but-asleep fox is distinct from an unfocused awake fox.
  final double focus;
}

// ═════════════════════════════════════════════════════════════════════════
// Runtime — continuous state owned per creature subtype

/// Per-creature mutable state. One instance per [BondCreature]
/// subtype, lives for the app's lifetime. All easing happens here
/// so widget mounts/unmounts are invisible to the painted output.
class BondCreatureRuntime {
  BondCreatureRuntime();

  /// Smoothed signals — what the painter actually sees.
  BondCreatureSignals signals = BondCreatureSignals.empty;

  /// Smoothed openness 0..1.
  double openness = 0;

  /// Smoothed pen-normalised position (0..1, 0..1). Where the
  /// creature *thinks* it is. Eased toward the current goal; the
  /// painter draws the body around this point. Painters can still
  /// add their own micro-orbit (Lissajous etc) as a small
  /// perturbation around this anchor.
  Offset position = const Offset(0.5, 0.5);

  /// Smoothed facing in [-1, 1]. **Convention:** +1 = facing right
  /// (moving toward +x), -1 = facing left. Derived from actual
  /// position velocity each tick, not from a host hint — a
  /// creature always faces where it's going, like any game
  /// character. Crosses zero smoothly so the canvas-x mirror
  /// produces a clean fold-and-flip rather than a snap.
  double facing = 1.0;

  /// Sticky target for the eased [facing] value. Only updated when
  /// the creature has meaningful x-velocity — below that threshold
  /// we *hold* heading rather than letting micro-jitter from the
  /// Lissajous orbit flip the creature every frame.
  double _facingTarget = 1.0;

  /// Threshold (pen-widths per second) for the velocity-fallback
  /// facing update. Only fires when no goal/cursor intent exists —
  /// goal-directed facing handles the common case already. Lowered
  /// so even gentle ambient drift eventually resolves a heading.
  static const double _facingVelocityEpsilon = 0.08;

  /// Smoothed cursor position in pen-normalised coords. The creature
  /// gazes here — eye pupil shifts toward this point. Decoupled from
  /// [BondCreatureSignals.cursor] so gaze lags the real cursor by a
  /// human-feeling amount (not dart-precise tracking).
  Offset cursor = const Offset(0.5, 0.5);

  /// How "present" the cursor is (0..1). Eased toward 1 when the
  /// host reports a cursor position, toward 0 when null. Makes the
  /// eye gently return to centre instead of snapping home when the
  /// mouse leaves the pen.
  double cursorPresence = 0;

  /// Smoothed window-focus state (0 = fully unfocused, 1 = focused).
  /// Painters dim / curl proportionally.
  double focus = 1.0;

  static const double _cursorHalfLife = 0.18;
  static const double _focusHalfLife = 0.35;

  /// Last [BondCreatureClock.seconds] we ticked at. Negative on
  /// first-ever tick so the runtime can snap to the input target
  /// instead of fading in from zero (avoids a "creature appears
  /// from nothing" flash on cold start).
  double _lastTickSec = -1;

  /// Half-life seconds for each axis — tuned so transient signals
  /// (attention, excitement) snap fast and slow ones (restlessness)
  /// drift. Openness, position, and facing use their own constants.
  static const double _excitementHalfLife = 0.30;
  static const double _attentionHalfLife = 0.20;
  static const double _restlessnessHalfLife = 1.00;
  static const double _opennessHalfLife = 0.12;
  // Position drifts gently — fast enough to feel intentional when
  // a goal pulls, slow enough not to dart.
  static const double _positionHalfLife = 0.40;
  // Facing flips deliberately — slow enough that the wire-fold is
  // visible, fast enough to read as an intentional turn rather than
  // a lag. Paired with alignment-gated travel (below) so the body
  // only commits to pursuit once the head has committed to a
  // heading.
  static const double _facingHalfLife = 0.20;
  // Default rest position — centre of the pen if the host gives
  // no goal. Painter adds its own micro-orbit on top.
  static const Offset _restPosition = Offset(0.5, 0.5);

  /// Pull the runtime forward in time toward the given targets.
  /// Called from the widget's per-frame Ticker. Idempotent for the
  /// same `now` value (dt = 0 → no change).
  void tick(
    double now,
    BondCreatureMood targetMood,
    BondCreatureSignals target,
  ) {
    if (_lastTickSec < 0) {
      // Cold start — snap to target so the first paint isn't a
      // fade-in from black on app launch / first creature mount.
      signals = target;
      openness = (targetMood == BondCreatureMood.asleep) ? 0.0 : 1.0;
      position = target.goal ?? _restPosition;
      // Cold-start facing: aim toward goal if one is set (so we
      // don't boot facing the wrong way before the first velocity
      // sample); otherwise keep the default.
      if (target.goal != null) {
        final toward = target.goal!.dx - 0.5;
        if (toward.abs() > 0.01) {
          _facingTarget = toward > 0 ? 1.0 : -1.0;
          facing = _facingTarget;
        }
      }
      cursor = target.cursor ?? const Offset(0.5, 0.5);
      cursorPresence = target.cursor != null ? 1.0 : 0.0;
      focus = target.windowFocused ? 1.0 : 0.0;
      _lastTickSec = now;
      return;
    }
    var dt = now - _lastTickSec;
    if (dt <= 0) return;
    // Cap dt to protect against backgrounded-tab "huge dt" jumps
    // (Flutter doesn't tick when the surface isn't visible; on
    // resume the first dt would be enormous and cause an actual
    // jump-cut as everything teleports to its target). 100ms cap
    // means a worst-case "missed frame" still eases visibly.
    if (dt > 0.1) dt = 0.1;
    _lastTickSec = now;
    signals = _easeSignals(signals, target, dt);
    final moodTarget =
        (targetMood == BondCreatureMood.asleep) ? 0.0 : 1.0;
    openness = _ease(openness, moodTarget, dt, _opennessHalfLife);

    // ── Facing intent: look *before* you go ────────────────────
    // Game-character priority ladder:
    //   1. Goal direction (turn toward the destination before
    //      the body starts travelling — no more ass-first drift
    //      on short hops where velocity stays under threshold).
    //   2. Cursor attention (idle creature notices a hovering
    //      user and faces them — no magic, just awareness).
    //   3. Velocity fallback (for purely reactive drift).
    //   4. Hold last heading.
    final goal = target.goal ?? _restPosition;
    final goalDx = goal.dx - position.dx;
    double? desiredFacing;
    if (target.goal != null && goalDx.abs() > 0.04) {
      desiredFacing = goalDx > 0 ? 1.0 : -1.0;
    } else if (target.cursor != null) {
      final cursorDx = target.cursor!.dx - position.dx;
      // Wide dead-zone so the creature doesn't twitch at every
      // micro-jitter of the mouse. Only commits a turn when the
      // cursor is clearly to one side.
      if (cursorDx.abs() > 0.18) {
        desiredFacing = cursorDx > 0 ? 1.0 : -1.0;
      }
    }
    if (desiredFacing != null) {
      _facingTarget = desiredFacing;
    }

    // ── Alignment-gated pursuit ────────────────────────────────
    // Travel speed scales with how well the *current* facing is
    // aligned with the intent. Facing wrong way → crawl (turning
    // in place while the wire folds through 4D). Facing right →
    // full speed. This is what sells the "look then move" motion.
    final alignment = (facing * _facingTarget).clamp(-1.0, 1.0);
    final alignGate = (0.5 * (alignment + 1)).clamp(0.0, 1.0);
    // 0.20..1.00 — hard floor keeps creature from freezing mid-turn
    // if the ease lands pathologically at facing=0.
    final pursuitGate = 0.20 + 0.80 * alignGate;
    final posHalfLife = _positionHalfLife / pursuitGate;

    final nextPosition = Offset(
      _ease(position.dx, goal.dx, dt, posHalfLife),
      _ease(position.dy, goal.dy, dt, posHalfLife),
    );

    // Velocity-derived facing — only as a tie-breaker when no
    // explicit intent was found above. Keeps the creature from
    // being facing-less if it's just idling with ambient drift.
    if (desiredFacing == null) {
      final vx = (nextPosition.dx - position.dx) / dt;
      if (vx.abs() > _facingVelocityEpsilon) {
        _facingTarget = vx > 0 ? 1.0 : -1.0;
      }
    }

    position = nextPosition;
    facing = _ease(facing, _facingTarget, dt, _facingHalfLife);
    // Cursor gaze — ease toward the current cursor if present, else
    // toward pen centre. Presence eases on a separate track so the
    // eye's "looking at nothing" recenter is smooth even when the
    // last known cursor position is far from centre.
    final cursorTarget = target.cursor ?? const Offset(0.5, 0.5);
    cursor = Offset(
      _ease(cursor.dx, cursorTarget.dx, dt, _cursorHalfLife),
      _ease(cursor.dy, cursorTarget.dy, dt, _cursorHalfLife),
    );
    cursorPresence = _ease(
      cursorPresence,
      target.cursor != null ? 1.0 : 0.0,
      dt,
      _cursorHalfLife,
    );
    focus = _ease(focus, target.windowFocused ? 1.0 : 0.0, dt, _focusHalfLife);
  }

  static BondCreatureSignals _easeSignals(
    BondCreatureSignals from,
    BondCreatureSignals to,
    double dt,
  ) {
    return BondCreatureSignals(
      excitement: _ease(from.excitement, to.excitement, dt, _excitementHalfLife),
      attention: _ease(from.attention, to.attention, dt, _attentionHalfLife),
      restlessness:
          _ease(from.restlessness, to.restlessness, dt, _restlessnessHalfLife),
      // Event timestamps are discrete signals — they shouldn't
      // ease (the event happened or it didn't). The latest target
      // wins; the painter handles event decay via its own time
      // math.
      lastEventMs: to.lastEventMs ?? from.lastEventMs,
      lastPetMs: to.lastPetMs ?? from.lastPetMs,
      // Idle-flag is a discrete boolean — pass through directly.
      // Cursor/window fields are handled outside this helper.
      userIdle: to.userIdle,
    );
  }

  /// Frame-rate-independent half-life ease. After [halfLife]
  /// seconds, the gap closes by 50%. Independent of how many
  /// intermediate ticks fired.
  static double _ease(double from, double to, double dt, double halfLife) {
    if (from == to) return to;
    final k = math.pow(0.5, dt / halfLife).toDouble();
    return to + (from - to) * k;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Animator primitives — pure functions of clock seconds

class Oscillator {
  const Oscillator({required this.periodSeconds, this.phase = 0});
  final double periodSeconds;
  final double phase;
  double sample(double t) =>
      math.sin(((t / periodSeconds) + phase) * 2 * math.pi);
}

class Beat {
  const Beat({
    required this.intervalSeconds,
    required this.durationSeconds,
    this.phase = 0,
  });
  final double intervalSeconds;
  final double durationSeconds;
  final double phase;

  double sample(double t) {
    final cycle = (t / intervalSeconds) + phase;
    final inCycle = (cycle - cycle.floor()) * intervalSeconds;
    if (inCycle >= durationSeconds) return 0;
    final half = durationSeconds / 2;
    return inCycle < half
        ? inCycle / half
        : (durationSeconds - inCycle) / half;
  }
}

double easeOut(double t) {
  final c = t.clamp(0.0, 1.0);
  return 1 - (1 - c) * (1 - c);
}

double lerp(double a, double b, double t) => a + (b - a) * t;

// ═════════════════════════════════════════════════════════════════════════
// BondCreature — abstract base, owns its runtime

abstract class BondCreature {
  const BondCreature();

  /// One [BondCreatureRuntime] per creature subtype. A const
  /// `FoxCreature()` instance and another const `FoxCreature()`
  /// instance share the same runtime — they're the same animal.
  /// Runtime survives every widget mount/unmount.
  static final Map<Type, BondCreatureRuntime> _runtimes = {};

  BondCreatureRuntime get runtime =>
      _runtimes.putIfAbsent(runtimeType, BondCreatureRuntime.new);

  void paint(Canvas canvas, Rect pen, BondCreatureFrame frame);

  double get aspectRatio => 2.5;
}

// ═════════════════════════════════════════════════════════════════════════
// Widget — thin renderer pointing at the creature's runtime

class BondCreatureWidget extends StatefulWidget {
  const BondCreatureWidget({
    super.key,
    required this.creature,
    required this.mood,
    required this.stroke,
    required this.accent,
    required this.muted,
    this.signals = BondCreatureSignals.empty,
    this.height = 18,
  });

  final BondCreature creature;
  final BondCreatureMood mood;
  final Color stroke;
  final Color accent;
  final Color muted;
  final BondCreatureSignals signals;
  final double height;

  @override
  State<BondCreatureWidget> createState() => _BondCreatureWidgetState();
}

class _BondCreatureWidgetState extends State<BondCreatureWidget>
    with SingleTickerProviderStateMixin {
  // Single ticker; conditionally active. Frame-pump only — time and
  // continuous state live in the creature runtime, not here.
  late final Ticker _ticker = createTicker(_onTick);

  /// We keep ticking while:
  ///   • creature is awake / waking, OR
  ///   • the runtime hasn't yet reached its mood target (eased
  ///     openness still moving), OR
  ///   • the runtime hasn't settled on its signal targets (any
  ///     axis still mid-ease), OR
  ///   • a recent event timestamp still has decay budget left.
  /// All four conditions are functions of runtime state, so the
  /// widget can decide to stop the ticker without losing anything.
  static const double _kEventDecaySeconds = 1.5;
  static const double _kSignalEpsilon = 0.001;

  @override
  void initState() {
    super.initState();
    // Run one synchronous tick at mount so the runtime cold-start
    // path fires before the first paint. Avoids a one-frame
    // "openness=0 even though we want awake" flash on first mount.
    widget.creature.runtime.tick(
      BondCreatureClock.seconds,
      widget.mood,
      widget.signals,
    );
    _ticker.start();
  }

  @override
  void didUpdateWidget(BondCreatureWidget old) {
    super.didUpdateWidget(old);
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration _) {
    final now = BondCreatureClock.seconds;
    widget.creature.runtime.tick(now, widget.mood, widget.signals);
    final r = widget.creature.runtime;
    final moodTargetOpenness =
        widget.mood == BondCreatureMood.asleep ? 0.0 : 1.0;
    final opennessSettled =
        (r.openness - moodTargetOpenness).abs() < _kSignalEpsilon;
    final signalsSettled =
        (r.signals.excitement - widget.signals.excitement).abs() <
                _kSignalEpsilon &&
            (r.signals.attention - widget.signals.attention).abs() <
                _kSignalEpsilon &&
            (r.signals.restlessness - widget.signals.restlessness).abs() <
                _kSignalEpsilon;
    // Position + facing also need to be settled before we can stop —
    // otherwise a goal change while asleep would freeze mid-glide.
    final goalTarget = widget.signals.goal ?? const Offset(0.5, 0.5);
    final positionSettled =
        (r.position.dx - goalTarget.dx).abs() < _kSignalEpsilon &&
            (r.position.dy - goalTarget.dy).abs() < _kSignalEpsilon;
    // Facing is now velocity-derived in the runtime — it's settled
    // whenever the smoothed value has caught up with its sticky
    // target (i.e. the creature isn't mid-turn).
    final facingSettled = (r.facing - r._facingTarget).abs() < _kSignalEpsilon;
    // Gaze/focus convergence — keeps the ticker alive while the eye
    // is still easing toward (or away from) the cursor, and while
    // the window is mid focus-transition.
    final cursorTarget = widget.signals.cursor ?? const Offset(0.5, 0.5);
    final presenceTarget = widget.signals.cursor != null ? 1.0 : 0.0;
    final cursorSettled =
        (r.cursor.dx - cursorTarget.dx).abs() < _kSignalEpsilon &&
            (r.cursor.dy - cursorTarget.dy).abs() < _kSignalEpsilon &&
            (r.cursorPresence - presenceTarget).abs() < _kSignalEpsilon;
    final focusTarget = widget.signals.windowFocused ? 1.0 : 0.0;
    final focusSettled = (r.focus - focusTarget).abs() < _kSignalEpsilon;
    final lastEvent = r.signals.lastEventMs;
    final eventStillAlive = lastEvent != null &&
        (DateTime.now().millisecondsSinceEpoch - lastEvent) <
            (_kEventDecaySeconds * 1000);
    // Unfocused = "empty room" → don't keep pumping frames just to
    // breathe while nobody's watching. When the window loses focus
    // we stop treating awake/waking as a reason to stay ticking;
    // the run-down settle check below still fires any pending ease
    // (including focus → 0) before the ticker stops.
    final stayAwakeForMotion = (widget.mood == BondCreatureMood.awake ||
            widget.mood == BondCreatureMood.waking) &&
        widget.signals.windowFocused;
    if (!stayAwakeForMotion &&
        opennessSettled &&
        signalsSettled &&
        positionSettled &&
        facingSettled &&
        cursorSettled &&
        focusSettled &&
        !eventStillAlive) {
      // Nothing more to draw. Stop pumping frames; will resume on
      // next didUpdateWidget (mood/signal change).
      _ticker.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.creature.runtime;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if (w.isInfinite || w <= 0) return const SizedBox.shrink();
          final stroke = (widget.height / 14).clamp(0.8, 1.6);
          final pen = Rect.fromLTWH(0, 0, w, widget.height);
          return CustomPaint(
            size: Size(w, widget.height),
            painter: _CreatureCanvas(
              creature: widget.creature,
              frame: BondCreatureFrame(
                mood: widget.mood,
                timeSeconds: BondCreatureClock.seconds,
                openness: r.openness,
                stroke: widget.stroke,
                accent: widget.accent,
                muted: widget.muted,
                strokeWidth: stroke,
                signals: r.signals,
                position: r.position,
                facing: r.facing,
                cursor: r.cursor,
                cursorPresence: r.cursorPresence,
                focus: r.focus,
              ),
              pen: pen,
            ),
          );
        },
      ),
    );
  }
}

class _CreatureCanvas extends CustomPainter {
  _CreatureCanvas({
    required this.creature,
    required this.frame,
    required this.pen,
  });

  final BondCreature creature;
  final BondCreatureFrame frame;
  final Rect pen;

  @override
  void paint(Canvas canvas, Size size) {
    creature.paint(canvas, pen, frame);
  }

  @override
  bool shouldRepaint(_CreatureCanvas old) =>
      // The widget calls setState every Ticker tick, which already
      // triggers a paint. shouldRepaint is here to short-circuit
      // setState calls that arrive without state changes (rare,
      // but cheap to handle).
      old.frame.timeSeconds != frame.timeSeconds ||
      old.frame.openness != frame.openness ||
      old.frame.position != frame.position ||
      old.frame.facing != frame.facing ||
      old.frame.cursor != frame.cursor ||
      old.frame.cursorPresence != frame.cursorPresence ||
      old.frame.focus != frame.focus ||
      old.frame.signals.excitement != frame.signals.excitement ||
      old.frame.signals.attention != frame.signals.attention ||
      old.frame.signals.restlessness != frame.signals.restlessness ||
      old.frame.signals.lastEventMs != frame.signals.lastEventMs ||
      old.frame.stroke != frame.stroke ||
      old.frame.accent != frame.accent ||
      old.pen != pen;
}
