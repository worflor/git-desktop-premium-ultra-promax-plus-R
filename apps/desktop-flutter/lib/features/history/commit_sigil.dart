import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../backend/commit_fingerprint.dart';
import '../../ui/tokens.dart';

/// ═════════════════════════════════════════════════════════════════════════
/// COMMIT SIGIL — visual rendering of the 25D fingerprint
/// ═════════════════════════════════════════════════════════════════════════
///
/// Renders the 25-component Walsh-Hadamard fingerprint as a 5×5 grid of
/// signed cells. Each cell is positive (top-axis token color) or negative
/// (deletion-axis token color), with intensity proportional to the cell's
/// magnitude relative to the fingerprint's own peak. The same commit
/// renders the same sigil forever; cherry-picks render identically;
/// refactors that touched the same neighborhood look like dialect-
/// variations of one shape. Cheap: a 25-cell paint per commit.
///
/// The grid layout is the canonical mask order — row-major reading of
/// the 25 masks in their declared order:
///
///   row 0: L0 L1 L2 L3 L4
///   row 1: L5 L6 L7 U0 U1
///   row 2: U2 U3 U4 U5 U6
///   row 3: U7 X0 X1 X2 X3
///   row 4: X4 X5 X6 X7 FFFF
/// ═════════════════════════════════════════════════════════════════════════

class CommitSigil extends StatelessWidget {
  final Float32List fingerprint;
  final AppTokens tokens;
  final double size;

  const CommitSigil({
    super.key,
    required this.fingerprint,
    required this.tokens,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SigilPainter(
          fingerprint: fingerprint,
          posColor: tokens.hypercubePositive,
          negColor: tokens.hypercubeNegative,
          accentColor: tokens.accentBright,
        ),
      ),
    );
  }
}

class _SigilPainter extends CustomPainter {
  final Float32List fingerprint;
  final Color posColor;
  final Color negColor;
  final Color accentColor;

  _SigilPainter({
    required this.fingerprint,
    required this.posColor,
    required this.negColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fingerprint.length != kFingerprintDim) return;

    // Per-fingerprint normalisation — each sigil uses its own peak so
    // every commit's glyph spans the full color range. Cosine across
    // commits stays well-defined (it's invariant to magnitude); the
    // visual is just internally calibrated.
    var peak = 0.0;
    for (var i = 0; i < kFingerprintDim; i++) {
      final a = fingerprint[i].abs();
      if (a > peak) peak = a;
    }
    if (peak <= 0) {
      // Pure-rename / mode-only / zero-churn commit — render a tiny
      // neutral dot so the slot doesn't read as a missing thing.
      final paint = Paint()
        ..color = posColor.withValues(alpha: 0.08);
      canvas.drawCircle(
          Offset(size.width / 2, size.height / 2), 1.5, paint);
      return;
    }

    // Cell geometry — 5×5 grid with a 1px gutter between cells.
    final cell = (size.width - 4) / 5; // 4 gutters
    final paint = Paint();

    var idx = 0;
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 5; col++) {
        if (idx >= kFingerprintDim) break;
        final v = fingerprint[idx] / peak; // [-1, 1]
        final mag = v.abs();
        // Skip near-zero cells — let the bg show through.
        if (mag > 0.04) {
          final c = v >= 0 ? posColor : negColor;
          paint.color = c.withValues(alpha: 0.2 + 0.8 * mag);
          final x = col * (cell + 1);
          final y = row * (cell + 1);
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
        idx++;
      }
    }

    // Global cell (FFFF, idx 24) gets a thin accent rim — the
    // "everything-summed" coefficient is the most informative single
    // value, visually anchor it.
    final globalMag = (fingerprint[24] / peak).abs();
    if (globalMag > 0.1) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = accentColor.withValues(alpha: 0.35 + 0.5 * globalMag);
      final col = 4, row = 4;
      final x = col * (cell + 1);
      final y = row * (cell + 1);
      canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), ring);
    }
  }

  @override
  bool shouldRepaint(_SigilPainter old) =>
      old.fingerprint != fingerprint ||
      old.posColor != posColor ||
      old.negColor != negColor ||
      old.accentColor != accentColor;
}
