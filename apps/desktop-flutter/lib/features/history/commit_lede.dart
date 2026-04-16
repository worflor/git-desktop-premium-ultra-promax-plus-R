import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/logos_git_state.dart';
import '../../app/repository_state.dart';
import '../../backend/commit_fingerprint.dart';
import '../../backend/dtos.dart';
import '../../ui/morph_text.dart';
import '../../ui/tokens.dart';

/// The metadata header for a commit, expressed as a single typographic
/// artifact: the subject text with an underline that ENCODES — not
/// labels — the commit's place in the repo.
/// Five signals carried by one element:
///   • Thickness of the underline       = combined importance
///   • Add/del horizontal split colors  = additions vs deletions ratio
///   • Dashed continuation past subject = neighborhood coherence
///                                        (this commit's files co-change)
///   • Top rim accent                   = your-tree overlap
///   • (Notches reserved for keystone files when xray is loaded.)
/// The principle: don't label what you can encode. Plain text says
/// what; visual form says how-much-it-matters.
class CommitLede extends StatelessWidget {
  final CommitDetailData detail;
  final String repoPath;
  final AppTokens tokens;
  final TextStyle subjectStyle;

  /// Optional precomputed structural signature for this commit. When
  /// non-null, the lede renders the 5×5 sigil glyph to the left of
  /// the subject. Lifted to the parent so the cache is shared across
  /// the timeline (every row that displays the same commit gets the
  /// same glyph for free).
  final CommitSignature? signature;

  const CommitLede({
    super.key,
    required this.detail,
    required this.repoPath,
    required this.tokens,
    required this.subjectStyle,
    this.signature,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final signals = _computeSignals(context);

    return LayoutBuilder(builder: (context, cons) {
      final avail = cons.maxWidth;
      // Measure the subject's actual rendered width so the painter knows
      // where the "main" line ends and the dashed continuation begins.
      final tp = TextPainter(
        text: TextSpan(text: detail.subject, style: subjectStyle),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: avail);
      final subjectW = math.min(tp.width, avail);

      return Semantics(
        label: _semanticDescription(signals),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThemeMorphText(detail.subject, style: subjectStyle),
            const SizedBox(height: 6),
            SizedBox(
              width: avail,
              // Reserve enough vertical room for the thickest possible
              // bar plus its rim accent above.
              height: 8,
              child: CustomPaint(
                painter: _LedePainter(
                  importance: signals.importance,
                  addShare: signals.addShare,
                  delShare: signals.delShare,
                  thread: signals.thread,
                  dirty: signals.dirty,
                  subjectWidth: subjectW,
                  // Hypercube poles — additions and deletions live on
                  // the same axis, just opposite ends. The dedicated
                  // hypercube tokens read more cohesive than the raw
                  // state-add/state-del pair.
                  addColor: t.hypercubePositive,
                  delColor: t.hypercubeNegative,
                  threadColor: t.textFaint,
                  dirtyColor: t.accentBright,
                  neutralColor: t.textFaint,
                  hasChurn: detail.additions + detail.deletions > 0,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  String _semanticDescription(_LedeSignals s) {
    final parts = <String>[detail.subject];
    if (s.importance > 0.7) {
      parts.add('high importance');
    } else if (s.importance > 0.4) {
      parts.add('moderate importance');
    }
    if (s.addShare > 0.7) {
      parts.add('mostly additions');
    } else if (s.delShare > 0.7) {
      parts.add('mostly deletions');
    }
    if (s.thread > 0.5) parts.add('tightly coupled files');
    if (s.dirty > 0) parts.add('overlaps your working tree');
    return parts.join(', ');
  }

  _LedeSignals _computeSignals(BuildContext context) {
    final logos = context.read<LogosGitState>().engineFor(repoPath);
    final status = context.read<RepositoryState>().status;
    final dirtySet = status?.files
            .map((f) => f.path.replaceAll('\\', '/'))
            .toSet() ??
        const <String>{};

    final totalChurn = detail.additions + detail.deletions;
    final addShare =
        totalChurn == 0 ? 0.5 : detail.additions / totalChurn;
    final delShare =
        totalChurn == 0 ? 0.5 : detail.deletions / totalChurn;

    // Importance: log-scaled churn into [0,1]. Calibrated so a typical
    // ~50-line commit reads thin and a ~2k+ line commit reads thick.
    // No magic threshold — just a curve that maps the order-of-magnitude
    // range humans encounter in practice into the visual range we have.
    final importance =
        (math.log(1 + totalChurn) / math.log(1 + 2000)).clamp(0.0, 1.0);

    // Thread = how tightly do this commit's own files co-change in the
    // repo's history (LogosGit's coherence). High coherence ⇒ this
    // commit is operating in a coherent region; the underline extends
    // beyond the subject to imply "ripples outward". Engine is
    // pre-warmed when the repo is opened so this is synchronous.
    var thread = 0.0;
    if (logos != null && detail.files.length >= 2) {
      final paths = detail.files
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();
      try {
        thread = logos.coherence(paths).clamp(0.0, 1.0);
      } catch (_) {
        thread = 0.0;
      }
    }

    // Dirty overlap: ratio of this commit's files that you're currently
    // editing. Subtle warm rim above the bar when nonzero.
    var dirtyHits = 0;
    for (final f in detail.files) {
      if (dirtySet.contains(f.path.replaceAll('\\', '/'))) dirtyHits++;
    }
    final dirty = detail.files.isEmpty
        ? 0.0
        : (dirtyHits / detail.files.length).clamp(0.0, 1.0);

    return _LedeSignals(
      importance: importance.toDouble(),
      addShare: addShare,
      delShare: delShare,
      thread: thread,
      dirty: dirty,
    );
  }
}

class _LedeSignals {
  final double importance;
  final double addShare;
  final double delShare;
  final double thread;
  final double dirty;
  const _LedeSignals({
    required this.importance,
    required this.addShare,
    required this.delShare,
    required this.thread,
    required this.dirty,
  });
}

class _LedePainter extends CustomPainter {
  final double importance; // 0..1
  final double addShare;   // 0..1
  final double delShare;   // 0..1
  final double thread;     // 0..1
  final double dirty;      // 0..1
  final double subjectWidth;
  final Color addColor;
  final Color delColor;
  final Color threadColor;
  final Color dirtyColor;
  final Color neutralColor;
  final bool hasChurn;

  _LedePainter({
    required this.importance,
    required this.addShare,
    required this.delShare,
    required this.thread,
    required this.dirty,
    required this.subjectWidth,
    required this.addColor,
    required this.delColor,
    required this.threadColor,
    required this.dirtyColor,
    required this.neutralColor,
    required this.hasChurn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lineH = 1.0 + 4.0 * importance; // 1px → 5px
    final yBase = size.height - lineH;
    final mainW = subjectWidth.clamp(0.0, size.width);

    if (hasChurn) {
      // Two-color split: deletions on the LEFT, additions on the RIGHT,
      // proportional to share of churn. Order encodes "what was torn
      // down → what was built up" left to right.
      final delW = mainW * delShare;
      final addW = mainW - delW;
      if (delW > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, yBase, delW, lineH),
          Paint()..color = delColor.withValues(alpha: 0.85),
        );
      }
      if (addW > 0) {
        canvas.drawRect(
          Rect.fromLTWH(delW, yBase, addW, lineH),
          Paint()..color = addColor.withValues(alpha: 0.85),
        );
      }
    } else {
      // Pure rename / mode-only / typechange: neutral hairline.
      canvas.drawRect(
        Rect.fromLTWH(0, yBase, mainW, lineH),
        Paint()..color = neutralColor.withValues(alpha: 0.55),
      );
    }

    // Dashed continuation past the subject — implies the commit's
    // files ripple outward into a coherent neighborhood.
    if (thread > 0.05 && mainW < size.width) {
      final tailStart = mainW + 6;
      final tailMax = size.width - tailStart;
      if (tailMax > 4) {
        final tailLen = tailMax * thread;
        final dashPaint = Paint()
          ..color = threadColor.withValues(alpha: 0.25 + 0.45 * thread)
          ..strokeWidth = math.max(1.0, lineH - 1)
          ..strokeCap = StrokeCap.round;
        const dashLen = 5.0;
        const gapLen = 4.0;
        var x = tailStart;
        final yMid = yBase + lineH / 2;
        final stop = tailStart + tailLen;
        while (x < stop) {
          final segEnd = math.min(x + dashLen, stop);
          canvas.drawLine(Offset(x, yMid), Offset(segEnd, yMid), dashPaint);
          x = segEnd + gapLen;
        }
      }
    }

    // Top rim accent — warm hairline above the bar when this commit's
    // files overlap your working tree. Intensity scales with overlap.
    if (dirty > 0) {
      final rimPaint = Paint()
        ..color = dirtyColor.withValues(alpha: 0.4 + 0.5 * dirty)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(0, yBase - 1.5),
        Offset(mainW, yBase - 1.5),
        rimPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LedePainter o) =>
      o.importance != importance ||
      o.addShare != addShare ||
      o.delShare != delShare ||
      o.thread != thread ||
      o.dirty != dirty ||
      o.subjectWidth != subjectWidth ||
      o.addColor != addColor ||
      o.delColor != delColor ||
      o.threadColor != threadColor ||
      o.dirtyColor != dirtyColor ||
      o.neutralColor != neutralColor ||
      o.hasChurn != hasChurn;
}
