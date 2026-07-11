import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

/// The review verdict and its score cast as ONE procedurally-built shape: a
/// rounded-left label bar whose top and bottom edges swell — through tangent
/// shoulders — into a guardrail-shaped node on the right that holds the score.
/// It is a single continuous outline (no gap, no seam, no glued-on chip); the
/// node takes the guardrail shape, generated per stage so the whole object
/// hardens as the review gets stricter:
///   0 loose    → circle
///   1 balanced → rounded square
///   2 strict   → shield
///   3 paranoid → octagon
/// The node's own perimeter doubles as the score ring.
///
/// Lives in its own file (no backend deps) so the whole badge — every shape,
/// every fill level — is render-testable in isolation and can't drift from
/// what ships. See test/ui/split_pill_preview_test.dart.
const double _vbH = 32; // total height
const double _vbBodyHalf = 11; // body half-height
const double _vbR = 16; // node radius (bulges past the body: 16 > 11)
const double _vbOverlap = 8; // node's left flank overlaps the body by this
const double _vbLabelPad = 14;
const double _vbPhiTop = 232; // where the top shoulder meets the node
const double _vbPhiBot = 128; // 360 - phiTop (mirror)

double _vbRad(double deg) => deg * math.pi / 180.0;

class ReviewVerdictBadge extends StatefulWidget {
  final AppTokens tokens;
  final String verdict;
  final int score;
  final int guardrailStage; // 0=loose, 1=balanced, 2=strict, 3=paranoid

  const ReviewVerdictBadge({
    super.key,
    required this.tokens,
    required this.verdict,
    required this.score,
    required this.guardrailStage,
  });

  @override
  State<ReviewVerdictBadge> createState() => _ReviewVerdictBadgeState();
}

// Stateful purely for TextPainter LIFECYCLE: a CustomPainter has no
// dispose hook, so painters minted in a StatelessWidget.build and handed
// to one are orphaned on every rebuild (caught by leak_tracker). This
// State owns the pair — rebuilds dispose the previous generation, unmount
// disposes the last.
class _ReviewVerdictBadgeState extends State<ReviewVerdictBadge> {
  TextPainter? _labelPainter;
  TextPainter? _scorePainter;

  @override
  void dispose() {
    _labelPainter?.dispose();
    _scorePainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _reviewVerdictColor(widget.verdict);
    final scaler = MediaQuery.textScalerOf(context);
    // Merge onto the ambient default style so the raw TextPainters inherit the
    // app font family (a bare TextStyle would fall to the platform default).
    final base = DefaultTextStyle.of(context).style;

    // Retire the previous generation before minting the new one — the
    // frame's paint always runs after this build, so nothing still holds
    // the old painters.
    _labelPainter?.dispose();
    _scorePainter?.dispose();

    final labelPainter = TextPainter(
      text: TextSpan(
        text: widget.verdict,
        style: base.copyWith(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    _labelPainter = labelPainter;

    final scorePainter = TextPainter(
      text: TextSpan(
        text: '${widget.score}',
        style: base.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    _scorePainter = scorePainter;

    final pillW = _vbLabelPad * 2 + labelPainter.width;
    final nodeCx = pillW - _vbOverlap + _vbR;
    // Only the shield (stage 2) protrudes past the node radius; the rest fit
    // inside _vbR.
    final rightExtent =
        widget.guardrailStage.clamp(0, 3) == 2 ? _vbR * 1.08 : _vbR;

    return SizedBox(
      width: nodeCx + rightExtent + 1.5,
      height: _vbH,
      child: CustomPaint(
        painter: _VerdictBadgePainter(
          color: color,
          score: widget.score,
          guardrailStage: widget.guardrailStage,
          pillW: pillW,
          labelPainter: labelPainter,
          scorePainter: scorePainter,
        ),
      ),
    );
  }
}

/// Preview/eyeball hook — identical to [ReviewVerdictBadge], named so the
/// render harness reads clearly.
@visibleForTesting
class ReviewVerdictBadgePreview extends StatelessWidget {
  final AppTokens tokens;
  final String verdict;
  final int score;
  final int guardrailStage;
  const ReviewVerdictBadgePreview({
    super.key,
    required this.tokens,
    required this.verdict,
    required this.score,
    required this.guardrailStage,
  });

  @override
  Widget build(BuildContext context) => ReviewVerdictBadge(
        tokens: tokens,
        verdict: verdict,
        score: score,
        guardrailStage: guardrailStage,
      );
}

Color _reviewVerdictColor(String verdict) =>
    AppSeverityPalette.fromVerdict(verdict);

class _VerdictBadgePainter extends CustomPainter {
  final Color color;
  final int score;
  final int guardrailStage;
  final double pillW;
  final TextPainter labelPainter;
  final TextPainter scorePainter;

  const _VerdictBadgePainter({
    required this.color,
    required this.score,
    required this.guardrailStage,
    required this.pillW,
    required this.labelPainter,
    required this.scorePainter,
  });

  static const double _cy = _vbH / 2;

  Offset _onNode(double nodeCx, double phiDeg, [double scale = 1.0]) {
    final p = _vbRad(phiDeg);
    return Offset(nodeCx + _vbR * scale * math.cos(p),
        _cy + _vbR * scale * math.sin(p));
  }

  // G1 control point: horizontal at the body edge, tangent to the node at P.
  Offset _shoulderCtrl(Offset p, double phiDeg, double edgeY) {
    final phi = _vbRad(phiDeg);
    final tx = -math.sin(phi), ty = math.cos(phi);
    final s = (edgeY - p.dy) / ty;
    return Offset(p.dx + s * tx, edgeY);
  }

  // ── Flat-topped node box (stages 1 and 3) ────────────────────────────────
  // The rounded square and the stop-sign octagon share one generous 28×26 box
  // so the score sits with real air around it (the old 17×24 box read as
  // squished). It leans slightly right of the node centre so the node
  // protrudes out of the bar, and its left side stays compact at the neck:
  // the fill crossing the opening traces real, short shape edges hugging the
  // node — never a stray line into the label.
  static const double _flatHalf = 13.0; // half-height (box is 26 tall)
  static const double _flatL = -13.0; // left edge, relative to nodeCx
  static const double _flatR = 15.0; // right edge, relative to nodeCx
  // Octagon corner run (45° facets), sized for a ~26 regular octagon:
  // (26 − 26/(1+√2)) / 2.
  static const double _octC = 7.6;

  // Appends the node's right profile (from P_top, clockwise through top/right/
  // bottom, to P_bot) to the outline [path]. These are the ROUND guardrail
  // shapes' visible faces — circle / shield. (Stages 1 and 3 — rounded square
  // and octagon — are built in [_build]: their flat tops want S-curve
  // shoulders, not the circle-tangent ones the round shapes use.)
  void _rightProfile(Path path, int stage, double nodeCx) {
    final rect = Rect.fromCircle(center: Offset(nodeCx, _cy), radius: _vbR);

    void line(Offset o) => path.lineTo(o.dx, o.dy);
    void arc(double fromDeg, double toDeg) =>
        path.arcTo(rect, _vbRad(fromDeg), _vbRad(toDeg - fromDeg), false);

    if (stage == 2) {
      // strict — heraldic shield: wide flat shoulders → short point
      final tShoulder = Offset(nodeCx + _vbR * 0.55, _cy - _vbR * 0.82);
      final bShoulder = Offset(nodeCx + _vbR * 0.55, _cy + _vbR * 0.82);
      final tip = Offset(nodeCx + _vbR * 1.08, _cy);
      arc(_vbPhiTop, 258); // round the top-left corner
      line(tShoulder); // flat top edge
      line(tip); // straight side down to the point
      line(bShoulder); // straight side back up
      line(_onNode(nodeCx, 102)); // flat bottom edge
      arc(102, _vbPhiBot); // round the bottom-left corner
    } else {
      // loose — circle
      arc(_vbPhiTop, _vbPhiBot + 360);
    }
  }

  /// The score gauge's two runs, which together are the node's IDEAL shape as
  /// a closed loop (a true circle, a fully-rounded square, a flat-backed
  /// shield, a true stop-sign octagon):
  ///
  ///  * `visible` — the free perimeter, top neck → clockwise → bottom neck.
  ///    The sweep covers this first, exactly like it always has.
  ///  * `hidden`  — the shape's contour over the protruding pill, traversed
  ///    bottom neck → top neck. Appended after `visible`, it fills LAST: the
  ///    score flows over the opening near 100, always tracing the shape's own
  ///    edge (arc / rounded corners / facets / pointed back — never a flat
  ///    closure).
  ///
  /// They share endpoints exactly, so concatenated they form one seamless
  /// loop and the fill is a single connected sweep from the top neck.
  (Path, Path) _scoreRings(int stage, double nodeCx) {
    final rect = Rect.fromCircle(center: Offset(nodeCx, _cy), radius: _vbR);
    switch (stage.clamp(0, 3)) {
      case 0: // circle
        final visible = Path()
          ..addArc(rect, _vbRad(_vbPhiTop), _vbRad(_vbPhiBot + 360 - _vbPhiTop));
        final hidden = Path()
          ..addArc(rect, _vbRad(_vbPhiBot), _vbRad(_vbPhiTop - _vbPhiBot));
        return (visible, hidden);

      case 1: // rounded square — all four corners rounded; the left pair
        // (over the pill) form the hidden run.
        final xR = nodeCx + _flatR;
        final xL = nodeCx + _flatL;
        const yT = _cy - _flatHalf, yB = _cy + _flatHalf;
        const cr = _vbR * 0.42;
        final visible = Path()
          ..moveTo(xL + cr, yT)
          ..lineTo(xR - cr, yT) // top edge
          ..quadraticBezierTo(xR, yT, xR, yT + cr) // top-right corner
          ..lineTo(xR, yB - cr) // right edge
          ..quadraticBezierTo(xR, yB, xR - cr, yB) // bottom-right corner
          ..lineTo(xL + cr, yB); // bottom edge
        final hidden = Path()
          ..moveTo(xL + cr, yB)
          ..quadraticBezierTo(xL, yB, xL, yB - cr) // bottom-left corner
          ..lineTo(xL, yT + cr) // left edge
          ..quadraticBezierTo(xL, yT, xL + cr, yT); // top-left corner
        return (visible, hidden);

      case 2: // shield — outer profile; the hidden run CONTINUES THE SHAPE:
        // the back comes to a gentle point mirroring the front tip (never a
        // flat line, never a bulged circle arc).
        final tShoulder = Offset(nodeCx + _vbR * 0.55, _cy - _vbR * 0.82);
        final bShoulder = Offset(nodeCx + _vbR * 0.55, _cy + _vbR * 0.82);
        final tip = Offset(nodeCx + _vbR * 1.08, _cy);
        final backTip = Offset(nodeCx - _vbR * 1.0, _cy);
        final pTop = _onNode(nodeCx, _vbPhiTop);
        final pBot = _onNode(nodeCx, _vbPhiBot);
        final visible = Path()
          ..addArc(rect, _vbRad(_vbPhiTop), _vbRad(258 - _vbPhiTop))
          ..lineTo(tShoulder.dx, tShoulder.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(bShoulder.dx, bShoulder.dy)
          ..lineTo(_onNode(nodeCx, 102).dx, _onNode(nodeCx, 102).dy)
          ..arcTo(rect, _vbRad(102), _vbRad(_vbPhiBot - 102), false);
        final hidden = Path()
          ..moveTo(pBot.dx, pBot.dy)
          ..lineTo(backTip.dx, backTip.dy)
          ..lineTo(pTop.dx, pTop.dy);
        return (visible, hidden);

      default: // octagon — true stop-sign; the hidden run is its left corner
        // (bottom-left facet, left edge, top-left facet).
        final xL = nodeCx + _flatL, xR = nodeCx + _flatR;
        const yT = _cy - _flatHalf, yB = _cy + _flatHalf;
        final visible = Path()
          ..moveTo(xL + _octC, yT)
          ..lineTo(xR - _octC, yT) // top edge
          ..lineTo(xR, yT + _octC) // top-right facet
          ..lineTo(xR, yB - _octC) // right edge
          ..lineTo(xR - _octC, yB) // bottom-right facet
          ..lineTo(xL + _octC, yB); // bottom edge
        final hidden = Path()
          ..moveTo(xL + _octC, yB)
          ..lineTo(xL, yB - _octC) // bottom-left facet
          ..lineTo(xL, yT + _octC) // left edge
          ..lineTo(xL + _octC, yT); // top-left facet
        return (visible, hidden);
    }
  }

  // Left cap that rhymes with the right node — the badge speaks one shape
  // language at both ends. [inset] is where the flat top/bottom meet the cap
  // (every cap still reaches x=0 so the left edge stays aligned).
  double _leftInset(int stage) => switch (stage) {
        0 => _vbBodyHalf, // full semicircle
        1 => _vbBodyHalf * 0.6, // rounded corners
        2 => _vbBodyHalf * 0.5, // shallow bevel
        _ => _vbBodyHalf * 0.72, // deep 45° facet (octagon)
      };

  // Draws the left cap from the current point (inset, cy+bodyHalf) up to
  // (inset, cy-bodyHalf); the outline then closes to the moveTo start.
  void _leftCap(Path o, int stage, double inset) {
    const top = _cy - _vbBodyHalf, bot = _cy + _vbBodyHalf;
    switch (stage) {
      case 0: // round — true semicircle
        o.arcTo(
            Rect.fromCircle(center: const Offset(_vbBodyHalf, _cy),
                radius: _vbBodyHalf),
            _vbRad(90), _vbRad(180), false);
        break;
      case 1: // rounded corners
        o.quadraticBezierTo(0, bot, 0, bot - inset);
        o.lineTo(0, top + inset);
        o.quadraticBezierTo(0, top, inset, top);
        break;
      default: // chamfered facet (shield, octagon)
        o.lineTo(0, bot - inset);
        o.lineTo(0, top + inset);
        o.lineTo(inset, top);
        break;
    }
  }

  /// Builds the single continuous outline + the node's gauge runs.
  /// Returns (outline, ringVisible, ringHidden, nodeCx, neckX).
  (Path, Path, Path, double, double) _build(int stage) {
    final nodeCx = pillW - _vbOverlap + _vbR;
    final inset = _leftInset(stage);
    final outline = Path()..moveTo(inset, _cy - _vbBodyHalf);

    if (stage == 1 || stage == 3) {
      // FLAT-TOPPED NODES (rounded square, stop-sign octagon) — their flat
      // top/bottom want S-curve shoulders (cubics) that leave the body
      // horizontal and arrive at the node's face horizontal, instead of the
      // round shapes' circle-tangent quadratics. `faceL` is where the flat
      // top/bottom edge begins; the octagon's hidden top-left/bottom-left
      // corner facets live only in the score ring.
      const yT = _cy - _flatHalf, yB = _cy + _flatHalf;
      final xR = nodeCx + _flatR;
      final double faceL;
      if (stage == 1) {
        faceL = nodeCx + _flatL + _vbR * 0.42; // after the rounded corner
      } else {
        faceL = nodeCx + _flatL + _octC; // after the 45° facet
      }
      final sx = faceL - 7; // a longer run makes the swell read as graceful
      final mx = (sx + faceL) / 2;
      outline
        ..lineTo(sx, _cy - _vbBodyHalf)
        ..cubicTo(mx, _cy - _vbBodyHalf, mx, yT, faceL, yT);
      if (stage == 1) {
        const cr = _vbR * 0.42;
        outline
          ..lineTo(xR - cr, yT)
          ..quadraticBezierTo(xR, yT, xR, yT + cr)
          ..lineTo(xR, yB - cr)
          ..quadraticBezierTo(xR, yB, xR - cr, yB);
      } else {
        outline
          ..lineTo(xR - _octC, yT) // top edge
          ..lineTo(xR, yT + _octC) // top-right facet
          ..lineTo(xR, yB - _octC) // right edge
          ..lineTo(xR - _octC, yB); // bottom-right facet
      }
      outline
        ..lineTo(faceL, yB)
        ..cubicTo(mx, yB, mx, _cy + _vbBodyHalf, sx, _cy + _vbBodyHalf)
        ..lineTo(inset, _cy + _vbBodyHalf);
    } else {
      final pTop = _onNode(nodeCx, _vbPhiTop);
      final pBot = _onNode(nodeCx, _vbPhiBot);
      final qTop = _shoulderCtrl(pTop, _vbPhiTop, _cy - _vbBodyHalf);
      final qBot = _shoulderCtrl(pBot, _vbPhiBot, _cy + _vbBodyHalf);
      final shoulderX = math.min(qTop.dx, nodeCx - _vbR) - 3;
      outline
        ..lineTo(shoulderX, _cy - _vbBodyHalf)
        ..quadraticBezierTo(qTop.dx, qTop.dy, pTop.dx, pTop.dy);
      _rightProfile(outline, stage, nodeCx);
      outline
        ..quadraticBezierTo(qBot.dx, qBot.dy, shoulderX, _cy + _vbBodyHalf)
        ..lineTo(inset, _cy + _vbBodyHalf);
    }

    _leftCap(outline, stage, inset);
    outline.close();

    final (ringVisible, ringHidden) = _scoreRings(stage, nodeCx);
    return (outline, ringVisible, ringHidden, nodeCx, nodeCx - _vbR);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (outline, ringVisible, ringHidden, nodeCx, neckX) =
        _build(guardrailStage);

    // One shape: a single fill and a single outer stroke.
    canvas.drawPath(
      outline,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    // A soft core glow in the node gives the score end depth without a seam.
    // Clipped to the silhouette so it can only brighten the shape's interior,
    // never haze outside the outline.
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawCircle(
      Offset(nodeCx, _cy),
      _vbR * 1.15,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.13),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(nodeCx, _cy), radius: _vbR * 1.15)),
    );
    canvas.restore();
    canvas.drawPath(
      outline,
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeJoin = StrokeJoin.round,
    );

    // The score gauge: ONE seamless loop — the node's ideal shape — swept by
    // ONE connected fill, exactly like a normal progress ring. The sweep
    // starts at the top neck junction and runs clockwise around the VISIBLE
    // perimeter first; the overlap contour (the shape's edge over the
    // protruding pill) fills LAST — the score flows over the opening as it
    // approaches 100 and the loop closes seamlessly. A faint track of the
    // full loop underneath keeps the not-yet-filled remainder — including the
    // overlap contour — legible as the shape at every score.
    const ringWidth = 2.2;
    final ring = Path.from(ringVisible)
      ..extendWithPath(ringHidden, Offset.zero)
      ..close();
    canvas.drawPath(
      ring,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeJoin = StrokeJoin.round,
    );
    final frac = (score / 100).clamp(0.0, 1.0);
    final metrics = ring.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
      final drawLength = total * frac;
      final arc = Paint()
        ..color = color.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      var drawn = 0.0;
      for (final m in metrics) {
        if (drawn >= drawLength) break;
        final segLen = (drawLength - drawn).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(0, segLen), arc);
        drawn += m.length;
      }
    }

    // Label centred in the body zone; score centred in the full loop's bounds
    // (its horizontal midpoint shifts per shape) so the fill never clips it.
    labelPainter.paint(
      canvas,
      Offset((neckX - labelPainter.width) / 2 + 2, _cy - labelPainter.height / 2),
    );
    scorePainter.paint(
      canvas,
      Offset(ring.getBounds().center.dx - scorePainter.width / 2,
          _cy - scorePainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_VerdictBadgePainter old) =>
      old.color != color ||
      old.score != score ||
      old.guardrailStage != guardrailStage ||
      old.pillW != pillW ||
      // Compare the rendered text, not just color: two unrecognized verdict
      // strings both fall to the neutral fallback colour, so a label swap
      // between them wouldn't otherwise repaint. TextPainter.text is a
      // TextSpan with value equality, so this never causes a spurious repaint.
      old.labelPainter.text != labelPainter.text ||
      old.scorePainter.text != scorePainter.text;
}
