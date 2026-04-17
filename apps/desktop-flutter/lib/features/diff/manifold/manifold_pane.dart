// Manifold drawer pane.
//
// A two-pane evidence view built on [DiffPinnedContextModel]. The
// scene lives in 3D: each comet has an (x, y, z) position on a shell
// around the pinned line, and a small set of prefixed perspectives
// rotate the whole neighborhood via quaternion slerp so the user
// witnesses the same evidence from different vantage points.
//
// Left pane — chart. Current hunk at center as a diamond. Rhymes
// (line-level echoes in the current diff) on an inner shell. Related
// files (K-nearest file-level neighbors) on an outer shell. Positions
// on each shell are distributed via sunflower (golden-angle) packing,
// so density reads naturally without clumping.
//
// Right pane — tangent. Pinned file as the diamond anchor on the
// left. Each transport edge becomes a flow into a 3D fan on the
// right, with the target comet at the end of the flow. Coupled
// related files that carry no current transport edge render as halo-
// only ghosts with dashed flows — absence reads as the message.
//
// Perspectives (slerp between them on click):
//   * overview — slight yaw/pitch, see the whole neighborhood
//   * rhymes   — pitched to emphasize the inner shell
//   * reach    — yawed toward the outer shell / transport
//   * parallel — rotated 90° around to look along the flow axis; what
//                was flat becomes depth, what was depth becomes flat
//   * residual — tipped so dormant ghosts sit in the foreground
//
// Motion and visual intensity route through the active theme's
// [SurfaceMaterialShader] (motion, luminescence, edgeIntensity,
// geometry.pillRadius). The idle breath controller respects the
// user's motion rate — on reduced-motion, pulses fall silent.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../backend/diff_logos_facade.dart';
import '../../../backend/lru_cache.dart';
import '../../../ui/motion.dart';
import '../../../ui/tokens.dart';
import 'comet.dart';

/// Prefixed perspectives the user can slerp between. Order drives the
/// chip row layout. Each one answers a distinct programmer question;
/// perspectives that were redundant with [eigenshape] (plain overview,
/// rhymes-forward) have been collapsed into the default.
///
///   * [eigenshape] — positions come from PCA of the local simhash
///     cloud. Physical distance = code-shape distance. Home view.
///   * [reach] — pull-weight becomes depth. Answers: what does this
///     change pull on hardest?
///   * [parallel] — coupling becomes depth. Answers: who historically
///     moves with this file, not just resembles it?
///   * [residual] — ghosts come forward. Answers: what's the engine
///     expecting that isn't there?
enum ManifoldPerspective {
  eigenshape,
  reach,
  parallel,
  residual,
}

const Map<ManifoldPerspective, CometCamera> _chartPerspectives = {
  ManifoldPerspective.eigenshape:
      CometCamera(yaw: 0.08, pitch: -0.06, focal: 2.7),
  ManifoldPerspective.reach:
      CometCamera(yaw: 0.55, pitch: -0.05, focal: 2.3),
  ManifoldPerspective.parallel:
      CometCamera(yaw: 1.25, pitch: 0.10, focal: 2.1),
  ManifoldPerspective.residual:
      CometCamera(yaw: -0.42, pitch: 0.28, focal: 2.4),
};

const Map<ManifoldPerspective, CometCamera> _tangentPerspectives = {
  ManifoldPerspective.eigenshape:
      CometCamera(yaw: 0.08, pitch: -0.04, focal: 2.7),
  ManifoldPerspective.reach:
      CometCamera(yaw: 0.50, pitch: 0.02, focal: 2.2),
  ManifoldPerspective.parallel:
      CometCamera(yaw: 1.20, pitch: 0.05, focal: 2.1),
  ManifoldPerspective.residual:
      CometCamera(yaw: -0.45, pitch: 0.22, focal: 2.4),
};


class ManifoldPane extends StatefulWidget {
  final DiffPinnedContextModel context;
  final AppTokens tokens;
  final ValueChanged<String>? onOpenRelatedPath;
  final void Function(int displayIdx)? onRhymeTap;

  const ManifoldPane({
    super.key,
    required this.context,
    required this.tokens,
    this.onOpenRelatedPath,
    this.onRhymeTap,
  });

  @override
  State<ManifoldPane> createState() => _ManifoldPaneState();
}

class _ManifoldPaneState extends State<ManifoldPane>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _breath;
  late final AnimationController _slerp;
  /// Short "you-just-arrived" flash on the destination glyph. Fires
  /// when the slerp lands so the target chip gets a small celebratory
  /// ripple instead of the wavefront animation silently stopping.
  late final AnimationController _landing;

  ManifoldPerspective _from = ManifoldPerspective.eigenshape;
  ManifoldPerspective _to = ManifoldPerspective.eigenshape;

  Offset? _chartCursor;
  Offset? _tangentCursor;
  int? _chartFocus;
  int? _tangentFocus;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
    // Slerp is completed at rest — advances to 1 on first perspective
    // switch so the scene doesn't animate needlessly on mount.
    _slerp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1.0,
    );
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _landing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    // When the slerp settles, trigger the landing flash on the
    // destination glyph. Status listener fires exactly once per
    // transition regardless of frame pacing.
    _slerp.addStatusListener((status) {
      if (status == AnimationStatus.completed && _from != _to) {
        _landing
          ..reset()
          ..forward();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shader = context.surfaceShader;
    // Intro and slerp follow the active theme's motion character and
    // respect the user's motion-rate preference for accessibility.
    final introDesired = context.motion(shader.duration * 4);
    if (introDesired > Duration.zero && _intro.duration != introDesired) {
      _intro.duration = introDesired;
    }
    // Slerp runs longer than ordinary state transitions — perspective
    // shifts physically remap where comets sit, and we want the morph
    // to feel like matter flowing through the manifold, not a
    // flat-lerp snap.
    final slerpDesired = context.motion(shader.duration * 5);
    if (slerpDesired > Duration.zero && _slerp.duration != slerpDesired) {
      _slerp.duration = slerpDesired;
    }
    // Breath — if the user has disabled motion, stop the idle loop
    // entirely; otherwise keep it in sync with the motion rate.
    final breathTarget = context.motion(const Duration(milliseconds: 5000));
    if (breathTarget <= Duration.zero) {
      if (_breath.isAnimating) _breath.stop();
    } else {
      if (_breath.duration != breathTarget) _breath.duration = breathTarget;
      if (!_breath.isAnimating) _breath.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ManifoldPane old) {
    super.didUpdateWidget(old);
    final lineChanged =
        old.context.line.fastKey != widget.context.line.fastKey;
    // Signal shape can change without the line changing (facade may
    // stream rhymes/edges in stages). Reset the intro on any material
    // change so arrivals are visible, and clear stale cursor state.
    final shapeChanged = lineChanged ||
        old.context.rhymePreviews.length !=
            widget.context.rhymePreviews.length ||
        old.context.relatedFiles.length !=
            widget.context.relatedFiles.length ||
        old.context.transportEdges.length !=
            widget.context.transportEdges.length;
    if (shapeChanged) {
      _intro
        ..reset()
        ..forward();
      _chartCursor = null;
      _tangentCursor = null;
      _chartFocus = null;
      _tangentFocus = null;
    }
    if (lineChanged) {
      // Reset perspective to Eigenshape on line change — it's the
      // default informational lens and wouldn't match state from a
      // different pinned line.
      _from = ManifoldPerspective.eigenshape;
      _to = ManifoldPerspective.eigenshape;
      _slerp.value = 1.0;
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    _slerp.dispose();
    _landing.dispose();
    super.dispose();
  }

  void _setPerspective(ManifoldPerspective next) {
    if (_to == next) return;
    setState(() {
      _from = _to;
      _to = next;
      _slerp
        ..reset()
        ..forward();
      // Clear hover state — the geometry has moved; old focus index
      // would hit-test against stale positions until next hover.
      _chartFocus = null;
      _tangentFocus = null;
    });
  }

  CometCamera _camera(Map<ManifoldPerspective, CometCamera> map) {
    return CometCamera.slerp(map[_from]!, map[_to]!, _slerp.value);
  }

  @override
  Widget build(BuildContext ctx) {
    final shader = ctx.surfaceShader;
    final t = widget.tokens;
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _breath, _slerp, _landing]),
      builder: (_, __) {
        final introT = _intro.value;
        final breathT = _breath.value;
        final chartCamera = _camera(_chartPerspectives);
        final tangentCamera = _camera(_tangentPerspectives);
        // Themes whose text effect is `none` stay silent on arrival —
        // petrichor's explicit intent is no decoration, even on
        // interaction events. Every other theme reuses its existing
        // ambient character: a brief brightening of the glyph's own
        // rendering (no new shapes, no ripple).
        final allowArrival = shader.textEffect != ThemeTextEffect.none;
        final landingT = allowArrival ? _landing.value : 0.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: SizedBox(
            height: 202,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PerspectiveChipRow(
                  tokens: t,
                  from: _from,
                  to: _to,
                  slerpT: _slerp.value,
                  landingT: landingT,
                  breathT: breathT,
                  onPick: _setPerspective,
                ),
                const SizedBox(height: 2),
                Expanded(
                  // Single inset surface — both panes share one darker
                  // background "cut into" the drawer, with a hairline
                  // divider between chart and tangent so they read as
                  // one cohesive space rather than two cards.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.bg0.withValues(alpha: 0.55),
                      border: Border.all(
                        color: t.chromeBorder.withValues(alpha: 0.10),
                        width: 0.5,
                      ),
                      borderRadius:
                          BorderRadius.circular(shader.geometry.pillRadius),
                    ),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(shader.geometry.pillRadius),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 11,
                            child: _ChartSurface(
                              tokens: t,
                              shader: shader,
                              model: widget.context,
                              introT: introT,
                              breathT: breathT,
                              camera: chartCamera,
                              perspectiveFrom: _from,
                              perspectiveTo: _to,
                              perspectiveT: _slerp.value,
                              cursor: _chartCursor,
                              focus: _chartFocus,
                              onCursor: (p) {
                                if (_chartCursor != p) {
                                  setState(() => _chartCursor = p);
                                }
                              },
                              onFocus: (f) {
                                if (_chartFocus != f) {
                                  setState(() => _chartFocus = f);
                                }
                              },
                              onOpenPath: widget.onOpenRelatedPath,
                              onRhymeTap: widget.onRhymeTap,
                            ),
                          ),
                          Container(
                            width: 1,
                            color:
                                t.chromeBorder.withValues(alpha: 0.16),
                          ),
                          Expanded(
                            flex: 9,
                            child: _TangentSurface(
                              tokens: t,
                              shader: shader,
                              model: widget.context,
                              introT: introT,
                              breathT: breathT,
                              camera: tangentCamera,
                              perspectiveFrom: _from,
                              perspectiveTo: _to,
                              perspectiveT: _slerp.value,
                              cursor: _tangentCursor,
                              focus: _tangentFocus,
                              onCursor: (p) {
                                if (_tangentCursor != p) {
                                  setState(() => _tangentCursor = p);
                                }
                              },
                              onFocus: (f) {
                                if (_tangentFocus != f) {
                                  setState(() => _tangentFocus = f);
                                }
                              },
                              onOpenPath: widget.onOpenRelatedPath,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- perspective chip row ----------------------------------------

/// Row of animated shape-glyphs — one per perspective. Each glyph
/// molds and animates continuously via the shared [breathT] clock,
/// communicating what its perspective IS through its motion rather
/// than a tooltip. The slerp progress cross-fades between the
/// outgoing and incoming glyph's "activation" so the row feels like
/// one cohesive flowing system, not a set of independent widgets.
class _PerspectiveChipRow extends StatelessWidget {
  final AppTokens tokens;
  final ManifoldPerspective from;
  final ManifoldPerspective to;
  final double slerpT;
  /// 0 at rest; 0→1→0 on arrival of a new perspective. Gated to zero
  /// by the parent when the active theme's [ThemeTextEffect] is none
  /// so restrained themes stay silent on arrival.
  final double landingT;
  final double breathT;
  final ValueChanged<ManifoldPerspective> onPick;

  const _PerspectiveChipRow({
    required this.tokens,
    required this.from,
    required this.to,
    required this.slerpT,
    required this.landingT,
    required this.breathT,
    required this.onPick,
  });

  double _weightFor(ManifoldPerspective p) {
    if (from == to) {
      return p == to ? 1.0 : 0.0;
    }
    if (p == to) return slerpT;
    if (p == from) return 1.0 - slerpT;
    return 0.0;
  }

  /// Gaussian wavefront travelling from the `from` glyph to the `to`
  /// glyph as the slerp progresses. Intermediate glyphs light up when
  /// the front passes through them — the handoff reads as a ripple
  /// across the row, not just two endpoints fading in opposition.
  double _pulseFor(ManifoldPerspective p) {
    if (from == to) return 0.0;
    const values = ManifoldPerspective.values;
    final pIndex = values.indexOf(p).toDouble();
    final fromIndex = values.indexOf(from).toDouble();
    final toIndex = values.indexOf(to).toDouble();
    // Same curve as slerp so row motion and scene morph feel fused.
    final curved = Curves.easeInOutCubic.transform(slerpT.clamp(0.0, 1.0));
    final pulsePos = fromIndex + (toIndex - fromIndex) * curved;
    final distance = (pIndex - pulsePos).abs();
    const sigma = 0.6;
    final energy = math.exp(-(distance * distance) / (2 * sigma * sigma));
    // Don't double-paint endpoints — they've got their own rising/
    // falling weights.
    if (p == from || p == to) return 0.0;
    return energy;
  }

  @override
  Widget build(BuildContext context) {
    final luminescence = context.surfaceShader.luminescence;
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final p in ManifoldPerspective.values)
            _PerspectiveGlyph(
              tokens: tokens,
              perspective: p,
              weight: _weightFor(p),
              pulse: _pulseFor(p),
              // Only the destination glyph feels the arrival flash.
              landing: p == to ? landingT : 0.0,
              breathT: breathT,
              luminescence: luminescence,
              onPick: onPick,
            ),
        ],
      ),
    );
  }
}

class _PerspectiveGlyph extends StatelessWidget {
  final AppTokens tokens;
  final ManifoldPerspective perspective;
  /// 0 = inert / background; 1 = fully active. Lerps during slerp
  /// transitions so the row visually mirrors the manifold's morph.
  final double weight;
  /// Transient attention boost as the selection wavefront passes
  /// through this glyph. 0 at rest; peaks while the front is on top
  /// of this glyph; falls back to 0 once the front has moved on.
  final double pulse;
  /// 0 at rest; brief 0→1→0 arc only on the destination glyph as the
  /// slerp completes. Modulates the glyph's OWN alpha and scale —
  /// no new shapes introduced. Gated zero on restrained themes by
  /// the parent.
  final double landing;
  final double breathT;
  final double luminescence;
  final ValueChanged<ManifoldPerspective> onPick;

  const _PerspectiveGlyph({
    required this.tokens,
    required this.perspective,
    required this.weight,
    required this.pulse,
    required this.landing,
    required this.breathT,
    required this.luminescence,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    // Wavefront passing-through: small lift + widening.
    final lift = -pulse * 1.8;
    final wavefrontScale = 1.0 + pulse * 0.14;
    // Arrival pulse — a single heartbeat on landing. sin(pi·t) is 0
    // at the ends and 1 at the peak, so the glyph swells then settles
    // without a linger.
    final arrival = math.sin(landing.clamp(0.0, 1.0) * math.pi);
    final landingScale = 1.0 + arrival * 0.18;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onPick(perspective),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Transform.translate(
            offset: Offset(0, lift),
            child: Transform.scale(
              scale: wavefrontScale * landingScale,
              child: SizedBox(
                width: 22,
                height: 14,
                child: CustomPaint(
                  painter: _GlyphPainter(
                    perspective: perspective,
                    weight: weight,
                    pulse: pulse,
                    arrival: arrival,
                    breathT: breathT,
                    color: tokens.accentBright,
                    luminescence: luminescence,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the per-perspective molding glyph. Each perspective has a
/// distinct visual language tied to its informational meaning:
///   * eigenshape — a scatter of small nodes drifting on individual
///     orbits (positions-are-data)
///   * reach — a horizontal ray with a traveling pulse (flow outward)
///   * parallel — two synchronized dots rising together (co-movement)
///   * residual — a dashed ring with an expanding inner pulse that
///     never quite reaches the edge (the gap)
class _GlyphPainter extends CustomPainter {
  final ManifoldPerspective perspective;
  final double weight;
  final double pulse;
  final double arrival;
  final double breathT;
  final Color color;
  final double luminescence;

  const _GlyphPainter({
    required this.perspective,
    required this.weight,
    required this.pulse,
    required this.arrival,
    required this.breathT,
    required this.color,
    required this.luminescence,
  });

  double get _alphaScale {
    // Idle alpha floor ~0.32; active peaks at 1.0. Weight interpolates
    // during slerp; pulse brightens as the wavefront passes; arrival
    // adds a brief brightening on landing. All three modulate the
    // glyph's own rendering — no new shapes drawn.
    return (0.32 + 0.68 * weight + 0.55 * pulse + 0.30 * arrival)
            .clamp(0.0, 1.4) *
        luminescence;
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (perspective) {
      case ManifoldPerspective.eigenshape:
        _paintEigenshape(canvas, size);
      case ManifoldPerspective.reach:
        _paintReach(canvas, size);
      case ManifoldPerspective.parallel:
        _paintParallel(canvas, size);
      case ManifoldPerspective.residual:
        _paintResidual(canvas, size);
    }
  }

  void _paintEigenshape(Canvas canvas, Size size) {
    final alpha = _alphaScale;
    final paint = Paint()..color = color.withValues(alpha: alpha);
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Four nodes on independent drifting orbits — a miniature PCA
    // scatter, never in lockstep.
    const base = [
      Offset(-0.6, -0.25),
      Offset(0.45, -0.45),
      Offset(-0.15, 0.5),
      Offset(0.55, 0.35),
    ];
    for (var i = 0; i < base.length; i++) {
      final phase = (breathT + i * 0.23) * 2 * math.pi;
      final ox = base[i].dx + 0.08 * math.sin(phase);
      final oy = base[i].dy + 0.06 * math.cos(phase * 1.1);
      final p = Offset(
        cx + ox * size.width * 0.4,
        cy + oy * size.height * 0.42,
      );
      canvas.drawCircle(p, 1.3 + 0.4 * weight, paint);
    }
  }

  void _paintReach(Canvas canvas, Size size) {
    final alpha = _alphaScale;
    final cy = size.height / 2;
    final linePaint = Paint()
      ..color = color.withValues(alpha: alpha * 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(2, cy), Offset(size.width - 2, cy), linePaint);
    // Traveling pulse rides outward, loops.
    final t = breathT;
    final pulseX = 2 + t * (size.width - 4);
    canvas.drawCircle(
      Offset(pulseX, cy),
      1.5 + 0.5 * weight,
      Paint()..color = color.withValues(alpha: alpha),
    );
    // Small arrowhead at the far end.
    final headPaint = Paint()
      ..color = color.withValues(alpha: alpha * 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final tipX = size.width - 1.5;
    canvas.drawLine(
      Offset(tipX - 2.5, cy - 1.8),
      Offset(tipX, cy),
      headPaint,
    );
    canvas.drawLine(
      Offset(tipX - 2.5, cy + 1.8),
      Offset(tipX, cy),
      headPaint,
    );
  }

  void _paintParallel(Canvas canvas, Size size) {
    final alpha = _alphaScale;
    final paint = Paint()..color = color.withValues(alpha: alpha);
    // Two dots drift up-and-down in perfect sync — the visual
    // definition of co-movement.
    final phase = breathT * 2 * math.pi;
    final drift = 0.22 * math.sin(phase) * size.height;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = 1.4 + 0.4 * weight;
    canvas.drawCircle(Offset(cx - 4.5, cy + drift), r, paint);
    canvas.drawCircle(Offset(cx + 4.5, cy + drift), r, paint);
    // Faint bond line between them to suggest coupling.
    canvas.drawLine(
      Offset(cx - 4.5, cy + drift),
      Offset(cx + 4.5, cy + drift),
      Paint()
        ..color = color.withValues(alpha: alpha * 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _paintResidual(Canvas canvas, Size size) {
    final alpha = _alphaScale;
    final center = Offset(size.width / 2, size.height / 2);
    const r = 5.0;
    // Dashed outer ring — the envelope of what the engine expects.
    final ringPaint = Paint()
      ..color = color.withValues(alpha: alpha * 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dashCount = 10;
    const step = 2 * math.pi / dashCount;
    for (var k = 0; k < dashCount; k++) {
      final a0 = k * step;
      final a1 = a0 + step * 0.55;
      final p0 = center + Offset(math.cos(a0) * r, math.sin(a0) * r);
      final p1 = center + Offset(math.cos(a1) * r, math.sin(a1) * r);
      canvas.drawLine(p0, p1, ringPaint);
    }
    // Inner pulse expands outward and fades — never quite fills the
    // ring. The visual of "almost, but not there".
    final pulseT = breathT;
    final innerR = pulseT * (r - 0.8);
    final innerAlpha = (alpha * (1 - pulseT) * 0.6).clamp(0.0, 1.0);
    if (innerAlpha > 0.01) {
      canvas.drawCircle(
        center,
        innerR,
        Paint()
          ..color = color.withValues(alpha: innerAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.perspective != perspective ||
      old.weight != weight ||
      old.pulse != pulse ||
      old.arrival != arrival ||
      old.breathT != breathT ||
      old.color != color ||
      old.luminescence != luminescence;
}

// ---- hashing + lane coloring -------------------------------------

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final code in s.codeUnits) {
    h ^= code;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

Color _laneColor(AppTokens t, String key) {
  final seed = _fnv1a(key);
  final palette = <Color>[
    t.accentBright,
    t.chromeAccent,
    t.stateAdded,
    t.hyperChromatic1,
    t.hyperChromatic2,
    t.eventStartTone,
  ];
  return palette[seed % palette.length];
}

// Sunflower packing on a sphere — returns unit vector for index i in
// a set of size n. Gives well-distributed 3D positions without
// clumping, which 2D golden-angle alone couldn't.
(double, double, double) _sunflowerOnSphere(int i, int n) {
  // Offset to avoid a point exactly at the pole when n is small.
  final t = n <= 1 ? 0.0 : (i + 0.5) / n * 2 - 1;
  final r = math.sqrt(1 - t * t);
  final angle = i * 2.399963229728653; // golden angle
  final x = r * math.cos(angle);
  final y = r * math.sin(angle);
  final z = t;
  return (x, y, z);
}

/// Project a cloud of 64-bit simhashes onto their top-3 principal
/// components and return one (x, y, z) per input, scaled to roughly
/// [-0.35, 0.35] so the result fits in a chart pane.
///
/// Implementation note: for N simhashes with N ≪ 64 we compute the
/// NxN Gram matrix of the ±1-encoded centered vectors and recover its
/// top-3 eigenvectors via power iteration with deflation. The Gram
/// eigenvectors ARE the sample projections (up to scale), which
/// saves us from materializing a 64×64 covariance matrix or running a
/// general SVD.
///
/// Sign is stabilized so re-opening the drawer on the same data
/// doesn't mirror the layout.
List<(double, double, double)> _simhashPca(List<int> simhashes) {
  final n = simhashes.length;
  if (n == 0) return const [];
  if (n == 1) return [(0.0, 0.0, 0.0)];

  // Bit-unpack each simhash into a ±1 vector of length 64.
  final X = <List<double>>[];
  for (final h in simhashes) {
    final v = List<double>.filled(64, 0);
    for (var b = 0; b < 64; b++) {
      v[b] = (((h >> b) & 1) == 1) ? 1.0 : -1.0;
    }
    X.add(v);
  }
  // Center each feature (bit) column.
  final mean = List<double>.filled(64, 0);
  for (final v in X) {
    for (var j = 0; j < 64; j++) {
      mean[j] += v[j];
    }
  }
  for (var j = 0; j < 64; j++) {
    mean[j] /= n;
  }
  for (final v in X) {
    for (var j = 0; j < 64; j++) {
      v[j] -= mean[j];
    }
  }

  // Gram matrix (NxN).
  final G = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    for (var j = i; j < n; j++) {
      var s = 0.0;
      for (var k = 0; k < 64; k++) {
        s += X[i][k] * X[j][k];
      }
      G[i][j] = s;
      G[j][i] = s;
    }
  }

  // Top-3 eigenvectors via power iteration + deflation.
  final axes = <List<double>>[];
  for (var a = 0; a < 3; a++) {
    var v = List<double>.filled(n, 0);
    for (var k = 0; k < n; k++) {
      v[k] = math.sin((a + 1) * (k + 1) * 1.7321) +
          0.3 * math.cos((k + 3) * 0.91);
    }
    for (final prev in axes) {
      final d = _dotN(v, prev);
      for (var k = 0; k < n; k++) {
        v[k] -= d * prev[k];
      }
    }
    var nm = math.sqrt(_dotN(v, v));
    if (nm < 1e-10) {
      axes.add(List<double>.filled(n, 0));
      continue;
    }
    for (var k = 0; k < n; k++) {
      v[k] /= nm;
    }

    for (var iter = 0; iter < 40; iter++) {
      final w = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        var s = 0.0;
        for (var j = 0; j < n; j++) {
          s += G[i][j] * v[j];
        }
        w[i] = s;
      }
      for (final prev in axes) {
        final d = _dotN(w, prev);
        for (var k = 0; k < n; k++) {
          w[k] -= d * prev[k];
        }
      }
      nm = math.sqrt(_dotN(w, w));
      if (nm < 1e-12) {
        v = List<double>.filled(n, 0);
        break;
      }
      for (var k = 0; k < n; k++) {
        w[k] /= nm;
      }
      v = w;
    }
    // Sign stabilization — largest-magnitude component positive.
    var peak = 0;
    for (var k = 1; k < n; k++) {
      if (v[k].abs() > v[peak].abs()) peak = k;
    }
    if (v[peak] < 0) {
      for (var k = 0; k < n; k++) {
        v[k] = -v[k];
      }
    }
    axes.add(v);
  }

  // Scale each axis independently to [-0.35, 0.35].
  final scale = <double>[];
  for (final axis in axes) {
    var max = 0.0;
    for (final x in axis) {
      if (x.abs() > max) max = x.abs();
    }
    scale.add(max < 1e-10 ? 0.0 : 0.35 / max);
  }

  return [
    for (var i = 0; i < n; i++)
      (
        axes[0][i] * scale[0],
        axes[1][i] * scale[1],
        axes[2][i] * scale[2],
      ),
  ];
}

/// Content-keyed LRU for [_simhashPca] results. The PCA is the single
/// hottest cost in chart rebuilds — O(N²) power iteration × 40 iters × 3
/// eigenvectors — and the input (one pinned line's simhash cloud) is
/// stable across every breath/intro/slerp tick that happens while the
/// user stays on the same line. Caching by content fingerprint collapses
/// all those redundant rebuilds to a single compute per unique cloud.
final LruCache<int, List<(double, double, double)>> _simhashPcaCache =
    LruCache<int, List<(double, double, double)>>(maxSize: 12);

int _fingerprintSimhashes(List<int> simhashes) {
  // Use Object.hashAll over the full 64-bit values so every bit of
  // every simhash participates in the hash. The previous hand-folded
  // 30-bit variant discarded bits 30–31 of every input.
  return Object.hashAll(simhashes);
}

List<(double, double, double)> _simhashPcaCached(List<int> simhashes) {
  // Trivial cases — cheaper to recompute than to hash.
  if (simhashes.length <= 1) return _simhashPca(simhashes);
  final key = _fingerprintSimhashes(simhashes);
  final cached = _simhashPcaCache.get(key);
  if (cached != null) return cached;
  final computed = _simhashPca(simhashes);
  _simhashPcaCache.put(key, computed);
  return computed;
}

double _dotN(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

// ---- chart pane --------------------------------------------------

/// Per-echo metadata used by perspective-driven z remapping. Kept
/// alongside the comet list so the widget can re-assemble comets at
/// frame time with different z values per perspective without
/// rebuilding the whole layout.
class _ChartRole {
  final bool isRhyme;
  final bool isRelated;
  final bool coupled;
  final bool semantic;
  final double score;
  const _ChartRole({
    required this.isRhyme,
    required this.isRelated,
    required this.coupled,
    required this.semantic,
    required this.score,
  });
  static const anchor = _ChartRole(
    isRhyme: false,
    isRelated: false,
    coupled: false,
    semantic: false,
    score: 1,
  );
}

class _ChartData {
  final List<Comet> baseComets; // identity + overview-layout position
  final List<_ChartRole> roles;
  final Map<ManifoldPerspective, List<(Offset, double)>> positions;
  final List<CometLink> links;
  final List<int> rhymeDisplayIdxs;
  final List<String?> openPaths;
  const _ChartData({
    required this.baseComets,
    required this.roles,
    required this.positions,
    required this.links,
    required this.rhymeDisplayIdxs,
    required this.openPaths,
  });
}

/// Z delta applied to an echo for a given perspective. Positive is
/// forward (closer to camera). Combined with the base sunflower z the
/// overview layout already sets, the chosen perspective physically
/// lifts the data that matters most for its question.
double _chartZBoost(ManifoldPerspective p, _ChartRole r) {
  switch (p) {
    case ManifoldPerspective.eigenshape:
      // Eigenshape supplies its own xy/z via the positions map, so
      // the z-boost path never needs to add anything.
      return 0;
    case ManifoldPerspective.reach:
      // Strong-score related files jump forward; rhymes step back so
      // the eye lands on the reach signal.
      if (r.isRelated) return 0.08 + r.score * 0.22;
      if (r.isRhyme) return -0.16;
      return 0;
    case ManifoldPerspective.parallel:
      // Coupled (historical co-change) is the "parallel worktree"
      // signal — it moves WITH you. Semantic-only resemblance looks
      // alike but doesn't move together; push it back.
      if (r.coupled && r.semantic) return 0.26;
      if (r.coupled) return 0.16;
      if (r.semantic) return -0.12;
      return 0;
    case ManifoldPerspective.residual:
      // Surprise surface: low-score echoes (the ones you wouldn't
      // have guessed) step forward; confident neighbors dim back.
      return (1.0 - r.score) * 0.28 - 0.10;
  }
}

_ChartData _buildChart(AppTokens t, DiffPinnedContextModel c) {
  final comets = <Comet>[];
  final roles = <_ChartRole>[];
  final links = <CometLink>[];
  final rhymeIdxs = <int>[];
  final openPaths = <String?>[];
  // Track rhyme indices per file so same-file rhymes can be chained
  // as a peer mesh — only meaningful across different files; within
  // the current file it's just "they're all here" and adds no info.
  final rhymeIndicesByPath = <String, List<int>>{};
  final currentFilePath = c.line.filePath ?? '';

  // Orientation anchor: current hunk, center, diamond.
  comets.add(Comet(
    position: const Offset(0.5, 0.5),
    z: 0,
    strength: 1.0,
    coreMass: 1.0,
    laneColor: t.accentBright,
    phase: 0,
    shape: CometShape.diamond,
  ));
  roles.add(_ChartRole.anchor);
  rhymeIdxs.add(-1);
  openPaths.add(null);

  // Inner shell: rhymes. Sunflower packing so 1 comet sits alone,
  // 20 fill the shell uniformly.
  final rs = c.rhymePreviews;
  const rhymeShellXY = 0.22;
  const rhymeShellZ = 0.20;
  for (var i = 0; i < rs.length; i++) {
    final r = rs[i];
    final (ux, uy, uz) = _sunflowerOnSphere(i, rs.length);
    // Y is compressed slightly so the shell reads elliptical in the
    // wider-than-tall pane — comets don't stack tightly at top/bottom.
    final pos = Offset(
      (0.5 + ux * rhymeShellXY).clamp(0.08, 0.92),
      (0.5 + uy * rhymeShellXY * 0.72).clamp(0.14, 0.86),
    );
    final pathSeed = _fnv1a('rhyme:${r.filePath}:${r.displayIndex}');
    final strength = (0.72 + (1.0 - (uz * uz)) * 0.18).clamp(0.4, 0.92);
    final rhymeIndex = comets.length;
    comets.add(Comet(
      position: pos,
      z: uz * rhymeShellZ,
      strength: strength.toDouble(),
      coreMass: 1.0,
      laneColor: _laneColor(t, 'rhyme:${r.filePath}'),
      phase: (pathSeed & 0xFF) / 0xFF,
      tag: r,
    ));
    roles.add(_ChartRole(
      isRhyme: true,
      isRelated: false,
      coupled: false,
      semantic: false,
      score: strength.toDouble(),
    ));
    rhymeIdxs.add(r.displayIndex);
    openPaths.add(null);
    // Peer chain: only across-file rhymes cluster — same-file is noise.
    if (r.filePath != currentFilePath) {
      rhymeIndicesByPath.putIfAbsent(r.filePath, () => []).add(rhymeIndex);
    }
  }

  // Outer shell: related files. Larger shell, offset phase so its
  // sunflower doesn't align angularly with the rhyme shell.
  final rf = c.relatedFiles;
  const relShellXY = 0.36;
  const relShellZ = 0.28;
  for (var i = 0; i < rf.length; i++) {
    final f = rf[i];
    // Offset index so rings don't share angular phases with rhymes.
    final (ux, uy, uz) = _sunflowerOnSphere(i + rs.length, rs.length + rf.length);
    final pos = Offset(
      (0.5 + ux * relShellXY).clamp(0.06, 0.94),
      (0.5 + uy * relShellXY * 0.72).clamp(0.14, 0.86),
    );
    final pathSeed = _fnv1a('rel:${f.path}');
    final double coreMass = f.coupled && f.semantic ? 1.0 : 0.82;
    final clampedScore = f.score.clamp(0.3, 0.9).toDouble();
    comets.add(Comet(
      position: pos,
      z: uz * relShellZ,
      strength: clampedScore,
      coreMass: coreMass,
      laneColor: _laneColor(t, 'rel:${f.path}'),
      phase: (pathSeed & 0xFF) / 0xFF,
      tag: f,
    ));
    roles.add(_ChartRole(
      isRhyme: false,
      isRelated: true,
      coupled: f.coupled,
      semantic: f.semantic,
      score: clampedScore,
    ));
    rhymeIdxs.add(-1);
    openPaths.add(f.path);
  }

  // Focus tethers: anchor → every echo, hover-only. Reveal which comet
  // connects to the current line only when asked.
  for (var i = 1; i < comets.length; i++) {
    links.add(CometLink(
      fromIndex: 0,
      toIndex: i,
      color: comets[i].laneColor,
      strength: comets[i].strength,
      hoverOnly: true,
    ));
  }

  // Peer mesh: rhymes from the same non-current file, chained.
  for (final indices in rhymeIndicesByPath.values) {
    if (indices.length < 2) continue;
    for (var k = 0; k < indices.length - 1; k++) {
      links.add(CometLink(
        fromIndex: indices[k],
        toIndex: indices[k + 1],
        color: comets[indices[k]].laneColor,
        strength: 0.8,
      ));
    }
  }

  // Compute per-perspective positions. Overview uses the sunflower
  // layout as built above. Other perspectives apply a z boost off the
  // same base. Eigenshape throws the sunflower away entirely: rhymes
  // get positions from PCA of their simhash cloud (centered on the
  // current line), and related files sit on an outer ring whose
  // z-depth encodes coupling vs pure-semantic resemblance.
  final positions = <ManifoldPerspective, List<(Offset, double)>>{};

  // Reach / Parallel / Residual all share the base sunflower xy and
  // just shift z based on role. Eigenshape is filled below with its
  // own xy + z derived from simhash PCA.
  for (final p in [
    ManifoldPerspective.reach,
    ManifoldPerspective.parallel,
    ManifoldPerspective.residual,
  ]) {
    positions[p] = [
      for (var i = 0; i < comets.length; i++)
        (comets[i].position, comets[i].z + _chartZBoost(p, roles[i])),
    ];
  }

  // Eigenshape: PCA of [currentLine, ...rhymes] simhashes. Shift so
  // the current line lands at origin; rhymes scatter at their learned
  // principal coordinates. Related files take a stable outer-ring
  // placement (no simhash available at the facade level) with
  // coupling on the z axis so parallel worktree signal still reads.
  final eigen = <(Offset, double)>[];
  final currentSimHash = c.line.simHash;
  final rhymeSimhashes = [for (final r in c.rhymePreviews) r.simHash];
  final simhashes = <int>[currentSimHash, ...rhymeSimhashes];
  final hasAnyHashes =
      currentSimHash != 0 || rhymeSimhashes.any((h) => h != 0);
  final eigenCoords = hasAnyHashes
      ? _simhashPcaCached(simhashes)
      : const <(double, double, double)>[];
  final anchorEigen = eigenCoords.isNotEmpty
      ? eigenCoords[0]
      : const (0.0, 0.0, 0.0);
  const anchorCenter = Offset(0.5, 0.5);
  // Anchor always at center.
  eigen.add((anchorCenter, 0.0));
  // Rhymes — one per entry in c.rhymePreviews, in order.
  for (var i = 0; i < rhymeSimhashes.length; i++) {
    if (eigenCoords.length > i + 1) {
      final ex = eigenCoords[i + 1].$1 - anchorEigen.$1;
      final ey = eigenCoords[i + 1].$2 - anchorEigen.$2;
      final ez = eigenCoords[i + 1].$3 - anchorEigen.$3;
      final clampedX = (0.5 + ex).clamp(0.06, 0.94).toDouble();
      final clampedY = (0.5 + ey * 0.72).clamp(0.14, 0.86).toDouble();
      eigen.add((Offset(clampedX, clampedY), ez));
    } else {
      // PCA fallback — place on a small ring so we don't collapse.
      final angle = i * 2.399963229728653;
      final xy = Offset(
        (0.5 + math.cos(angle) * 0.20).clamp(0.08, 0.92).toDouble(),
        (0.5 + math.sin(angle) * 0.20 * 0.72).clamp(0.14, 0.86).toDouble(),
      );
      eigen.add((xy, 0.0));
    }
  }
  // Related files — stable outer ring + z encoding coupling signal.
  for (var i = 0; i < c.relatedFiles.length; i++) {
    final f = c.relatedFiles[i];
    final seed = _fnv1a('eigen:${f.path}');
    final angle = ((seed & 0xFFFF) / 0xFFFF) * 2 * math.pi;
    final radius = 0.36 + (1.0 - f.score.clamp(0.0, 1.0)) * 0.08;
    final xy = Offset(
      (0.5 + math.cos(angle) * radius).clamp(0.06, 0.94).toDouble(),
      (0.5 + math.sin(angle) * radius * 0.72).clamp(0.14, 0.86).toDouble(),
    );
    final z = (f.coupled && f.semantic)
        ? 0.22
        : (f.coupled ? 0.10 : (f.semantic ? -0.14 : 0.0));
    eigen.add((xy, z));
  }
  positions[ManifoldPerspective.eigenshape] = eigen;

  return _ChartData(
    baseComets: comets,
    roles: roles,
    positions: positions,
    links: links,
    rhymeDisplayIdxs: rhymeIdxs,
    openPaths: openPaths,
  );
}

class _ChartSurface extends StatelessWidget {
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final DiffPinnedContextModel model;
  final double introT;
  final double breathT;
  final CometCamera camera;
  final ManifoldPerspective perspectiveFrom;
  final ManifoldPerspective perspectiveTo;
  final double perspectiveT;
  final Offset? cursor;
  final int? focus;
  final ValueChanged<Offset?> onCursor;
  final ValueChanged<int?> onFocus;
  final ValueChanged<String>? onOpenPath;
  final void Function(int displayIdx)? onRhymeTap;

  const _ChartSurface({
    required this.tokens,
    required this.shader,
    required this.model,
    required this.introT,
    required this.breathT,
    required this.camera,
    required this.perspectiveFrom,
    required this.perspectiveTo,
    required this.perspectiveT,
    required this.cursor,
    required this.focus,
    required this.onCursor,
    required this.onFocus,
    this.onOpenPath,
    this.onRhymeTap,
  });

  int? _hitTest(Offset p, Size size, List<Comet> comets) {
    final lay = CometField.layout(
      comets: comets,
      size: size,
      introT: introT,
      anchor: const Offset(0.5, 0.5),
      cursor: cursor,
      camera: camera,
    );
    int? best;
    var bestD = double.infinity;
    // Hit-test in paint order reverse so front-most comet wins ties.
    for (var k = lay.paintOrder.length - 1; k >= 0; k--) {
      final i = lay.paintOrder[k];
      final d = (p - lay.positions[i]).distance;
      final reach = lay.reachRadii[i] * 1.2 + 6;
      if (d < reach && d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final data = _buildChart(tokens, model);
    final comets =
        _morphChart(data, perspectiveFrom, perspectiveTo, perspectiveT);
    // Bare surface — the outer inset container in ManifoldPane owns
    // the background and border so both panes read as one space.
    return LayoutBuilder(
      builder: (ctx, cons) {
        final size = Size(cons.maxWidth, cons.maxHeight);
        return MouseRegion(
          cursor: focus != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (ev) {
            onCursor(ev.localPosition);
            onFocus(_hitTest(ev.localPosition, size, comets));
          },
          onExit: (_) {
            onCursor(null);
            onFocus(null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final hit = _hitTest(d.localPosition, size, comets);
              if (hit == null) return;
              final displayIdx = data.rhymeDisplayIdxs[hit];
              final path = data.openPaths[hit];
              if (displayIdx >= 0) {
                onRhymeTap?.call(displayIdx);
              } else if (path != null) {
                onOpenPath?.call(path);
              }
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: CometField(
                  comets: comets,
                  links: data.links,
                  introT: introT,
                  breathT: breathT,
                  luminescence: shader.luminescence,
                  edgeIntensity: shader.edgeIntensity,
                  focusedIndex: focus,
                  cursor: cursor,
                  camera: camera,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---- tangent pane ------------------------------------------------

class _TangentRole {
  final bool isSource;
  final bool isGhost;
  final bool coupled;
  final double pull;
  const _TangentRole({
    required this.isSource,
    required this.isGhost,
    required this.coupled,
    required this.pull,
  });
  static const source = _TangentRole(
    isSource: true,
    isGhost: false,
    coupled: false,
    pull: 1,
  );
}

class _TangentData {
  final List<Comet> comets;
  final List<_TangentRole> roles;
  final List<CometLink> links;
  final List<TangentFlow> flows;
  final List<String?> openPaths;
  const _TangentData(
    this.comets,
    this.roles,
    this.links,
    this.flows,
    this.openPaths,
  );
}

/// Z delta per perspective for tangent targets. The tangent pane
/// answers "what does this change reach?" so each perspective tilts
/// the answer toward a different facet of reach.
double _tangentZBoost(ManifoldPerspective p, _TangentRole r) {
  if (r.isSource) return 0;
  switch (p) {
    case ManifoldPerspective.eigenshape:
      // Tangent Eigenshape: strongest pulls lean toward the viewer;
      // ghosts sit quietly behind. Same informational lens as Reach
      // but paired with the eigenshape camera so the chart and
      // tangent read as one unified "positions are data" moment.
      if (r.isGhost) return -0.18 + (r.coupled ? 0.10 : 0);
      return (r.pull - 0.5) * 0.40;
    case ManifoldPerspective.reach:
      // Pull strength becomes depth. Strong pulls lean toward viewer;
      // weak targets (and ghosts) recede.
      if (r.isGhost) return -0.18;
      return (r.pull - 0.5) * 0.40;
    case ManifoldPerspective.parallel:
      // Coupled ghosts are the "parallel worktree" signal on the
      // tangent side — historically these move with you even if no
      // current edge fires. Push them forward.
      if (r.isGhost && r.coupled) return 0.22;
      if (r.isGhost) return -0.05;
      return -0.08;
    case ManifoldPerspective.residual:
      // Gaps perspective: ghosts become the foreground, solid edges
      // recede into the background so the eye sees the absence.
      return r.isGhost ? 0.34 : -0.22;
  }
}

_TangentData _buildTangent(AppTokens t, DiffPinnedContextModel c) {
  final comets = <Comet>[];
  final roles = <_TangentRole>[];
  final links = <CometLink>[];
  final flows = <TangentFlow>[];
  final openPaths = <String?>[];
  // Group transport targets by lane so same-lane siblings chain — a
  // user seeing a source<->test edge can instantly spot the other
  // tests pulled by the same change.
  final edgeIndicesByLane = <String, List<int>>{};

  final currentPath = c.line.filePath ?? '';
  const source = Offset(0.09, 0.5);

  comets.add(Comet(
    position: source,
    z: 0,
    strength: 1.0,
    coreMass: 1.0,
    laneColor: t.accentBright,
    phase: 0,
    shape: CometShape.diamond,
  ));
  roles.add(_TangentRole.source);
  openPaths.add(null);

  // Sort by pull desc so the strongest edges land first.
  final sortedEdges = [...c.transportEdges]
    ..sort((a, b) => b.pull.compareTo(a.pull));

  final edgeTargets = <String>{};

  // Targets fan out on a hemisphere centered on the source, facing
  // +x. Uses sunflower so small counts spread well and large counts
  // stay uniform. Pull scalar nudges the target slightly inward (high
  // pull = forward in z, strong visible).
  const fanRadiusXY = 0.34;
  const fanRadiusZ = 0.30;
  final n = sortedEdges.length;
  for (var i = 0; i < n; i++) {
    final e = sortedEdges[i];
    final target =
        e.targetPath == currentPath ? e.sourcePath : e.targetPath;
    if (target.isEmpty || target == currentPath) continue;
    edgeTargets.add(target);

    // Sunflower unit on the upper hemisphere facing +x.
    final (ux, uy, uz) = _sunflowerOnSphere(i, math.max(n, 3));
    // Tilt the hemisphere to face +x: remap (ux, uy, uz) so +x is the
    // dominant axis. Simple assignment: x = |ux| so targets are always
    // on the forward side; y + z carry the spread.
    final forwardX = 0.55 + (0.5 + 0.5 * ux.abs()) * 0.30;
    final yOffset = uy * fanRadiusXY * 0.72;
    final zOffset = uz * fanRadiusZ;
    final pos = Offset(
      forwardX.clamp(0.52, 0.94).toDouble(),
      (0.5 + yOffset).clamp(0.12, 0.88),
    );

    final lane = (e.laneLabel?.trim().isNotEmpty ?? false)
        ? e.laneLabel!.trim()
        : 'transport';
    final color = _laneColor(t, 'lane:$lane');
    final strength = e.pull.clamp(0.28, 0.95).toDouble();
    final cometIndex = comets.length;
    comets.add(Comet(
      position: pos,
      z: zOffset,
      strength: strength,
      coreMass: 1.0,
      laneColor: color,
      phase: (_fnv1a(target) & 0xFF) / 0xFF,
      tag: e,
    ));
    roles.add(_TangentRole(
      isSource: false,
      isGhost: false,
      coupled: false,
      pull: strength,
    ));
    openPaths.add(target);
    flows.add(TangentFlow(
      start: source,
      startZ: 0,
      end: pos,
      endZ: zOffset,
      strength: strength,
      laneColor: color,
    ));
    edgeIndicesByLane.putIfAbsent(lane, () => []).add(cometIndex);
  }

  // Ghosts — coupled related files without a transport edge. Live on
  // a slightly farther shell so they recede when foreground targets
  // fire. Rotated perspectives (especially 'residual') surface them.
  final ghosts = <DiffPinnedRelatedFile>[];
  for (final r in c.relatedFiles) {
    if (r.path == currentPath) continue;
    if (edgeTargets.contains(r.path)) continue;
    if (!r.coupled) continue;
    ghosts.add(r);
  }
  for (var i = 0; i < ghosts.length; i++) {
    final r = ghosts[i];
    final (ux, uy, uz) = _sunflowerOnSphere(i, math.max(ghosts.length, 3));
    final forwardX = 0.72 + (0.5 + 0.5 * ux.abs()) * 0.18;
    final yOffset = uy * fanRadiusXY * 0.68;
    final zOffset = uz * fanRadiusZ * 1.1; // slightly deeper than solids
    final pos = Offset(
      forwardX.clamp(0.58, 0.96).toDouble(),
      (0.5 + yOffset).clamp(0.10, 0.90),
    );
    final color = _laneColor(t, 'ghost:${r.path}');
    final strength = r.score.clamp(0.22, 0.55).toDouble();
    comets.add(Comet(
      position: pos,
      z: zOffset,
      strength: strength,
      coreMass: 0.0,
      laneColor: color,
      phase: (_fnv1a('ghost:${r.path}') & 0xFF) / 0xFF,
      tag: r,
    ));
    roles.add(_TangentRole(
      isSource: false,
      isGhost: true,
      coupled: r.coupled,
      pull: strength,
    ));
    openPaths.add(r.path);
    flows.add(TangentFlow(
      start: source,
      startZ: 0,
      end: pos,
      endZ: zOffset,
      strength: strength,
      laneColor: color,
      ghost: true,
    ));
  }

  // Focus tethers: source → every target + ghost, hover-only. Lights
  // up the path from the current file to whichever node is hovered.
  for (var i = 1; i < comets.length; i++) {
    links.add(CometLink(
      fromIndex: 0,
      toIndex: i,
      color: comets[i].laneColor,
      strength: comets[i].strength,
      hoverOnly: true,
    ));
  }

  // Peer mesh: same-lane transport targets chain, so the user can
  // see at a glance which targets are pulled by the same witness.
  for (final indices in edgeIndicesByLane.values) {
    if (indices.length < 2) continue;
    for (var k = 0; k < indices.length - 1; k++) {
      links.add(CometLink(
        fromIndex: indices[k],
        toIndex: indices[k + 1],
        color: comets[indices[k]].laneColor,
        strength: 0.75,
      ));
    }
  }

  return _TangentData(comets, roles, links, flows, openPaths);
}

/// Produce a new Comet list with per-comet z re-mapped by the current
/// perspective transition. [t] is the slerp progress 0..1 on an
/// easeInOutCubic curve, so the morph feels like matter pulled
/// through the manifold rather than a flat lerp.
List<Comet> _morphChart(
  _ChartData data,
  ManifoldPerspective from,
  ManifoldPerspective to,
  double t,
) {
  if (data.baseComets.isEmpty) return const [];
  final curved = Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
  final fromP = data.positions[from] ??
      data.positions[ManifoldPerspective.eigenshape]!;
  final toP = data.positions[to] ??
      data.positions[ManifoldPerspective.eigenshape]!;
  final out = <Comet>[];
  for (var i = 0; i < data.baseComets.length; i++) {
    final xy = Offset.lerp(fromP[i].$1, toP[i].$1, curved)!;
    final z = fromP[i].$2 + (toP[i].$2 - fromP[i].$2) * curved;
    final base = data.baseComets[i];
    out.add(Comet(
      position: xy,
      z: z,
      strength: base.strength,
      coreMass: base.coreMass,
      laneColor: base.laneColor,
      phase: base.phase,
      shape: base.shape,
      tag: base.tag,
    ));
  }
  return out;
}

List<Comet> _morphTangent(
  _TangentData data,
  ManifoldPerspective from,
  ManifoldPerspective to,
  double t,
) {
  if (data.comets.isEmpty) return const [];
  final curved = Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
  final out = <Comet>[];
  for (var i = 0; i < data.comets.length; i++) {
    final role = data.roles[i];
    final fromZBoost = _tangentZBoost(from, role);
    final toZBoost = _tangentZBoost(to, role);
    final zBoost = fromZBoost + (toZBoost - fromZBoost) * curved;
    final base = data.comets[i];
    out.add(Comet(
      position: base.position,
      z: base.z + zBoost,
      strength: base.strength,
      coreMass: base.coreMass,
      laneColor: base.laneColor,
      phase: base.phase,
      shape: base.shape,
      tag: base.tag,
    ));
  }
  return out;
}

/// Same morph applied to tangent flow endpoints so flow lines stay
/// anchored to their comets as the scene remaps.
List<TangentFlow> _morphFlows(
  _TangentData data,
  ManifoldPerspective from,
  ManifoldPerspective to,
  double t,
) {
  if (data.flows.isEmpty) return const [];
  final curved = Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
  final out = <TangentFlow>[];
  // Flow i connects source (role 0) to target (role i+1), aligned by
  // build order — same indexing used when _buildTangent created them.
  for (var i = 0; i < data.flows.length; i++) {
    final role = data.roles[i + 1];
    final fromZ = _tangentZBoost(from, role);
    final toZ = _tangentZBoost(to, role);
    final zBoost = fromZ + (toZ - fromZ) * curved;
    final f = data.flows[i];
    out.add(TangentFlow(
      start: f.start,
      startZ: f.startZ,
      end: f.end,
      endZ: f.endZ + zBoost,
      strength: f.strength,
      laneColor: f.laneColor,
      ghost: f.ghost,
    ));
  }
  return out;
}

class _TangentSurface extends StatelessWidget {
  final AppTokens tokens;
  final SurfaceMaterialShader shader;
  final DiffPinnedContextModel model;
  final double introT;
  final double breathT;
  final CometCamera camera;
  final ManifoldPerspective perspectiveFrom;
  final ManifoldPerspective perspectiveTo;
  final double perspectiveT;
  final Offset? cursor;
  final int? focus;
  final ValueChanged<Offset?> onCursor;
  final ValueChanged<int?> onFocus;
  final ValueChanged<String>? onOpenPath;

  const _TangentSurface({
    required this.tokens,
    required this.shader,
    required this.model,
    required this.introT,
    required this.breathT,
    required this.camera,
    required this.perspectiveFrom,
    required this.perspectiveTo,
    required this.perspectiveT,
    required this.cursor,
    required this.focus,
    required this.onCursor,
    required this.onFocus,
    this.onOpenPath,
  });

  int? _hitTest(Offset p, Size size, List<Comet> morphedComets) {
    final lay = CometField.layout(
      comets: morphedComets,
      size: size,
      introT: introT,
      anchor: const Offset(0.09, 0.5),
      cursor: cursor,
      camera: camera,
    );
    int? best;
    var bestD = double.infinity;
    for (var k = lay.paintOrder.length - 1; k >= 0; k--) {
      final i = lay.paintOrder[k];
      final d = (p - lay.positions[i]).distance;
      final reach = lay.reachRadii[i] * 1.2 + 6;
      if (d < reach && d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final data = _buildTangent(tokens, model);
    final morphedComets = _morphTangent(
      data,
      perspectiveFrom,
      perspectiveTo,
      perspectiveT,
    );
    final morphedFlows = _morphFlows(
      data,
      perspectiveFrom,
      perspectiveTo,
      perspectiveT,
    );
    // Bare surface — the outer inset container in ManifoldPane owns
    // the background and border.
    return LayoutBuilder(
      builder: (ctx, cons) {
        final size = Size(cons.maxWidth, cons.maxHeight);
        return MouseRegion(
          cursor: focus != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: (ev) {
            onCursor(ev.localPosition);
            onFocus(_hitTest(ev.localPosition, size, morphedComets));
          },
          onExit: (_) {
            onCursor(null);
            onFocus(null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final hit = _hitTest(d.localPosition, size, morphedComets);
              if (hit == null) return;
              final path = data.openPaths[hit];
              if (path != null) onOpenPath?.call(path);
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _TangentCompositePainter(
                  flows: morphedFlows,
                  comets: morphedComets,
                  links: data.links,
                  introT: introT,
                  breathT: breathT,
                  luminescence: shader.luminescence,
                  edgeIntensity: shader.edgeIntensity,
                  focusedIndex: focus,
                  cursor: cursor,
                  camera: camera,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TangentCompositePainter extends CustomPainter {
  final List<TangentFlow> flows;
  final List<Comet> comets;
  final List<CometLink> links;
  final double introT;
  final double breathT;
  final double luminescence;
  final double edgeIntensity;
  final int? focusedIndex;
  final Offset? cursor;
  final CometCamera camera;

  const _TangentCompositePainter({
    required this.flows,
    required this.comets,
    required this.links,
    required this.introT,
    required this.breathT,
    required this.luminescence,
    required this.edgeIntensity,
    this.focusedIndex,
    this.cursor,
    required this.camera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    TangentFlowPainter(
      flows: flows,
      introT: introT,
      breathT: breathT,
      luminescence: luminescence,
      edgeIntensity: edgeIntensity,
      camera: camera,
      anchor: const Offset(0.09, 0.5),
    ).paint(canvas, size);
    CometField(
      comets: comets,
      links: links,
      introT: introT,
      breathT: breathT,
      luminescence: luminescence,
      edgeIntensity: edgeIntensity,
      focusedIndex: focusedIndex,
      cursor: cursor,
      camera: camera,
      anchor: const Offset(0.09, 0.5),
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _TangentCompositePainter old) =>
      old.introT != introT ||
      old.breathT != breathT ||
      old.luminescence != luminescence ||
      old.edgeIntensity != edgeIntensity ||
      old.focusedIndex != focusedIndex ||
      old.cursor != cursor ||
      old.camera.yaw != camera.yaw ||
      old.camera.pitch != camera.pitch ||
      old.camera.focal != camera.focal ||
      !identical(old.flows, flows) ||
      !identical(old.comets, comets) ||
      !identical(old.links, links);
}
