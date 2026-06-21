// easter_eggs.dart — discovered delights.
//
// An easter egg is a hidden effect that activates on a TRIGGER (a magic name;
// later: a key sequence, a calendar moment) and floats over the app as a
// pointer-transparent overlay. Unlike themes, you don't pick eggs from a menu —
// you stumble into them. So the system is deliberately a thin pure-function
// trigger map + an overlay renderer, decoupled from the theme machinery.
// Adding the next egg is exactly three edits: one [EasterEgg] value, one case
// in [resolveEasterEgg], one branch in [EasterEggOverlay]. Nothing else.
//
// First resident: winton 🍌. Name your Manifold "winton" and bananas drift in.
// (Winston's a gorilla, the plush is his — the bananas are everyone's.)

import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../app/app_identity.dart';
import '../app/preferences_state.dart';

/// The currently-active easter egg. Add a value, a trigger in
/// [resolveEasterEgg], and a renderer branch in [EasterEggOverlay].
enum EasterEgg { none, winton }

/// Pure trigger resolution from the app's observable signals. Pure so eggs are
/// trivially testable and the "what unlocks what" knowledge lives in one place.
EasterEgg resolveEasterEgg({required String appName}) {
  switch (appName.trim().toLowerCase()) {
    case 'winton':
      return EasterEgg.winton;
    default:
      return EasterEgg.none;
  }
}

/// Wraps the app root. When an egg is active it overlays the effect above the
/// UI (pointer-transparent); otherwise it returns [child] untouched — no Stack,
/// no painter, zero overhead on the common path.
class EasterEggOverlay extends StatelessWidget {
  final Widget child;
  const EasterEggOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final egg = resolveEasterEgg(
      appName:
          context.select<AppIdentityState, String>((s) => s.identity.shortName),
    );
    if (egg == EasterEgg.none) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: switch (egg) {
            EasterEgg.winton => const _WintonBananaField(),
            EasterEgg.none => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

// ─── winton 🍌 ───────────────────────────────────────────────────────────────

/// A gentle, always-on shower of tumbling bananas. Cheap (only alive while the
/// app is literally named "winton") and TickerMode-muted when the window is
/// hidden, like every other animation in the app.
class _WintonBananaField extends StatefulWidget {
  const _WintonBananaField();

  @override
  State<_WintonBananaField> createState() => _WintonBananaFieldState();
}

class _WintonBananaFieldState extends State<_WintonBananaField>
    with TickerProviderStateMixin {
  static const int _count = 16;

  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  // Seconds accumulated across ticker stop/starts. A raw Ticker's `elapsed`
  // restarts at zero on every start(), so without this base a reduce-motion
  // freeze→resume would snap every banana back to its t=0 position.
  double _timeBase = 0;
  late final Ticker _ticker;
  late final AnimationController _entrance;
  late final CurvedAnimation _entranceCurve;
  late final List<_Banana> _bananas;
  PreferencesState? _prefsRef;

  @override
  void initState() {
    super.initState();
    // Fixed seed: a deterministic, hand-tuned scatter beats per-run randomness
    // for an effect people will screenshot. (0xBA11A — bananas.)
    final rng = math.Random(0xBA11A);
    _bananas = List<_Banana>.generate(_count, (_) => _Banana.random(rng));
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceCurve =
        CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    _ticker = createTicker((elapsed) {
      _time.value = _timeBase + elapsed.inMicroseconds / 1e6;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to the motion pref so toggling reduce-motion while the egg is
    // already on screen flips between the frozen scatter and the live shower,
    // instead of latching whichever mode was set when the field first
    // appeared. Mirrors the MotionLoopSync pattern (the egg drives a raw
    // Ticker rather than a repeating controller, so it can't use the mixin).
    final prefs = context.read<PreferencesState>();
    if (prefs != _prefsRef) {
      _prefsRef?.removeListener(_syncMotion);
      prefs.addListener(_syncMotion);
      _prefsRef = prefs;
    }
    _syncMotion();
  }

  /// Reconcile the ticker + entrance with the current reduce-motion pref.
  /// Honor reduced-motion by freezing the field in place (static scatter,
  /// fully present, no fade) rather than denying the egg — motion-sensitive
  /// users still get the joke without the movement. Idempotent: safe to call
  /// on any dependency change or pref notification.
  void _syncMotion() {
    if (!mounted) return;
    if (_prefsRef?.reduceMotion ?? false) {
      if (_ticker.isActive) {
        _timeBase = _time.value; // preserve phase so a later resume is seamless
        _ticker.stop();
      }
      if (_entrance.value != 1.0) _entrance.value = 1.0;
    } else {
      if (!_ticker.isActive) _ticker.start();
      if (_entrance.status == AnimationStatus.dismissed) _entrance.forward();
    }
  }

  @override
  void dispose() {
    _prefsRef?.removeListener(_syncMotion);
    _ticker.dispose();
    _entranceCurve.dispose();
    _entrance.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BananaPainter(
        bananas: _bananas,
        time: _time,
        entrance: _entranceCurve,
      ),
      size: Size.infinite,
    );
  }
}

/// One falling banana's invariant params; its position is a pure function of
/// time, so the field needs no per-frame mutable state.
class _Banana {
  static const double _sizeMin = 20;
  static const double _sizeMax = 34;

  final double x0; // 0..1 horizontal home column
  final double size; // px, long axis
  final double fall; // px/s
  final double swayAmp; // px
  final double swayFreq; // Hz
  final double spin; // rad/s (tumble)
  final double phase; // rad
  final double y0; // 0..1 initial position (fraction of the fall span)
  final double ripe; // 0 green-gold .. 1 speckled-ripe
  final double depth; // 0.72..1 parallax opacity, precomputed from size
  final Color hi; // ripeness palette — precomputed (fixed per banana)
  final Color mid;
  final Color lo;

  const _Banana({
    required this.x0,
    required this.size,
    required this.fall,
    required this.swayAmp,
    required this.swayFreq,
    required this.spin,
    required this.phase,
    required this.y0,
    required this.ripe,
    required this.depth,
    required this.hi,
    required this.mid,
    required this.lo,
  });

  factory _Banana.random(math.Random r) {
    double lerp(double a, double b) => a + (b - a) * r.nextDouble();
    final double size = lerp(_sizeMin, _sizeMax);
    final double ripe = r.nextDouble();
    // Larger reads as nearer; clamp so the formula survives any future change
    // to the size range without silently pushing opacity out of [0, 1].
    final double depth =
        (0.72 + 0.28 * ((size - _sizeMin) / (_sizeMax - _sizeMin)))
            .clamp(0.0, 1.0);
    return _Banana(
      x0: r.nextDouble(),
      size: size,
      fall: lerp(26, 52),
      swayAmp: lerp(10, 30),
      swayFreq: lerp(0.18, 0.5),
      spin: lerp(-0.7, 0.7),
      phase: r.nextDouble() * math.pi * 2,
      y0: r.nextDouble(), // fraction of span — screen-size agnostic
      ripe: ripe,
      depth: depth,
      hi: Color.lerp(const Color(0xFFF1EE86), const Color(0xFFFFE98A), ripe)!,
      mid: Color.lerp(const Color(0xFFE6D945), const Color(0xFFFFD23B), ripe)!,
      lo: Color.lerp(const Color(0xFFBBA42C), const Color(0xFFE3A12A), ripe)!,
    );
  }
}

class _BananaPainter extends CustomPainter {
  final List<_Banana> bananas;
  final ValueNotifier<double> time;
  final Animation<double> entrance;

  _BananaPainter({
    required this.bananas,
    required this.time,
    required this.entrance,
  }) : super(repaint: Listenable.merge([time, entrance]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.isFinite) return; // degenerate layout — skip
    final double t = time.value;
    final double ent = entrance.value.clamp(0.0, 1.0).toDouble();
    if (ent <= 0) return;
    for (final b in bananas) {
      final double span = size.height + b.size * 3;
      // b.y0 is a fraction of span, so the initial scatter fills any window
      // height (an absolute px offset clumped on tall/short screens).
      final double y = ((t * b.fall + b.y0 * span) % span) - b.size * 1.5;
      final double progress = (y + b.size * 1.5) / span; // 0 top .. 1 bottom
      final double fade = _smoothstep(0.0, 0.10, progress) *
          (1.0 - _smoothstep(0.84, 1.0, progress));
      final double opacity = fade * ent * b.depth * 0.62;
      if (opacity <= 0.01) continue;
      final double x = b.x0 * size.width +
          b.swayAmp * math.sin(t * b.swayFreq * 2 * math.pi + b.phase);
      _drawBanana(canvas, b, Offset(x, y), b.phase + t * b.spin, opacity);
    }
  }

  /// A procedural banana: a closed crescent (two pointed tips, fattest belly)
  /// filled with a ripeness-shifted vertical gradient for roundness, a pale
  /// top-ridge sheen, brown freckles that bloom with ripeness, and a stem
  /// stalk + blossom point. Local space: long axis on x, bowing DOWN (+y).
  void _drawBanana(
      Canvas canvas, _Banana b, Offset center, double rot, double opacity) {
    final double s = b.size;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rot);

    final Offset tipA = Offset(-s * 0.46, -s * 0.03); // stem tip (top-left)
    final Offset tipB = Offset(s * 0.46, -s * 0.03); // blossom tip (top-right)
    final Path body = Path()
      ..moveTo(tipA.dx, tipA.dy)
      ..quadraticBezierTo(0, s * 0.62, tipB.dx, tipB.dy) // outer (lower) edge
      ..quadraticBezierTo(0, s * 0.30, tipA.dx, tipA.dy) // inner (upper) edge
      ..close();

    // Ripeness palette is precomputed per banana (it never changes); only the
    // per-frame opacity is folded in here.
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, s * 0.10),
          Offset(0, s * 0.50),
          <Color>[
            b.hi.withValues(alpha: opacity),
            b.mid.withValues(alpha: opacity),
            b.lo.withValues(alpha: opacity),
          ],
          const <double>[0.0, 0.5, 1.0],
        ),
    );

    // Top-ridge sheen — a soft pale highlight tracing the inner curve.
    canvas.drawPath(
      Path()
        ..moveTo(tipA.dx * 0.66, s * 0.02)
        ..quadraticBezierTo(0, s * 0.30, tipB.dx * 0.66, s * 0.02),
      Paint()
        ..color = const Color(0xFFFFF4B8).withValues(alpha: opacity * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..strokeCap = StrokeCap.round,
    );

    // Ripe freckles — a few brown specks bloom past ~0.55 ripeness.
    if (b.ripe > 0.55) {
      final Paint speck = Paint()
        ..color = const Color(0xFF7A4A22)
            .withValues(alpha: opacity * (b.ripe - 0.55) * 1.5);
      for (int k = 0; k < 3; k++) {
        final double u = math.sin(b.phase * (k + 2.0)) * 0.20;
        final double v = 0.20 + 0.05 * math.cos(b.phase + k);
        canvas.drawCircle(Offset(s * u, s * v), s * 0.026, speck);
      }
    }

    // Stem stalk at tip A; browned blossom point at tip B.
    canvas.drawLine(
      tipA,
      Offset(tipA.dx - s * 0.06, tipA.dy - s * 0.13),
      Paint()
        ..color = const Color(0xFF6E4B26).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tipB, s * 0.045,
        Paint()..color = const Color(0xFF4A3018).withValues(alpha: opacity));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BananaPainter oldDelegate) => false; // repaint via Listenable
}

double _smoothstep(double edge0, double edge1, double x) {
  final double t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}
