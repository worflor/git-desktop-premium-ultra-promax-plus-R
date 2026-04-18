// LogosGlyphStrip — a compact visual-first status row for files.
//
// Used at the top of file context menus to surface the engine's read
// of a file without burdening the user with prose. Every glyph
// corresponds to a signal the engine already computes:
//
//   • Tangle bar          — TangleMap contribution, as a horizontal fill
//   • Health dot          — node-level F contribution, colored by intensity
//   • Finding glyphs      — one small distinctive shape per spaghetti type
//                           (god-class, localized/dead-code, bridge)
//   • Proposal indicators — tiny marks when this file is in a refactor
//                           proposal (↔ merge, ⇀⇁ extract, ⊥ decouple)
//
// Glyphs are rendered minimally (thin strokes, single-color, small) so
// the strip reads as decoration at a glance and as data on attention.

import 'package:flutter/material.dart';

import '../backend/logos_refactor.dart';
import '../backend/logos_spaghetti.dart';
import 'tokens.dart';

/// Everything the strip needs about one file.
class LogosFileStatus {
  /// 0..1 — contribution to the global tangle index.
  final double tangle;

  /// Spaghetti findings specific to this file. Any subset; empty =
  /// no finding.
  final List<SpaghettiFinding> findings;

  /// Refactor proposals that name this file. Any subset.
  final List<RefactorProposal> proposals;

  const LogosFileStatus({
    this.tangle = 0.0,
    this.findings = const [],
    this.proposals = const [],
  });

  /// A status is "silent" when the engine has nothing interesting to
  /// say about this file. Strip renders an empty (hidden) state.
  bool get isSilent =>
      tangle <= 0.05 && findings.isEmpty && proposals.isEmpty;
}

/// A thin horizontal strip of glyphs that visualise the engine's read
/// of a file. Intended to sit at the top of a context menu as an
/// inert `custom` row.
class LogosGlyphStrip extends StatelessWidget {
  final AppTokens tokens;
  final LogosFileStatus status;

  const LogosGlyphStrip({
    super.key,
    required this.tokens,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    if (status.isSilent) {
      // Minimal empty state — a near-invisible separator hairline so
      // the menu doesn't shift when a file has no engine data.
      return SizedBox(
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.chromeBorder.withValues(alpha: 0.08),
          ),
        ),
      );
    }
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          // Tangle bar — the dominant visual. Width proportional to
          // contribution.
          Expanded(
            flex: 4,
            child: _TangleBar(tokens: tokens, value: status.tangle),
          ),
          const SizedBox(width: 8),
          // Finding glyphs — one per type present.
          for (final f in _uniqueFindingTypes(status.findings))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _FindingGlyph(tokens: tokens, kind: f),
            ),
          // Proposal indicators — one per type present.
          for (final kind in _uniqueProposalKinds(status.proposals))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _ProposalGlyph(tokens: tokens, kind: kind),
            ),
        ],
      ),
    );
  }

  static Iterable<Type> _uniqueFindingTypes(List<SpaghettiFinding> fs) {
    return fs.map((f) => f.runtimeType).toSet();
  }

  static Iterable<RefactorKind> _uniqueProposalKinds(
      List<RefactorProposal> ps) {
    return ps.map((p) => p.kind).toSet();
  }
}

/// Horizontal tangle bar — fill width encodes contribution, color
/// shifts from neutral (low) through amber toward warm red (high).
class _TangleBar extends StatelessWidget {
  final AppTokens tokens;
  final double value;
  const _TangleBar({required this.tokens, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0).toDouble();
    final fillColor = Color.lerp(
      tokens.accentBright.withValues(alpha: 0.35),
      tokens.stateConflicted.withValues(alpha: 0.9),
      v,
    )!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface2.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v.clamp(0.02, 1.0).toDouble(),
          child: Container(color: fillColor),
        ),
      ),
    );
  }
}

/// Finding glyph — a distinct shape per spaghetti pattern. All the
/// glyphs are intentionally simple: a circle outline for god class,
/// a filled dot for localized/dead, a two-node connector for bridges.
class _FindingGlyph extends StatelessWidget {
  final AppTokens tokens;
  final Type kind;
  const _FindingGlyph({required this.tokens, required this.kind});

  @override
  Widget build(BuildContext context) {
    final color = tokens.stateConflicted.withValues(alpha: 0.85);
    if (kind == GodClassFinding) {
      // Open circle — "mass without bound".
      return _GlyphBox(
        child: CustomPaint(
          painter: _OutlineCirclePainter(color: color),
        ),
      );
    }
    if (kind == DeadCodeFinding) {
      // Filled dot — localized, dense, stuck.
      return _GlyphBox(
        child: CustomPaint(
          painter: _FilledDotPainter(color: color),
        ),
      );
    }
    if (kind == CasimirBridgeFinding) {
      // Two-node connector — weak link between components.
      return _GlyphBox(
        child: CustomPaint(
          painter: _BridgePainter(color: color),
        ),
      );
    }
    // Fallback — a small square for unrecognised finding types.
    return _GlyphBox(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
        ),
      ),
    );
  }
}

/// Proposal glyph — tiny iconography for refactor kinds. Each one is
/// a simple stroke-drawing, no icon font dependency.
class _ProposalGlyph extends StatelessWidget {
  final AppTokens tokens;
  final RefactorKind kind;
  const _ProposalGlyph({required this.tokens, required this.kind});

  @override
  Widget build(BuildContext context) {
    final color = tokens.accentBright.withValues(alpha: 0.75);
    switch (kind) {
      case RefactorKind.merge:
        return _GlyphBox(
          child: CustomPaint(painter: _MergePainter(color: color)),
        );
      case RefactorKind.extract:
        return _GlyphBox(
          child: CustomPaint(painter: _ExtractPainter(color: color)),
        );
      case RefactorKind.decouple:
        return _GlyphBox(
          child: CustomPaint(painter: _DecouplePainter(color: color)),
        );
    }
  }
}

/// Fixed-size 14×14 box that glyph painters render into.
class _GlyphBox extends StatelessWidget {
  final Widget child;
  const _GlyphBox({required this.child});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 14, height: 14, child: child);
}

class _OutlineCirclePainter extends CustomPainter {
  final Color color;
  const _OutlineCirclePainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    c.drawCircle(Offset(s.width / 2, s.height / 2), s.width / 2 - 1, paint);
  }

  @override
  bool shouldRepaint(covariant _OutlineCirclePainter old) => old.color != color;
}

class _FilledDotPainter extends CustomPainter {
  final Color color;
  const _FilledDotPainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()..color = color;
    c.drawCircle(Offset(s.width / 2, s.height / 2), s.width / 2 - 2, paint);
  }

  @override
  bool shouldRepaint(covariant _FilledDotPainter old) => old.color != color;
}

class _BridgePainter extends CustomPainter {
  final Color color;
  const _BridgePainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final y = s.height / 2;
    // Two circles connected by a thin horizontal line.
    c.drawCircle(Offset(2.5, y), 1.5, paint);
    c.drawCircle(Offset(s.width - 2.5, y), 1.5, paint);
    c.drawLine(Offset(4, y), Offset(s.width - 4, y), paint);
  }

  @override
  bool shouldRepaint(covariant _BridgePainter old) => old.color != color;
}

class _MergePainter extends CustomPainter {
  final Color color;
  const _MergePainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    // Two arrows converging — simple V pointing right → one node.
    final mid = Offset(s.width - 2, s.height / 2);
    c.drawLine(const Offset(2, 2), mid, paint);
    c.drawLine(Offset(2, s.height - 2), mid, paint);
  }

  @override
  bool shouldRepaint(covariant _MergePainter old) => old.color != color;
}

class _ExtractPainter extends CustomPainter {
  final Color color;
  const _ExtractPainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    // One node splitting — / + \ from a single point on the left.
    final left = Offset(2, s.height / 2);
    c.drawLine(left, Offset(s.width - 2, 2), paint);
    c.drawLine(left, Offset(s.width - 2, s.height - 2), paint);
  }

  @override
  bool shouldRepaint(covariant _ExtractPainter old) => old.color != color;
}

class _DecouplePainter extends CustomPainter {
  final Color color;
  const _DecouplePainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    // Two nodes with an X between them — the crossed-out bond.
    final y = s.height / 2;
    c.drawCircle(Offset(3, y), 1.5, paint..style = PaintingStyle.stroke);
    c.drawCircle(Offset(s.width - 3, y), 1.5, paint);
    c.drawLine(Offset(5, y - 3), Offset(s.width - 5, y + 3), paint);
    c.drawLine(Offset(5, y + 3), Offset(s.width - 5, y - 3), paint);
  }

  @override
  bool shouldRepaint(covariant _DecouplePainter old) => old.color != color;
}
