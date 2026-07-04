import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// Shared geometry for the "shattered mosaic" look: a solid surface split
/// into equal cells by jagged, per-open cracks. Both the right-click context
/// menu's chip rail and the [SplitPillButton] render from these primitives so
/// the two controls share one visual language (and can't drift apart).

/// Fraction of a cell's nominal width a seam vertex may bleed into either
/// neighbour. Shared by the painter, the clipper, and the positioning math.
/// 0.06 = ±6 %. Kept deliberately small: on a narrow two-cell pill a larger
/// swing reads as a ragged gap rather than a crack, and the halves stop
/// looking like one control.
const double kMosaicJitterFrac = 0.06;

/// One crack between two mosaic cells. Vertices in normalised space
/// (dx [-1..1], dy [0..1]); painter + clipper scale identically.
class MosaicSeam {
  final List<Offset> vertices;
  final double widthScale; // 0.6..1.4
  final double alphaScale; // 0.7..1.3
  final List<double> segmentWidthScales; // per-segment, length = vertices - 1
  const MosaicSeam({
    required this.vertices,
    required this.widthScale,
    required this.alphaScale,
    required this.segmentWidthScales,
  });
}

/// Generates one randomised crack. Call once per seam at mount time and hold
/// the result — regenerating on every build would make the cracks shimmer.
MosaicSeam generateMosaicSeam(math.Random rng) {
  final segments = 4 + rng.nextInt(5);
  final ys = <double>[0.0];
  for (var i = 1; i < segments; i++) {
    ys.add(rng.nextDouble());
  }
  ys.add(1.0);
  ys.sort();
  // The top and bottom vertices are pinned to dx = 0 so adjacent cells meet
  // the rail's top/bottom edges at exactly the same x — the crack only wanders
  // in the interior, which is what keeps the cells reading as squarely shaped.
  final vertices = <Offset>[
    for (var i = 0; i < ys.length; i++)
      Offset(
        (i == 0 || i == ys.length - 1)
            ? 0.0
            : (rng.nextDouble() * 2.0 - 1.0) *
                (rng.nextDouble() < 0.3 ? 0.9 : 0.5),
        ys[i],
      ),
  ];
  return MosaicSeam(
    vertices: vertices,
    widthScale: 0.6 + rng.nextDouble() * 0.8,
    alphaScale: 0.7 + rng.nextDouble() * 0.6,
    segmentWidthScales: List.generate(
      vertices.length - 1,
      (_) => 0.7 + rng.nextDouble() * 0.6,
    ),
  );
}

/// Clips a mosaic cell to its polygon between adjacent seams.
/// [leftNominal] / [rightNominal] are the nominal seam x in cell-local
/// coords. Vertices jitter ±[jitter] from those nominals using the same
/// formula [ShatteredSeamPainter] uses — pixel-aligned.
class MosaicCellClipper extends CustomClipper<Path> {
  final double leftNominal;
  final double rightNominal;
  final double jitter;
  final MosaicSeam? leftSeam;
  final MosaicSeam? rightSeam;

  MosaicCellClipper({
    required this.leftNominal,
    required this.rightNominal,
    required this.jitter,
    required this.leftSeam,
    required this.rightSeam,
  });

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // Top-left.
    path.moveTo(
      leftSeam != null
          ? leftNominal + leftSeam!.vertices.first.dx * jitter
          : 0,
      0,
    );
    // Top-right.
    path.lineTo(
      rightSeam != null
          ? rightNominal + rightSeam!.vertices.first.dx * jitter
          : w,
      0,
    );
    // Right edge (seam top → bottom, or straight down).
    if (rightSeam != null) {
      for (var k = 1; k < rightSeam!.vertices.length; k++) {
        final v = rightSeam!.vertices[k];
        path.lineTo(rightNominal + v.dx * jitter, v.dy * h);
      }
    } else {
      path.lineTo(w, h);
    }
    // Bottom-left.
    if (leftSeam != null) {
      final v = leftSeam!.vertices.last;
      path.lineTo(leftNominal + v.dx * jitter, h);
    } else {
      path.lineTo(0, h);
    }
    // Left edge (seam bottom → top, reversed).
    if (leftSeam != null) {
      for (var k = leftSeam!.vertices.length - 2; k >= 0; k--) {
        final v = leftSeam!.vertices[k];
        path.lineTo(leftNominal + v.dx * jitter, v.dy * h);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(MosaicCellClipper old) =>
      old.leftNominal != leftNominal ||
      old.rightNominal != rightNominal ||
      old.jitter != jitter ||
      !identical(old.leftSeam, leftSeam) ||
      !identical(old.rightSeam, rightSeam);
}

/// Draws each [MosaicSeam] as a piecewise-stroked polyline so per-segment
/// width variation carries through (a single `Path` would lock the whole
/// crack to one stroke width). Vertex `dx` is scaled by [kMosaicJitterFrac]
/// of the cell width so a crack can intrude that far into either neighbour
/// but no further.
class ShatteredSeamPainter extends CustomPainter {
  final int cellCount;
  final List<MosaicSeam> seams;
  final Color baseColor;
  final double baseAlpha;
  final double baseWidth;

  /// Normalised x (0..1) of each interior seam, length `cellCount - 1`, so a
  /// bar can carry cells of *unequal* width. When null the seams fall on the
  /// equal-cell grid (`size.width / cellCount`) — byte-identical to the
  /// original behaviour, which the two equal-cell callers rely on.
  final List<double>? seamFractions;

  ShatteredSeamPainter({
    required this.cellCount,
    required this.seams,
    required this.baseColor,
    required this.baseAlpha,
    required this.baseWidth,
    this.seamFractions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cellCount < 2 || seams.isEmpty) return;
    final fractions = seamFractions;
    final equalCellWidth = size.width / cellCount;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < seams.length && i < cellCount - 1; i++) {
      final double nominalX;
      final double jitterCeiling;
      if (fractions == null) {
        nominalX = equalCellWidth * (i + 1);
        jitterCeiling = equalCellWidth * kMosaicJitterFrac;
      } else {
        // Weighted cells: the seam sits at its fraction and its crack may only
        // bleed as far as the NARROWER of its two adjacent cells — so a wide
        // neighbour never lets a crack wander across a small cell.
        nominalX = fractions[i] * size.width;
        final leftX = i == 0 ? 0.0 : fractions[i - 1] * size.width;
        final rightX =
            i == fractions.length - 1 ? size.width : fractions[i + 1] * size.width;
        jitterCeiling =
            math.min(nominalX - leftX, rightX - nominalX) * kMosaicJitterFrac;
      }
      final seam = seams[i];
      paint.color = baseColor.withValues(
        alpha: (baseAlpha * seam.alphaScale).clamp(0.0, 1.0),
      );
      final pts = <Offset>[
        for (final v in seam.vertices)
          Offset(nominalX + v.dx * jitterCeiling, v.dy * size.height),
      ];
      for (var k = 0; k < pts.length - 1; k++) {
        paint.strokeWidth =
            baseWidth * seam.widthScale * seam.segmentWidthScales[k];
        canvas.drawLine(pts[k], pts[k + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ShatteredSeamPainter old) =>
      old.cellCount != cellCount ||
      old.baseColor != baseColor ||
      old.baseAlpha != baseAlpha ||
      old.baseWidth != baseWidth ||
      !identical(old.seams, seams) ||
      !listEquals(old.seamFractions, seamFractions);
}
