// Not a pass/fail test — a render harness for the fused verdict+score badge.
// One continuous silhouette (rounded-left body → tangent shoulders → a
// guardrail-shaped node), using the ORIGINAL guardrail shapes:
//   0 circle · 1 rounded square · 2 shield · 3 octagon-with-battlements
// Text is suppressed (flutter_test has no real font — Ahem boxes obscure the
// shape); the real-widget/real-font check lives in test/ui/. Run:
//   flutter test test/features/changes/verdict_badge_preview_test.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/ui/tokens.dart';

class _BadgeSpec {
  final String verdict;
  final Color color;
  final int score;
  final int stage;
  const _BadgeSpec(this.verdict, this.color, this.score, this.stage);
}

double _rad(double deg) => deg * math.pi / 180.0;

const double _bodyHalf = 10.0;
const double _r = 14.0;
const double _h = 28.0;
const double _cy = _h / 2;
const double _phiTopDeg = 232.0;
const double _phiBotDeg = 128.0;

class _Silhouette {
  final Path outline;
  final Path ring;
  final double nodeCx;
  final double width;
  final double neckX;
  const _Silhouette(
      this.outline, this.ring, this.nodeCx, this.width, this.neckX);
}

Offset _onNode(double nodeCx, double phiDeg, [double scale = 1.0]) {
  final p = _rad(phiDeg);
  return Offset(
      nodeCx + _r * scale * math.cos(p), _cy + _r * scale * math.sin(p));
}

Offset _shoulderCtrl(Offset p, double phiDeg, double edgeY) {
  final phi = _rad(phiDeg);
  final tx = -math.sin(phi), ty = math.cos(phi);
  final s = (edgeY - p.dy) / ty;
  return Offset(p.dx + s * tx, edgeY);
}

// The ORIGINAL guardrail shapes, traced as the right-protruding node from
// P_top clockwise through top/right/bottom to P_bot. (Stage 1's rounded square
// is built in _buildSilhouette — its flat top wants S-curve shoulders.)
void _rightProfile(Path path, Path ring, int stage, double nodeCx) {
  final pBot = _onNode(nodeCx, _phiBotDeg);
  final rect = Rect.fromCircle(center: Offset(nodeCx, _cy), radius: _r);

  void line(Offset o) {
    path.lineTo(o.dx, o.dy);
    ring.lineTo(o.dx, o.dy);
  }

  void arc(double fromDeg, double toDeg) {
    path.arcTo(rect, _rad(fromDeg), _rad(toDeg - fromDeg), false);
    ring.arcTo(rect, _rad(fromDeg), _rad(toDeg - fromDeg), false);
  }

  ring.moveTo(_onNode(nodeCx, _phiTopDeg).dx, _onNode(nodeCx, _phiTopDeg).dy);

  switch (stage) {
    case 0: // loose — circle
      arc(_phiTopDeg, _phiBotDeg + 360);
      break;

    case 2: // strict — heraldic shield: wide flat shoulders → short point
      final tShoulder = Offset(nodeCx + _r * 0.55, _cy - _r * 0.82);
      final bShoulder = Offset(nodeCx + _r * 0.55, _cy + _r * 0.82);
      final tip = Offset(nodeCx + _r * 1.08, _cy);
      arc(_phiTopDeg, 258); // round the top-left corner
      line(tShoulder); // flat top edge
      line(tip); // straight side down to the point
      line(bShoulder); // straight side back up
      line(_onNode(nodeCx, 102)); // flat bottom edge
      arc(102, _phiBotDeg); // round the bottom-left corner
      break;

    default: // paranoid — octagon with subtle battlements at the cardinals
      void facet(double a, bool notch) {
        if (notch) {
          line(_onNode(nodeCx, a - 6, 1.0));
          line(_onNode(nodeCx, a - 3.5, 0.84));
          line(_onNode(nodeCx, a + 3.5, 0.84));
          line(_onNode(nodeCx, a + 6, 1.0));
        } else {
          line(_onNode(nodeCx, a));
        }
      }

      facet(270, true); // top merlon
      facet(315, false);
      facet(0, true); // right merlon
      facet(45, false);
      facet(90, true); // bottom merlon
      line(pBot);
      break;
  }
}

// Left cap that rhymes with the right node — the badge speaks one shape
// language at both ends. `inset` is where the flat top/bottom meet the cap
// (all caps still reach x=0 so the left edge stays aligned).
double _leftInset(int stage) => switch (stage) {
      0 => _bodyHalf, // full semicircle
      1 => _bodyHalf * 0.6, // rounded corners
      2 => _bodyHalf * 0.5, // shallow bevel
      _ => _bodyHalf * 0.72, // deep 45° facet (octagon)
    };

// Draws the left cap from the current point (inset, cy+bodyHalf) up to
// (inset, cy-bodyHalf); the outline closes back to the moveTo start.
void _leftCap(Path o, int stage, double inset) {
  const top = _cy - _bodyHalf, bot = _cy + _bodyHalf;
  switch (stage) {
    case 0: // round — true semicircle
      o.arcTo(
          Rect.fromCircle(center: const Offset(_bodyHalf, _cy),
              radius: _bodyHalf),
          _rad(90), _rad(180), false);
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

_Silhouette _buildSilhouette(int stage, double pillW) {
  const overlap = 8.0;
  final nodeCx = pillW - overlap + _r;
  final inset = _leftInset(stage);
  final outline = Path()..moveTo(inset, _cy - _bodyHalf);
  final ring = Path();

  if (stage == 1) {
    // ROUNDED SQUARE — flat top/bottom, so shoulders are S-curves (cubic) that
    // leave the body horizontal and arrive at the square's face horizontal.
    const half = 12.0;
    final xR = nodeCx + _r * 0.95;
    final xL = nodeCx - _r * 0.30;
    const yT = _cy - half, yB = _cy + half;
    const cr = _r * 0.42;
    final sx = xL - 5;
    final mx = (sx + xL) / 2;
    void line(Offset o) {
      outline.lineTo(o.dx, o.dy);
      ring.lineTo(o.dx, o.dy);
    }

    void quad(Offset c, Offset e) {
      outline.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
      ring.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
    }

    outline
      ..lineTo(sx, _cy - _bodyHalf)
      ..cubicTo(mx, _cy - _bodyHalf, mx, yT, xL, yT);
    ring.moveTo(xL, yT);
    line(Offset(xR - cr, yT));
    quad(Offset(xR, yT), Offset(xR, yT + cr));
    line(Offset(xR, yB - cr));
    quad(Offset(xR, yB), Offset(xR - cr, yB));
    line(Offset(xL, yB));
    ring.lineTo(xL, yT); // close the ring loop over the opening (neck)
    outline
      ..cubicTo(mx, yB, mx, _cy + _bodyHalf, sx, _cy + _bodyHalf)
      ..lineTo(inset, _cy + _bodyHalf);
  } else {
    final pTop = _onNode(nodeCx, _phiTopDeg);
    final pBot = _onNode(nodeCx, _phiBotDeg);
    final qTop = _shoulderCtrl(pTop, _phiTopDeg, _cy - _bodyHalf);
    final qBot = _shoulderCtrl(pBot, _phiBotDeg, _cy + _bodyHalf);
    final shoulderX = math.min(qTop.dx, nodeCx - _r) - 3;
    outline
      ..lineTo(shoulderX, _cy - _bodyHalf)
      ..quadraticBezierTo(qTop.dx, qTop.dy, pTop.dx, pTop.dy);
    _rightProfile(outline, ring, stage, nodeCx);
    // Close the ring loop over the opening (neck) so the score can fill all
    // the way round like a normal progress bar. The circle follows its own
    // arc; the faceted shapes take a straight chord across the neck.
    if (stage == 0) {
      ring.arcTo(Rect.fromCircle(center: Offset(nodeCx, _cy), radius: _r),
          _rad(_phiBotDeg), _rad(_phiTopDeg - _phiBotDeg), false);
    } else {
      ring.lineTo(pTop.dx, pTop.dy);
    }
    outline
      ..quadraticBezierTo(qBot.dx, qBot.dy, shoulderX, _cy + _bodyHalf)
      ..lineTo(inset, _cy + _bodyHalf);
  }

  _leftCap(outline, stage, inset);
  outline.close();

  final rightExtent = switch (stage) {
    1 => _r * 0.95,
    2 => _r * 1.18,
    _ => _r,
  };
  return _Silhouette(
      outline, ring, nodeCx, nodeCx + rightExtent + 1, nodeCx - _r);
}

double _paintBadge(Canvas canvas, _BadgeSpec spec, Offset origin) {
  const labelPad = 12.0;
  final color = spec.color;
  const pillW = labelPad * 2 + 44; // fixed body width for shape-only eyeballing
  final s = _buildSilhouette(spec.stage, pillW);

  canvas.save();
  canvas.translate(origin.dx, origin.dy);

  canvas.drawPath(s.outline,
      Paint()..color = color.withValues(alpha: 0.12)..style = PaintingStyle.fill);
  canvas.save();
  canvas.clipPath(s.outline);
  canvas.drawCircle(
      Offset(s.nodeCx, _cy),
      _r * 1.15,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.13),
          color.withValues(alpha: 0.0),
        ]).createShader(
            Rect.fromCircle(center: Offset(s.nodeCx, _cy), radius: _r * 1.15)));
  canvas.restore();
  canvas.drawPath(
      s.outline,
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round);

  const ringWidth = 2.0;
  final frac = (spec.score / 100).clamp(0.0, 1.0);
  final metrics = s.ring.computeMetrics().toList();
  final total = metrics.fold<double>(0, (a, m) => a + m.length);
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

  canvas.restore();
  return s.width;
}

void main() {
  test('verdict badge preview', () async {
    const specs = <_BadgeSpec>[
      _BadgeSpec('Ready', AppSeverityPalette.safe, 92, 0),
      _BadgeSpec('Mostly ready', AppSeverityPalette.info, 81, 1),
      _BadgeSpec('Needs attention', AppSeverityPalette.caution, 81, 2),
      _BadgeSpec('Block', AppSeverityPalette.critical, 40, 3),
    ];
    const zoom = 5.0;
    const size = Size(240 * zoom, 240 * zoom);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E1216));
    canvas.scale(zoom);
    var y = 26.0;
    for (final s in specs) {
      _paintBadge(canvas, s, Offset(24, y));
      y += 52;
    }
    final picture = recorder.endRecording();
    final image =
        await picture.toImage(size.width.round(), size.height.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.preview/verdict_badge.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}
